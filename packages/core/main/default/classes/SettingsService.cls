/**
 * Reads and writes the org's settings.
 *
 * Each package owns a protected hierarchy custom setting (ADR-0017): Core's is
 * `Nonprofit_Settings__c` and a module ships its own, named on its Setting Definition rows.
 * Every write is validated against that object's own schema and against the shipped rows, is
 * audited as a Setting Change record, and clears the cached copy so the next transaction sees
 * the new value (canonical model Section 12, R-N3).
 */
@NamespaceAccessible
public with sharing class SettingsService {
    /** Core's own settings object, used when a caller or a row does not name one. */
    @NamespaceAccessible
    public static final String CORE_SETTINGS_OBJECT = 'Nonprofit_Settings__c';

    private static final String CACHE_PARTITION = 'local.NonprofitSettings';
    private static final String CACHE_KEY = 'orgDefaults';
    private static final String SETUP_OWNER = 'setupownerid';

    private static Nonprofit_Settings__c cachedSettings;
    private static Map<String, Map<String, Schema.SObjectField>> cachedFields = new Map<String, Map<String, Schema.SObjectField>>();

    /** Raised when a setting does not exist, is not editable here, or the value cannot be read. */
    @NamespaceAccessible
    public class SettingsException extends Exception {
    }

    /**
     * The org-level Core settings record, from the static cache, then the org cache, then the
     * platform. Never null: an org that has never saved gets an empty record.
     */
    @NamespaceAccessible
    public static Nonprofit_Settings__c getSettings() {
        if (cachedSettings != null) {
            return cachedSettings;
        }
        Nonprofit_Settings__c fromCache = readCache();
        if (fromCache != null) {
            cachedSettings = fromCache;
            return cachedSettings;
        }
        cachedSettings = Nonprofit_Settings__c.getOrgDefaults();
        writeCache(cachedSettings);
        return cachedSettings;
    }

    /** True when Core's settings object actually has the given key. */
    @NamespaceAccessible
    public static Boolean hasKey(String key) {
        return hasKey(CORE_SETTINGS_OBJECT, key);
    }

    /** True when the named settings object actually has the given key. */
    @NamespaceAccessible
    public static Boolean hasKey(String settingsObject, String key) {
        if (String.isBlank(key)) {
            return false;
        }
        Schema.SObjectType type = Schema.getGlobalDescribe().get(objectName(settingsObject));
        return type != null && fieldsByLocalName(type).containsKey(key.trim().toLowerCase());
    }

    /** The current value of one Core setting, or null. Throws when the key does not exist. */
    @NamespaceAccessible
    public static Object getValue(String key) {
        return getValue(CORE_SETTINGS_OBJECT, key);
    }

    /** The current value of one setting on the named settings object, or null. */
    @NamespaceAccessible
    public static Object getValue(String settingsObject, String key) {
        Schema.SObjectType type = settingsType(settingsObject);
        return orgDefault(type).get(fieldFor(type, key));
    }

    /**
     * Saves the given Core values, keyed by the API name of the Nonprofit Settings field.
     * Only keys that exist on the object and are listed in a Setting Definition row are
     * accepted. Returns the refreshed Core settings.
     */
    @NamespaceAccessible
    public static Nonprofit_Settings__c saveValues(Map<String, Object> values) {
        applyValues(CORE_SETTINGS_OBJECT, values, true);
        return getSettings();
    }

    /**
     * Saves the given values on the named settings object. The object has to be a hierarchy
     * custom setting named by at least one shipped Setting Definition row. Returns the saved
     * org-level record.
     */
    @NamespaceAccessible
    public static SObject saveValues(String settingsObject, Map<String, Object> values) {
        return applyValues(settingsObject, values, true);
    }

    /**
     * Saves one value the package itself owns, such as the setup checklist progress,
     * which has no Setting Definition row because it is not an editable setting.
     */
    @NamespaceAccessible
    public static Nonprofit_Settings__c saveSystemValue(String key, Object value) {
        applyValues(CORE_SETTINGS_OBJECT, new Map<String, Object>{ key => value }, false);
        return getSettings();
    }

    private static SObject applyValues(
        String settingsObject,
        Map<String, Object> values,
        Boolean requireDefinition
    ) {
        Schema.SObjectType type = settingsType(settingsObject);
        SObject record = orgDefault(type);
        if (values == null || values.isEmpty()) {
            return record;
        }
        String objectName = objectName(settingsObject);
        Set<String> definedKeys = requireDefinition ? definedKeys(objectName) : null;
        record = record.clone(true, true, true, true);
        if (record.Id == null) {
            record.put(SETUP_OWNER, UserInfo.getOrganizationId());
        }
        List<Setting_Change__c> changes = new List<Setting_Change__c>();
        Datetime changedAt = System.now();
        for (String key : values.keySet()) {
            Schema.SObjectField token = fieldFor(type, key);
            Schema.DescribeFieldResult field = token.getDescribe();
            String localName = field.getLocalName();
            if (requireDefinition && !definedKeys.contains(localName.toLowerCase())) {
                throw new SettingsException(System.Label.Core_Settings_UnknownKeyError);
            }
            Object oldValue = record.get(token);
            Object newValue = coerce(values.get(key), field);
            if (asText(oldValue) == asText(newValue)) {
                continue;
            }
            record.put(token, newValue);
            changes.add(
                new Setting_Change__c(
                    Setting_Name__c = objectName + '.' + localName,
                    Old_Value__c = asText(oldValue),
                    New_Value__c = asText(newValue),
                    Changed_By__c = UserInfo.getUserId(),
                    Changed_At__c = changedAt
                )
            );
        }
        if (changes.isEmpty()) {
            return record;
        }
        Database.upsert(record, AccessLevel.USER_MODE);
        Database.insert(changes, AccessLevel.USER_MODE);
        clearCaches();
        return record;
    }

    /** The org-level record of the given settings object, never null. */
    private static SObject orgDefault(Schema.SObjectType type) {
        if (isCoreSettings(type)) {
            return getSettings();
        }
        SObject record = SettingsRecordSelector.getOrgDefault(type);
        return record == null ? type.newSObject() : record;
    }

    private static Boolean isCoreSettings(Schema.SObjectType type) {
        return type == Nonprofit_Settings__c.SObjectType;
    }

    /**
     * The settings object a caller named, checked: it has to exist, be a hierarchy custom
     * setting, and either be Core's own or be named by a shipped Setting Definition row.
     */
    private static Schema.SObjectType settingsType(String settingsObject) {
        String name = objectName(settingsObject);
        if (
            !CORE_SETTINGS_OBJECT.equalsIgnoreCase(name) &&
            !registeredObjects().contains(name.toLowerCase())
        ) {
            throw new SettingsException(System.Label.Core_Settings_UnknownKeyError);
        }
        Schema.SObjectType type = Schema.getGlobalDescribe().get(name);
        if (type == null) {
            throw new SettingsException(System.Label.Core_Settings_UnknownKeyError);
        }
        Schema.DescribeSObjectResult describe = type.getDescribe(SObjectDescribeOptions.DEFERRED);
        if (!describe.isCustomSetting() || !describe.fields.getMap().containsKey(SETUP_OWNER)) {
            throw new SettingsException(System.Label.Core_Settings_UnknownKeyError);
        }
        return type;
    }

    private static String objectName(String settingsObject) {
        return String.isBlank(settingsObject) ? CORE_SETTINGS_OBJECT : settingsObject.trim();
    }

    private static Set<String> registeredObjects() {
        Set<String> names = new Set<String>();
        for (Setting_Definition__mdt definition : SettingDefinitionSelector.getAll()) {
            names.add(objectName(definition.Settings_Object__c).toLowerCase());
        }
        return names;
    }

    /** Forgets both the static and the org cache, so the next read comes from the platform. */
    public static void clearCaches() {
        cachedSettings = null;
        Cache.OrgPartition partition = partition();
        if (partition == null) {
            return;
        }
        try {
            partition.remove(CACHE_KEY);
        } catch (Exception e) {
            ErrorLogger.log(e, 'Nonprofit Settings cache');
        }
    }

    private static Set<String> definedKeys(String objectName) {
        Set<String> keys = new Set<String>();
        for (Setting_Definition__mdt definition : SettingDefinitionSelector.getAll()) {
            Boolean sameObject = objectName(definition.Settings_Object__c)
                .equalsIgnoreCase(objectName);
            if (sameObject && String.isNotBlank(definition.Setting_Key__c)) {
                keys.add(definition.Setting_Key__c.trim().toLowerCase());
            }
        }
        return keys;
    }

    private static Schema.SObjectField fieldFor(Schema.SObjectType type, String key) {
        Schema.SObjectField token = String.isBlank(key)
            ? null
            : fieldsByLocalName(type).get(key.trim().toLowerCase());
        if (token == null) {
            throw new SettingsException(System.Label.Core_Settings_UnknownKeyError);
        }
        return token;
    }

    private static Map<String, Schema.SObjectField> fieldsByLocalName(Schema.SObjectType type) {
        Schema.DescribeSObjectResult describe = type.getDescribe(SObjectDescribeOptions.DEFERRED);
        String name = describe.getName();
        if (cachedFields.containsKey(name)) {
            return cachedFields.get(name);
        }
        Map<String, Schema.SObjectField> fields = new Map<String, Schema.SObjectField>();
        for (Schema.SObjectField token : describe.fields.getMap().values()) {
            fields.put(token.getDescribe().getLocalName().toLowerCase(), token);
        }
        cachedFields.put(name, fields);
        return fields;
    }

    private static Object coerce(Object raw, Schema.DescribeFieldResult field) {
        Schema.DisplayType kind = field.getType();
        String text = raw == null ? null : String.valueOf(raw).trim();
        if (kind == Schema.DisplayType.BOOLEAN) {
            return raw instanceof Boolean
                ? (Boolean) raw
                : (String.isBlank(text) ? false : Boolean.valueOf(text));
        }
        if (String.isBlank(text)) {
            return null;
        }
        Object typed = parse(kind, text);
        if (typed != null) {
            return typed;
        }
        Integer maximum = field.getLength();
        if (maximum > 0 && text.length() > maximum) {
            throw new SettingsException(System.Label.Core_Settings_InvalidValueError);
        }
        return text;
    }

    /** The value a non-text setting holds, or null when the setting is text after all. */
    private static Object parse(Schema.DisplayType kind, String text) {
        try {
            if (kind == Schema.DisplayType.INTEGER) {
                return Integer.valueOf(text);
            }
            if (isNumeric(kind)) {
                return Decimal.valueOf(text);
            }
            if (kind == Schema.DisplayType.DATETIME) {
                return (Datetime) JSON.deserialize('"' + text + '"', Datetime.class);
            }
            if (kind == Schema.DisplayType.DATE) {
                return (Date) JSON.deserialize('"' + text + '"', Date.class);
            }
        } catch (Exception e) {
            throw new SettingsException(System.Label.Core_Settings_InvalidValueError);
        }
        return null;
    }

    private static Boolean isNumeric(Schema.DisplayType kind) {
        return kind == Schema.DisplayType.DOUBLE ||
            kind == Schema.DisplayType.CURRENCY ||
            kind == Schema.DisplayType.PERCENT;
    }

    /** One text form for every value type, so old and new can be compared and audited. */
    public static String asText(Object value) {
        if (value == null) {
            return '';
        }
        if (value instanceof Datetime) {
            return ((Datetime) value).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        }
        return String.valueOf(value);
    }

    private static Cache.OrgPartition partition() {
        try {
            return Cache.Org.getPartition(CACHE_PARTITION);
        } catch (Exception e) {
            return null;
        }
    }

    private static Nonprofit_Settings__c readCache() {
        Cache.OrgPartition partition = partition();
        if (partition == null) {
            return null;
        }
        try {
            return (Nonprofit_Settings__c) partition.get(CACHE_KEY);
        } catch (Exception e) {
            return null;
        }
    }

    private static void writeCache(Nonprofit_Settings__c record) {
        Cache.OrgPartition partition = partition();
        if (partition == null || record == null) {
            return;
        }
        try {
            partition.put(CACHE_KEY, record);
        } catch (Exception e) {
            ErrorLogger.log(e, 'Nonprofit Settings cache');
        }
    }
}

/**
 * Reads and writes the org's Nonprofit Settings.
 *
 * Every write is validated against the object's own schema and against the shipped
 * Setting Definition rows, is audited as a Setting Change record, and clears the cached
 * copy so the next transaction sees the new value (canonical model Section 12, R-N3).
 */
public with sharing class SettingsService {
    private static final String CACHE_PARTITION = 'local.NonprofitSettings';
    private static final String CACHE_KEY = 'orgDefaults';

    private static Nonprofit_Settings__c cachedSettings;
    private static Map<String, Schema.SObjectField> cachedFields;

    /** Raised when a setting does not exist, is not editable here, or the value cannot be read. */
    public class SettingsException extends Exception {
    }

    /**
     * The org-level settings record, from the static cache, then the org cache, then the
     * platform. Never null: an org that has never saved gets an empty record.
     */
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

    /** True when this org's settings object actually has the given key. */
    public static Boolean hasKey(String key) {
        return String.isNotBlank(key) && fieldsByLocalName().containsKey(key.trim().toLowerCase());
    }

    /** The current value of one setting, or null. Throws when the key does not exist. */
    public static Object getValue(String key) {
        Schema.SObjectField token = fieldFor(key);
        return getSettings().get(token);
    }

    /**
     * Saves the given values, keyed by the API name of the Nonprofit Settings field.
     * Only keys that exist on the object and are listed in a Setting Definition row are
     * accepted. Returns the refreshed settings.
     */
    public static Nonprofit_Settings__c saveValues(Map<String, Object> values) {
        return applyValues(values, true);
    }

    /**
     * Saves one value the package itself owns, such as the setup checklist progress,
     * which has no Setting Definition row because it is not an editable setting.
     */
    public static Nonprofit_Settings__c saveSystemValue(String key, Object value) {
        return applyValues(new Map<String, Object>{ key => value }, false);
    }

    private static Nonprofit_Settings__c applyValues(
        Map<String, Object> values,
        Boolean requireDefinition
    ) {
        if (values == null || values.isEmpty()) {
            return getSettings();
        }
        Set<String> definedKeys = requireDefinition ? definedKeys() : null;
        Nonprofit_Settings__c record = Nonprofit_Settings__c.getOrgDefaults();
        if (record.Id == null) {
            record.SetupOwnerId = UserInfo.getOrganizationId();
        }
        List<Setting_Change__c> changes = new List<Setting_Change__c>();
        Datetime changedAt = System.now();
        for (String key : values.keySet()) {
            Schema.SObjectField token = fieldFor(key);
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
                    Setting_Name__c = localName,
                    Old_Value__c = asText(oldValue),
                    New_Value__c = asText(newValue),
                    Changed_By__c = UserInfo.getUserId(),
                    Changed_At__c = changedAt
                )
            );
        }
        if (changes.isEmpty()) {
            return getSettings();
        }
        if (record.Id == null) {
            Database.insert(record, AccessLevel.USER_MODE);
        } else {
            Database.update(record, AccessLevel.USER_MODE);
        }
        Database.insert(changes, AccessLevel.USER_MODE);
        clearCaches();
        return getSettings();
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

    private static Set<String> definedKeys() {
        Set<String> keys = new Set<String>();
        for (Setting_Definition__mdt definition : SettingDefinitionSelector.getAll()) {
            if (String.isNotBlank(definition.Setting_Key__c)) {
                keys.add(definition.Setting_Key__c.trim().toLowerCase());
            }
        }
        return keys;
    }

    private static Schema.SObjectField fieldFor(String key) {
        Schema.SObjectField token = String.isBlank(key)
            ? null
            : fieldsByLocalName().get(key.trim().toLowerCase());
        if (token == null) {
            throw new SettingsException(System.Label.Core_Settings_UnknownKeyError);
        }
        return token;
    }

    private static Map<String, Schema.SObjectField> fieldsByLocalName() {
        if (cachedFields != null) {
            return cachedFields;
        }
        cachedFields = new Map<String, Schema.SObjectField>();
        Schema.DescribeSObjectResult describe = Nonprofit_Settings__c.SObjectType.getDescribe(
            SObjectDescribeOptions.DEFERRED
        );
        for (Schema.SObjectField token : describe.fields.getMap().values()) {
            cachedFields.put(token.getDescribe().getLocalName().toLowerCase(), token);
        }
        return cachedFields;
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

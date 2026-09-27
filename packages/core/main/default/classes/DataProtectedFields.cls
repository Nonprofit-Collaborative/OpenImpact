/**
 * What data management never writes (plan Section 4.9, "Fields that can never be bulk updated
 * or imported over"; canonical model R-IT12): the package's own bookkeeping objects, the fields
 * the package or the platform keeps, and a household's name.
 *
 * One class for every tool that writes many records at once: a one-object import (C-33) today,
 * bulk update (C-35) next. The list is built at run time from describe and the Rollup
 * Definitions, so a rollup an administrator or a module adds later is protected without code,
 * and Core names no object outside its own: the objects of other packages are matched by name
 * as text (ADR-0013, ADR-0014).
 *
 * This decides protection, not access. Whether the running user may read, create or edit an
 * object or field is still asked of describe by the caller, and every write is in user mode.
 * The receipt and closed-period locks are not listed: their triggers still run on the save and
 * refuse a locked gift's change themselves (ADR-0010, ADR-0053).
 */
@NamespaceAccessible
public with sharing class DataProtectedFields {
    /**
     * The package's own bookkeeping objects, by their names without a namespace: imports and the
     * journal, the error log, settings and setting changes, automation settings, rollup
     * definitions, and receipts with their runs and number series. Named as text because some
     * belong to modules Core may not reference (ADR-0014).
     */
    private static final Set<String> BOOKKEEPING = new Set<String>{
        'import_template__c',
        'import_batch__c',
        'import_row__c',
        'import_journal__c',
        'error_log__c',
        'barn_settings__c',
        'setting_change__c',
        'automation_setting__c',
        'rollup_definition__c',
        'giving_settings__c',
        'connect_settings__c',
        'receipt__c',
        'receipt_run__c',
        'receipt_number_sequence__c'
    };

    /**
     * Suffixes of objects that are never records a person loads: custom metadata, platform
     * events, big and external objects, and the share, history, feed and change event objects
     * the platform keeps beside another object (AccountShare, Widget__History).
     */
    private static final List<String> NEVER_LOADED_SUFFIXES = new List<String>{
        '__mdt',
        '__e',
        '__b',
        '__x',
        'share',
        'history',
        'feed',
        'changeevent'
    };

    /**
     * Salesforce setup and security objects, by name: users, groups, profiles, roles, permission
     * sets and their assignments, record types, queues and the organization itself. Plan Section
     * 4.9 leaves permission management and the rest of Setup to Setup, and these are what an
     * administrator could otherwise assign or change in bulk here.
     */
    private static final Set<String> SETUP = new Set<String>{
        'user',
        'group',
        'groupmember',
        'queuesobject',
        'profile',
        'userrole',
        'permissionset',
        'permissionsetassignment',
        'permissionsetgroup',
        'permissionsetgroupcomponent',
        'permissionsetlicenseassign',
        'setupentityaccess',
        'objectpermissions',
        'fieldpermissions',
        'recordtype',
        'organization',
        'userlicense',
        'userpackagelicense',
        'networkmember'
    };

    /** Fields the package keeps on people and accounts (households, R-H8, ADR-0044, R-AF2). */
    private static final Set<String> KEPT_ON_PEOPLE_AND_ACCOUNTS = new Set<String>{
        'household_formal_greeting__c',
        'household_informal_greeting__c',
        'member_count__c',
        'primary_contact__c',
        'primary_affiliation__c'
    };

    /** The batch tag, on any object that carries it (R-IB3). */
    private static final String TAG_FIELD = 'created_by_import_batch__c';

    /** The suffix of every package field that says when something was last calculated. */
    private static final String LAST_CALCULATED_SUFFIX = 'last_calculated__c';

    /** Fields the platform keeps on every record. */
    private static final Set<String> SYSTEM_FIELDS = new Set<String>{
        'id',
        'isdeleted',
        'createddate',
        'createdbyid',
        'lastmodifieddate',
        'lastmodifiedbyid',
        'systemmodstamp',
        'lastactivitydate',
        'lastvieweddate',
        'lastreferenceddate'
    };

    /** Set only by tests: the Rollup Definitions to read in place of the org's. */
    @TestVisible
    private static List<Rollup_Definition__c> definitionsOverride;

    /** The protected field names of each object, worked out once per transaction. */
    private static final Map<Schema.SObjectType, Set<String>> PROTECTED_BY_TYPE = new Map<Schema.SObjectType, Set<String>>();

    /** The rollup target fields by object, read once per transaction. */
    private static Map<String, Set<String>> rollupTargets;

    /**
     * Why records of this object can never be loaded or bulk updated, or null when they can.
     * An object that does not exist, the package's own bookkeeping, Salesforce setup and security
     * objects, custom settings, custom metadata, platform events, big and external objects, and
     * share, history, feed and change event objects are refused. Access is the caller's question.
     */
    @NamespaceAccessible
    public static String objectRefusal(Schema.SObjectType type) {
        if (type == null) {
            return Label.Core_Data_ObjectUnknown;
        }
        Schema.DescribeSObjectResult described = type.getDescribe(SObjectDescribeOptions.DEFERRED);
        String name = described.getName().toLowerCase();
        if (described.isCustom() && BOOKKEEPING.contains(ownLocalName(name))) {
            return String.format(
                Label.Core_Data_ObjectBookkeeping,
                new List<String>{ described.getLabelPlural() }
            );
        }
        if (!described.isCustom() && SETUP.contains(name)) {
            return String.format(
                Label.Core_Data_ObjectSetup,
                new List<String>{ described.getLabelPlural() }
            );
        }
        if (described.isCustomSetting() || neverLoaded(name)) {
            return String.format(
                Label.Core_Data_ObjectNotLoadable,
                new List<String>{ described.getLabelPlural() }
            );
        }
        return null;
    }

    /**
     * The fields of this object that are never written, by their API names in lower case: every
     * Rollup Definition target on it, the fields the package keeps, formula and auto-number
     * fields, and the fields the platform keeps.
     */
    @NamespaceAccessible
    public static Set<String> fieldNames(Schema.SObjectType type) {
        if (type == null) {
            return new Set<String>();
        }
        if (!PROTECTED_BY_TYPE.containsKey(type)) {
            PROTECTED_BY_TYPE.put(type, computeProtected(type));
        }
        return PROTECTED_BY_TYPE.get(type);
    }

    /** Whether this field of this object is never written. */
    @NamespaceAccessible
    public static Boolean isProtected(Schema.SObjectType type, String fieldName) {
        return String.isNotBlank(fieldName) &&
            fieldNames(type).contains(fieldName.trim().toLowerCase());
    }

    /**
     * Whether this field is never written on this particular record: a household's name, which
     * the household naming patterns keep (R-H8). An organization's name is not protected.
     */
    @NamespaceAccessible
    public static Boolean isProtectedOnRecord(
        Schema.SObjectType type,
        String fieldName,
        Id recordTypeId
    ) {
        return type == Account.SObjectType &&
            'name'.equalsIgnoreCase(String.isBlank(fieldName) ? '' : fieldName.trim()) &&
            recordTypeId != null &&
            recordTypeId == HouseholdService.householdRecordTypeId();
    }

    private static Set<String> computeProtected(Schema.SObjectType type) {
        Set<String> result = new Set<String>();
        Schema.DescribeSObjectResult described = type.getDescribe(SObjectDescribeOptions.DEFERRED);
        Boolean peopleOrAccounts = type == Account.SObjectType || type == Contact.SObjectType;
        Map<String, Schema.SObjectField> fields = described.fields.getMap();
        Set<String> targets = rollupTargetsOf(described.getName());
        for (String key : fields.keySet()) {
            Schema.DescribeFieldResult field = fields.get(key).getDescribe();
            String name = field.getName().toLowerCase();
            // The package's own fields only: a subscriber's field of the same local name is theirs.
            String own = field.isCustom() ? ownLocalName(name) : null;
            if (
                SYSTEM_FIELDS.contains(name) ||
                field.isCalculated() ||
                field.isAutoNumber() ||
                targets.contains(name) ||
                targets.contains(localName(name)) ||
                (own != null &&
                (own == TAG_FIELD ||
                own.endsWith(LAST_CALCULATED_SUFFIX) ||
                (peopleOrAccounts && KEPT_ON_PEOPLE_AND_ACCOUNTS.contains(own))))
            ) {
                result.add(name);
            }
        }
        return result;
    }

    /**
     * The target fields of every Rollup Definition, active or not, on the object of this name,
     * in lower case, as written and without a namespace, so either form matches.
     */
    private static Set<String> rollupTargetsOf(String objectName) {
        if (rollupTargets == null) {
            rollupTargets = new Map<String, Set<String>>();
            List<Rollup_Definition__c> definitions = definitionsOverride != null
                ? definitionsOverride
                : RollupSelector.selectAll();
            for (Rollup_Definition__c definition : definitions) {
                if (
                    String.isBlank(definition.Target_Object__c) ||
                    String.isBlank(definition.Target_Field__c)
                ) {
                    continue;
                }
                String target = localName(definition.Target_Object__c.trim().toLowerCase());
                if (!rollupTargets.containsKey(target)) {
                    rollupTargets.put(target, new Set<String>());
                }
                String field = definition.Target_Field__c.trim().toLowerCase();
                rollupTargets.get(target).add(field);
                rollupTargets.get(target).add(localName(field));
            }
        }
        String key = localName(objectName.toLowerCase());
        return rollupTargets.containsKey(key) ? rollupTargets.get(key) : new Set<String>();
    }

    /**
     * A lower case API name without this package's namespace when it is the package's own, and
     * null when it belongs to another namespace. With no namespace, as today, every name is.
     */
    private static String ownLocalName(String lowerCaseName) {
        String prefix = NamespaceUtil.prefix().toLowerCase();
        if (String.isBlank(prefix)) {
            return lowerCaseName;
        }
        return lowerCaseName.startsWith(prefix) ? lowerCaseName.removeStart(prefix) : null;
    }

    /** A lower case API name without this package's namespace. */
    private static String localName(String lowerCaseName) {
        String prefix = NamespaceUtil.prefix().toLowerCase();
        return String.isNotBlank(prefix) && lowerCaseName.startsWith(prefix)
            ? lowerCaseName.removeStart(prefix)
            : lowerCaseName;
    }

    private static Boolean neverLoaded(String lowerCaseName) {
        for (String suffix : NEVER_LOADED_SUFFIXES) {
            if (lowerCaseName.endsWith(suffix)) {
                return true;
            }
        }
        return false;
    }
}

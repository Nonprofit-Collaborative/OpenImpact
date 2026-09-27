/**
 * What a data job may never write (canonical model R-IB15, plan Section 4.9, ADR-0047 amended,
 * C-35 decision 4): fields the package computes, formula, auto-number and system fields, fields
 * the running user may not edit, and every record of the package's own bookkeeping objects.
 *
 * The list is worked out when it is asked for, from describe and from the Rollup Definitions,
 * so a rollup an administrator adds tomorrow is protected without a code change. Answers are
 * cached for the transaction.
 *
 * Fields locked by an issued receipt are not here on purpose: the receipt lock triggers refuse
 * the save, and the job journals the refusal (ADR-0010, ADR-0024).
 *
 * Bulk update (C-35) uses it today; an import that loads one object (C-33) can ask the same
 * questions.
 */
@NamespaceAccessible
public with sharing class DataProtectedFields {
    /**
     * The package's own bookkeeping objects, by API name without a namespace. Giving's receipt
     * objects are named here as text, so Core holds no reference to them and an org without
     * Giving is unaffected (ADR-0014).
     */
    private static final Set<String> BOOKKEEPING_OBJECTS = new Set<String>{
        'Import_Batch__c',
        'Import_Row__c',
        'Import_Journal__c',
        'Import_Template__c',
        'Error_Log__c',
        'Error_Log_Event__e',
        'Setting_Change__c',
        'Automation_Setting__c',
        'Rollup_Definition__c',
        'Duplicate_Dismissal__c',
        'Barn_Settings__c',
        'Receipt__c',
        'Receipt_Run__c',
        'Receipt_Number_Sequence__c'
    };

    /** Fields the package computes on any object that carries them. */
    private static final Set<String> COMPUTED_ANYWHERE = new Set<String>{
        'Rollups_Last_Calculated__c',
        'Created_By_Import_Batch__c',
        'Sample_Data_Key__c'
    };

    /**
     * Fields the package computes on one object: the household's name and greetings and member
     * count (R-H4 to R-H11), a person's primary affiliation (R-AF2), and a saved query's
     * document, which only Find writes (R-Q6). The Account name is the household name.
     */
    private static final Map<String, Set<String>> COMPUTED_ON = new Map<String, Set<String>>{
        'Account' => new Set<String>{
            'Name',
            'Household_Formal_Greeting__c',
            'Household_Informal_Greeting__c',
            'Member_Count__c'
        },
        'Contact' => new Set<String>{ 'Primary_Affiliation__c' },
        'Saved_Query__c' => new Set<String>{ 'Query_JSON__c' }
    };

    private static final List<String> SYSTEM_SUFFIXES = new List<String>{
        '__mdt',
        '__e',
        '__b',
        '__x',
        'share',
        'history',
        'feed',
        'changeevent'
    };

    /** Rollup Definition targets, by lower-case object name, then lower-case field names. */
    private static Map<String, Set<String>> rollupTargets;
    private static Set<String> qualifiedBookkeeping;

    /**
     * Why no record of this object may be written by a data job, or null when records of it
     * may be (each field is then asked about on its own).
     */
    @NamespaceAccessible
    public static String objectReason(Schema.SObjectType type) {
        Schema.DescribeSObjectResult described = type.getDescribe(SObjectDescribeOptions.DEFERRED);
        String name = described.getName();
        if (bookkeeping().contains(name.toLowerCase())) {
            return Label.Core_BulkUpdate_ReasonBookkeeping;
        }
        String lower = name.toLowerCase();
        if (described.isCustomSetting()) {
            return Label.Core_BulkUpdate_ReasonBookkeeping;
        }
        for (String suffix : SYSTEM_SUFFIXES) {
            if (lower.endsWith(suffix)) {
                return Label.Core_BulkUpdate_ReasonSystemObject;
            }
        }
        if (!described.isUpdateable()) {
            return Label.Core_BulkUpdate_ReasonNoObjectAccess;
        }
        return null;
    }

    /** Why this field may not be written by a data job, or null when it may. */
    @NamespaceAccessible
    public static String fieldReason(Schema.SObjectType type, Schema.DescribeFieldResult field) {
        String objectName = type.getDescribe(SObjectDescribeOptions.DEFERRED).getName();
        if (isComputed(objectName, field.getName())) {
            return Label.Core_BulkUpdate_ReasonComputed;
        }
        if (field.isCalculated()) {
            return Label.Core_BulkUpdate_ReasonFormula;
        }
        if (field.isAutoNumber()) {
            return Label.Core_BulkUpdate_ReasonAutoNumber;
        }
        if (!field.isUpdateable()) {
            // A field an administrator could grant edit access to is the person's access; one
            // nobody can be granted is the platform's own.
            return field.isPermissionable()
                ? Label.Core_BulkUpdate_ReasonNoFieldAccess
                : Label.Core_BulkUpdate_ReasonSystem;
        }
        return null;
    }

    /**
     * Whether the package computes this field: a Rollup Definition target on this object, or
     * one of the fields named above. Names are compared both as written and with this
     * package's namespace, so the answer holds before and after the namespace is registered.
     */
    @NamespaceAccessible
    public static Boolean isComputed(String objectName, String fieldName) {
        String objectKey = objectName.toLowerCase();
        String fieldKey = fieldName.toLowerCase();
        for (String name : COMPUTED_ANYWHERE) {
            if (matches(fieldKey, name)) {
                return true;
            }
        }
        for (String owner : COMPUTED_ON.keySet()) {
            if (matches(objectKey, owner)) {
                for (String name : COMPUTED_ON.get(owner)) {
                    if (matches(fieldKey, name)) {
                        return true;
                    }
                }
            }
        }
        Set<String> targets = rollupTargets().get(objectKey);
        return targets != null && targets.contains(fieldKey);
    }

    private static Boolean matches(String describedLower, String packagedName) {
        return describedLower == packagedName.toLowerCase() ||
            describedLower == NamespaceUtil.qualify(packagedName).toLowerCase();
    }

    private static Set<String> bookkeeping() {
        if (qualifiedBookkeeping == null) {
            qualifiedBookkeeping = new Set<String>();
            for (String name : BOOKKEEPING_OBJECTS) {
                qualifiedBookkeeping.add(name.toLowerCase());
                qualifiedBookkeeping.add(NamespaceUtil.qualify(name).toLowerCase());
            }
        }
        return qualifiedBookkeeping;
    }

    /**
     * Every Rollup Definition's target, active or not, read in system mode: a definition the
     * person cannot see still computes the field, and a protection that depended on who is
     * asking would protect nothing (ADR-0021, a read that feeds a package decision, not one
     * shown to anybody). Each name is held as written and qualified.
     */
    private static Map<String, Set<String>> rollupTargets() {
        if (rollupTargets == null) {
            rollupTargets = new Map<String, Set<String>>();
            for (Rollup_Definition__c definition : RollupSelector.selectAll()) {
                if (
                    String.isBlank(definition.Target_Object__c) ||
                    String.isBlank(definition.Target_Field__c)
                ) {
                    continue;
                }
                for (
                    String objectName : new List<String>{
                        definition.Target_Object__c.trim(),
                        NamespaceUtil.qualify(definition.Target_Object__c.trim())
                    }
                ) {
                    String key = objectName.toLowerCase();
                    if (!rollupTargets.containsKey(key)) {
                        rollupTargets.put(key, new Set<String>());
                    }
                    rollupTargets.get(key).add(definition.Target_Field__c.trim().toLowerCase());
                    rollupTargets.get(key)
                        .add(
                            NamespaceUtil.qualify(definition.Target_Field__c.trim()).toLowerCase()
                        );
                }
            }
        }
        return rollupTargets;
    }
}

/**
 * Every query the duplicate scan and the Duplicates panel make (C-20).
 *
 * Almost all of them read records the platform owns: `DuplicateRule` says which rules the org
 * has switched on, and `DuplicateRecordSet` with `DuplicateRecordItem` holds what they found.
 * Canonical model R-DP1 is why there is nothing else to read.
 *
 * Everything is queried in user mode. A suggestion names two records, and a person who cannot
 * see one of them is never shown it, let alone offered a merge of it.
 */
public with sharing class DuplicateSelector {
    /** The objects duplicates are reviewed for, in the order a scan covers them. */
    public static final List<String> REVIEWED_OBJECTS = new List<String>{ 'Contact', 'Account' };

    /** Every duplicate rule for these objects, active or not. */
    public static List<DuplicateRule> rulesFor(Set<String> objectNames) {
        if (objectNames == null || objectNames.isEmpty()) {
            return new List<DuplicateRule>();
        }
        return [
            SELECT Id, DeveloperName, MasterLabel, SobjectType, IsActive
            FROM DuplicateRule
            WHERE SobjectType IN :objectNames
            WITH USER_MODE
            ORDER BY SobjectType, MasterLabel
        ];
    }

    /** The active rules for these objects, identifier by developer name. */
    public static Map<String, Id> activeRuleIdsByName(Set<String> objectNames) {
        Map<String, Id> result = new Map<String, Id>();
        for (DuplicateRule rule : rulesFor(objectNames)) {
            if (rule.IsActive == true) {
                result.put(rule.DeveloperName, rule.Id);
            }
        }
        return result;
    }

    /** The objects among these that have at least one active rule. */
    public static Set<String> objectsWithActiveRules(Set<String> objectNames) {
        Set<String> result = new Set<String>();
        for (DuplicateRule rule : rulesFor(objectNames)) {
            if (rule.IsActive == true) {
                result.add(rule.SobjectType);
            }
        }
        return result;
    }

    /**
     * The suggestions waiting to be looked at, newest first, with their records. A set written
     * when somebody saved past an alert and a set written by the scan are the same thing to the
     * person reviewing them. Sets for other objects (leads) and sets a merge has emptied down to
     * one record are left out.
     */
    public static List<DuplicateRecordSet> openSets(Integer max) {
        Integer limitRows = max == null || max <= 0 ? 50 : max;
        List<String> objects = REVIEWED_OBJECTS;
        return [
            SELECT
                Id,
                CreatedDate,
                DuplicateRule.MasterLabel,
                (SELECT Id, RecordId FROM DuplicateRecordItems ORDER BY CreatedDate)
            FROM DuplicateRecordSet
            WHERE
                RecordCount > 1
                AND (DuplicateRuleId = NULL
                OR DuplicateRule.SobjectType IN :objects)
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :limitRows
        ];
    }

    /** These suggestions, with their records. */
    public static List<DuplicateRecordSet> setsByIds(Set<Id> setIds) {
        if (setIds == null || setIds.isEmpty()) {
            return new List<DuplicateRecordSet>();
        }
        return [
            SELECT Id, (SELECT Id, RecordId FROM DuplicateRecordItems ORDER BY CreatedDate)
            FROM DuplicateRecordSet
            WHERE Id IN :setIds
            WITH USER_MODE
        ];
    }

    /** The suggestion entries naming any of these records. */
    public static List<DuplicateRecordItem> itemsForRecords(Set<Id> recordIds) {
        if (recordIds == null || recordIds.isEmpty()) {
            return new List<DuplicateRecordItem>();
        }
        return [
            SELECT Id, DuplicateRecordSetId, RecordId
            FROM DuplicateRecordItem
            WHERE RecordId IN :recordIds
            WITH USER_MODE
        ];
    }

    /** Every entry in these suggestions. */
    public static List<DuplicateRecordItem> itemsForSets(Set<Id> setIds) {
        if (setIds == null || setIds.isEmpty()) {
            return new List<DuplicateRecordItem>();
        }
        return [
            SELECT Id, DuplicateRecordSetId, RecordId
            FROM DuplicateRecordItem
            WHERE DuplicateRecordSetId IN :setIds
            WITH USER_MODE
        ];
    }

    /** The pairs among these that somebody already said are not duplicates. */
    public static Set<String> dismissedKeys(Set<String> pairKeys) {
        Set<String> result = new Set<String>();
        if (pairKeys == null || pairKeys.isEmpty()) {
            return result;
        }
        for (Duplicate_Dismissal__c dismissal : [
            SELECT Pair_Key__c
            FROM Duplicate_Dismissal__c
            WHERE Pair_Key__c IN :pairKeys
            WITH USER_MODE
        ]) {
            result.add(dismissal.Pair_Key__c);
        }
        return result;
    }

    /** How many pairs have been dismissed, for the count on the panel. */
    public static Integer dismissalCount() {
        return [SELECT COUNT() FROM Duplicate_Dismissal__c WITH USER_MODE];
    }

    /** The latest runs of the scan, so the panel can say whether one is going on. */
    public static List<AsyncApexJob> recentScanJobs(String className, Integer max) {
        Integer limitRows = max == null || max <= 0 ? 5 : max;
        return [
            SELECT Id, Status, CreatedDate, CompletedDate
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex' AND ApexClass.Name = :className
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :limitRows
        ];
    }

    /** The households among these account identifiers. */
    public static Set<Id> householdIds(Set<Id> accountIds) {
        Id householdType = HouseholdService.householdRecordTypeId();
        if (accountIds == null || accountIds.isEmpty() || householdType == null) {
            return new Set<Id>();
        }
        return new Map<Id, Account>(
                [
                    SELECT Id
                    FROM Account
                    WHERE Id IN :accountIds AND RecordTypeId = :householdType
                    WITH USER_MODE
                ]
            )
            .keySet();
    }

    /** The households among these identifiers, as the panel names them. */
    public static List<Account> householdsByIds(Set<Id> recordIds) {
        Id householdType = HouseholdService.householdRecordTypeId();
        if (recordIds == null || recordIds.isEmpty() || householdType == null) {
            return new List<Account>();
        }
        return [
            SELECT Id, Name, BillingCity, BillingPostalCode
            FROM Account
            WHERE Id IN :recordIds AND RecordTypeId = :householdType
            WITH USER_MODE
        ];
    }

    /** The people among these identifiers, as the panel names them. */
    public static List<Contact> contactsByIds(Set<Id> recordIds) {
        if (recordIds == null || recordIds.isEmpty()) {
            return new List<Contact>();
        }
        return [
            SELECT Id, Name, Email, MailingPostalCode, Account.Name
            FROM Contact
            WHERE Id IN :recordIds
            WITH USER_MODE
        ];
    }
}

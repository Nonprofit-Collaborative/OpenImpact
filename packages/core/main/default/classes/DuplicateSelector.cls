/**
 * Every query the duplicate review page and the duplicate scan make (C-20).
 *
 * Almost all of them are against records the platform owns rather than records Open Impact
 * owns: `DuplicateRule` says which rules an administrator has switched on, and
 * `DuplicateRecordSet` with `DuplicateRecordItem` holds what those rules found. Canonical
 * model R-DP1 is the reason there is nothing else to read: no packaged object holds a
 * suggestion, so a suggestion is only ever the platform's own record of one.
 *
 * Everything is queried in user mode. A duplicate suggestion names two records, and a person
 * who cannot see one of them has no business being shown it, let alone being offered a merge
 * of it.
 */
public with sharing class DuplicateSelector {
    /** The developer names of the two rules Open Impact ships, so the page can name them. */
    public static final String CONTACT_RULE = 'Open_Impact_Contact_Duplicates';
    public static final String HOUSEHOLD_RULE = 'Open_Impact_Household_Duplicates';

    /** Every duplicate rule defined for these objects, whether or not it is active. */
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

    /** The active rules for these objects, by developer name. */
    public static Map<String, DuplicateRule> activeRulesByName(Set<String> objectNames) {
        Map<String, DuplicateRule> result = new Map<String, DuplicateRule>();
        for (DuplicateRule rule : rulesFor(objectNames)) {
            if (rule.IsActive == true) {
                result.put(rule.DeveloperName, rule);
            }
        }
        return result;
    }

    /**
     * The suggestions waiting to be looked at, newest first, with the records in each one.
     *
     * Both sources arrive here together and neither is marked: a set written when somebody
     * saved a record over an alert, and a set written by the scan for two records that were
     * already in the org. They are the same thing to the person reviewing them.
     */
    public static List<DuplicateRecordSet> openSets(Integer max) {
        Integer limitRows = max == null || max <= 0 ? 50 : max;
        return [
            SELECT
                Id,
                Name,
                CreatedDate,
                RecordCount,
                DuplicateRuleId,
                DuplicateRule.MasterLabel,
                (SELECT Id, RecordId FROM DuplicateRecordItems ORDER BY CreatedDate)
            FROM DuplicateRecordSet
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :limitRows
        ];
    }

    /** One suggestion, with the records in it. */
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

    /** The suggestions any of these records is already in, so the scan does not repeat one. */
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

    /** Every record in these suggestions. */
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

    /** The pairs among these that somebody has already said are not duplicates. */
    public static Set<String> dismissedKeys(Set<String> pairKeys) {
        Set<String> result = new Set<String>();
        if (pairKeys == null || pairKeys.isEmpty()) {
            return result;
        }
        for (Duplicate_Dismissal__c dismissal : [
            SELECT Id, Pair_Key__c
            FROM Duplicate_Dismissal__c
            WHERE Pair_Key__c IN :pairKeys
            WITH USER_MODE
        ]) {
            result.add(dismissal.Pair_Key__c);
        }
        return result;
    }

    /** How many pairs have been dismissed altogether, for the count on the page. */
    public static Integer dismissalCount() {
        return [SELECT COUNT() FROM Duplicate_Dismissal__c WITH USER_MODE];
    }

    /** The most recent runs of the scan, so the page can say whether one is going on. */
    public static List<AsyncApexJob> recentScanJobs(String className, Integer max) {
        Integer limitRows = max == null || max <= 0 ? 5 : max;
        return [
            SELECT Id, Status, CreatedDate, CompletedDate, JobItemsProcessed, TotalJobItems
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex' AND ApexClass.Name = :className
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :limitRows
        ];
    }

    /** The households and organizations among these identifiers. */
    public static List<Account> accountsByIds(Set<Id> recordIds) {
        if (recordIds == null || recordIds.isEmpty()) {
            return new List<Account>();
        }
        return [
            SELECT
                Id,
                Name,
                RecordTypeId,
                RecordType.DeveloperName,
                BillingCity,
                BillingPostalCode,
                Member_Count__c
            FROM Account
            WHERE Id IN :recordIds
            WITH USER_MODE
        ];
    }

    /** The people among these identifiers. */
    public static List<Contact> contactsByIds(Set<Id> recordIds) {
        if (recordIds == null || recordIds.isEmpty()) {
            return new List<Contact>();
        }
        return [
            SELECT Id, Name, Email, MailingPostalCode, AccountId, Account.Name
            FROM Contact
            WHERE Id IN :recordIds
            WITH USER_MODE
        ];
    }
}

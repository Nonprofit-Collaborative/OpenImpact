/**
 * Every query the household feature makes. No other household class contains SOQL.
 *
 * There are two kinds of read here, and they are not interchangeable.
 *
 * The upkeep reads (everything not named ForDisplay) feed the member count, the household
 * name and the two greetings, which HouseholdWriter then saves, and the guard that decides
 * whether an emptied household may be deleted at all. They run
 * `WITH SYSTEM_MODE` under ADR-0021: a count computed from only the contacts the saving
 * user happens to see would be wrong, and a household must be named correctly for a user
 * who holds no packaged permission set at all. Nothing read on this path reaches a screen.
 * The class is `with sharing`, so which records are visible is not changed by any of this;
 * only field level access on the fields the package itself owns is bypassed.
 *
 * The display reads (the ForDisplay methods) are what a screen shows. ADR-0021 keeps those
 * in user mode: object access is checked, and every field the running user cannot read is
 * stripped from the records before anything is built from them, so a member's deceased
 * flag or preferred name never reaches a user who could not read it on the record itself.
 */
@NamespaceAccessible
public with sharing class HouseholdSelector {
    // The two Nonprofit Cloud objects an Open Impact household Account can have hanging off
    // it, and the whole text of the query asked of each. Held as text and never compiled
    // against, so that Core still deploys on a Platform-only org where neither object exists
    // (ADR-0009, ADR-0013), and each query is a complete literal so that nothing is ever
    // concatenated into it, the same shape OrgShapeSelector uses.
    private static final String NATIVE_HOUSEHOLD_GROUP = 'PartyRelationshipGroup'; // detection-only: describe key, so the delete guard can tell whether this org has native household groups at all before it asks about one
    private static final String NATIVE_HOUSEHOLD_GROUP_QUERY = 'SELECT AccountId FROM PartyRelationshipGroup WHERE AccountId IN :accountIds LIMIT 10000'; // detection-only: the delete guard has to notice a native household group whose master-detail parent is the Account it is about to delete, because deleting the Account cascade-deletes the group
    private static final String NATIVE_MEMBERSHIP = 'AccountContactRelation'; // detection-only: describe key, so the delete guard can tell whether this org has native membership rows at all before it asks about one
    private static final String NATIVE_MEMBERSHIP_QUERY = 'SELECT AccountId FROM AccountContactRelation WHERE AccountId IN :accountIds LIMIT 10000'; // detection-only: the delete guard has to notice native household membership rows on the Account it is about to delete, because they make a household that reads as empty to Open Impact
    private static final String ACCOUNT_FIELD = 'AccountId';

    /**
     * Set only by tests, so that both outcomes of the delete guard are exercised on an org
     * where neither Nonprofit Cloud object exists. Production code always runs the probe.
     */
    @TestVisible
    private static Set<Id> accountsWithNativeDependentsOverride;

    @NamespaceAccessible
    public static List<Contact> getContactsByHouseholdIds(Set<Id> householdIds) {
        if (householdIds == null || householdIds.isEmpty()) {
            return new List<Contact>();
        }
        return [
            SELECT
                Id,
                FirstName,
                LastName,
                Salutation,
                AccountId,
                CreatedDate,
                Preferred_Name__c,
                Deceased__c,
                Household_Role__c,
                Exclude_From_Household_Name__c,
                Exclude_From_Greetings__c
            FROM Contact
            WHERE AccountId IN :householdIds
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
            LIMIT 10000
        ];
    }

    @NamespaceAccessible
    public static List<Contact> getContactsByIds(Set<Id> contactIds) {
        if (contactIds == null || contactIds.isEmpty()) {
            return new List<Contact>();
        }
        return [
            SELECT
                Id,
                FirstName,
                LastName,
                Salutation,
                AccountId,
                CreatedDate,
                Preferred_Name__c,
                Deceased__c,
                Household_Role__c,
                Exclude_From_Household_Name__c,
                Exclude_From_Greetings__c
            FROM Contact
            WHERE Id IN :contactIds
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
            LIMIT 10000
        ];
    }

    /**
     * People with the record type of the account they belong to, so that a caller can tell
     * a household from an organization without a second query.
     */
    /**
     * The household's contacts as a screen may see them: object access checked, and every
     * field the running user cannot read stripped out (ADR-0021).
     */
    @NamespaceAccessible
    public static List<Contact> getContactsByHouseholdIdsForDisplay(Set<Id> householdIds) {
        return readable(getContactsByHouseholdIds(householdIds), Schema.SObjectType.Contact);
    }

    /**
     * These contacts as a screen may see them, on the same terms.
     */
    @NamespaceAccessible
    public static List<Contact> getContactsByIdsForDisplay(Set<Id> contactIds) {
        return readable(getContactsByIds(contactIds), Schema.SObjectType.Contact);
    }

    /**
     * The membership rows of these households as a screen may see them, on the same terms.
     */
    @NamespaceAccessible
    public static List<Household_Member__c> getMembershipsForDisplay(Set<Id> householdIds) {
        return readable(getMemberships(householdIds), Schema.SObjectType.Household_Member__c);
    }

    /**
     * Nothing at all where the user cannot read the object, and otherwise the records with
     * every field they cannot read removed. A field that has been removed is simply absent
     * afterwards, which is why everything built from these records reads its values from
     * the record's own populated values rather than naming the field.
     */
    private static List<SObject> readableRecords(
        List<SObject> records,
        Schema.DescribeSObjectResult describe
    ) {
        if (records == null || records.isEmpty() || !describe.isAccessible()) {
            return new List<SObject>();
        }
        return Security.stripInaccessible(AccessType.READABLE, records).getRecords();
    }

    private static List<Contact> readable(
        List<Contact> records,
        Schema.DescribeSObjectResult describe
    ) {
        return (List<Contact>) readableRecords(records, describe);
    }

    private static List<Household_Member__c> readable(
        List<Household_Member__c> records,
        Schema.DescribeSObjectResult describe
    ) {
        return (List<Household_Member__c>) readableRecords(records, describe);
    }

    @NamespaceAccessible
    public static List<Contact> getContactsWithHouseholds(Set<Id> contactIds) {
        if (contactIds == null || contactIds.isEmpty()) {
            return new List<Contact>();
        }
        return [
            SELECT Id, AccountId, Account.RecordTypeId
            FROM Contact
            WHERE Id IN :contactIds
            WITH SYSTEM_MODE
            LIMIT 10000
        ];
    }

    @NamespaceAccessible
    public static List<Account> getHouseholdsByIds(Set<Id> householdIds) {
        if (householdIds == null || householdIds.isEmpty()) {
            return new List<Account>();
        }
        return [
            SELECT
                Id,
                Name,
                RecordTypeId,
                Custom_Name__c,
                Member_Count__c,
                Primary_Contact__c,
                Household_Formal_Greeting__c,
                Household_Informal_Greeting__c
            FROM Account
            WHERE Id IN :householdIds
            WITH SYSTEM_MODE
            LIMIT 10000
        ];
    }

    /**
     * The record type of each of these accounts, and nothing else.
     *
     * An upkeep read (ADR-0021): the answer never reaches a screen. It decides which
     * standard fields address propagation may write on an account, and a household member
     * the saving user cannot see would otherwise read as an organization and be written
     * through the wrong fields.
     */
    @NamespaceAccessible
    public static List<Account> getAccountRecordTypes(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new List<Account>();
        }
        return [
            SELECT Id, RecordTypeId
            FROM Account
            WHERE Id IN :accountIds
            WITH SYSTEM_MODE
            LIMIT 10000
        ];
    }

    /**
     * Accounts that something outside Open Impact still depends on, of the ones given.
     *
     * A household built by Salesforce Nonprofit Cloud is an Account plus a second record, the
     * native household group, and its membership is carried on native relationship rows
     * rather than on our own Household Member object. The two object names are the constants
     * at the top of this class. The group's account field is a master-detail to Account with
     * no Update property, so deleting the Account does not orphan the group, it destroys it,
     * and every membership row goes with it. Such a household reads as empty to Open Impact,
     * because Open Impact owns none of those rows. The verification is in
     * docs/architecture/reference/nonprofit-cloud-data-model.md section 8 item 7.
     * ADR-NEXT is the decision this method exists to enforce: an empty household is deleted
     * only when nothing outside Open Impact depends on the Account.
     *
     * Neither object exists on a Platform-only org, so both names and both query texts are
     * held as String constants and each query is run through Database.query (ADR-0009,
     * ADR-0013), the same way OrgShapeSelector holds its query. An object that is not in the
     * org is not a dependency, so it contributes nothing rather than throwing.
     *
     * An upkeep read (ADR-0021): the answer never reaches a screen, so it runs in system
     * mode, and the four conditions hold. Only package upkeep reaches it, from
     * HouseholdService.deleteEmptyHouseholds and nowhere else. Its only input is the set of
     * account identifiers that upkeep computed for itself, never anything a person typed. It
     * reads one identifier field on each object and nothing else. Nothing else in the
     * transaction is elevated by it. Reading these rows with the saving user's own access
     * would be worse than useless here: a row that user cannot see would come back missing,
     * the household would read as safe to delete, and the cascade this guard exists to
     * prevent would happen anyway.
     */
    @NamespaceAccessible
    public static Set<Id> getAccountsWithNativeDependents(Set<Id> accountIds) {
        if (accountsWithNativeDependentsOverride != null) {
            return accountsWithNativeDependentsOverride;
        }
        Set<Id> dependent = new Set<Id>();
        if (accountIds == null || accountIds.isEmpty()) {
            return dependent;
        }
        addNativeDependents(
            dependent,
            NATIVE_HOUSEHOLD_GROUP,
            NATIVE_HOUSEHOLD_GROUP_QUERY,
            accountIds
        );
        addNativeDependents(dependent, NATIVE_MEMBERSHIP, NATIVE_MEMBERSHIP_QUERY, accountIds);
        return dependent;
    }

    /**
     * Adds the accounts that have at least one row of this object hanging off them. An object
     * the org does not have, or one this user cannot read at all, adds nothing.
     *
     * A probe that fails for any other reason is treated as though every account given were
     * dependent. Not being able to answer is not the same as answering no, and the cost of
     * the two mistakes is not the same: refusing to delete leaves a tidy-up undone and says
     * so in the log, while deleting on a probe that never ran destroys the native household
     * this guard was added to protect.
     */
    private static void addNativeDependents(
        Set<Id> dependent,
        String objectName,
        String query,
        Set<Id> accountIds
    ) {
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
        if (objectType == null || !objectType.getDescribe().isAccessible()) {
            return;
        }
        try {
            for (SObject row : Database.query(query, AccessLevel.SYSTEM_MODE)) {
                dependent.add((Id) row.get(ACCOUNT_FIELD));
            }
        } catch (Exception probeFailed) {
            // No logging from a selector: the caller reports every household it declined to
            // delete, and this account is now one of them.
            dependent.addAll(accountIds);
        }
    }

    /**
     * The households a merge compares, with every field the comparison offers a choice
     * about: the wording, the primary contact, the anniversary, and the address a letter
     * is sent to.
     */
    @NamespaceAccessible
    public static List<Account> getHouseholdsForMerge(Set<Id> householdIds) {
        if (householdIds == null || householdIds.isEmpty()) {
            return new List<Account>();
        }
        return [
            SELECT
                Id,
                Name,
                RecordTypeId,
                Custom_Name__c,
                Member_Count__c,
                Primary_Contact__c,
                Primary_Contact__r.Name,
                Anniversary__c,
                Household_Formal_Greeting__c,
                Household_Informal_Greeting__c,
                BillingStreet,
                BillingCity,
                BillingState,
                BillingPostalCode,
                BillingCountry
            FROM Account
            WHERE Id IN :householdIds
            WITH USER_MODE
            LIMIT 100
        ];
    }

    /**
     * Households whose name contains what the person typed, for the picker that chooses
     * the other household in a merge or the destination of a split. Only households are
     * offered, never organizations, and the household the person started from is left out.
     */
    @NamespaceAccessible
    public static List<Account> searchHouseholds(String term, Id excludeId, Integer maxRows) {
        Id recordTypeId = HouseholdService.householdRecordTypeId();
        if (recordTypeId == null || String.isBlank(term)) {
            return new List<Account>();
        }
        // The term is a bind variable, not string concatenation, so it needs no escaping.
        // Escaping it would put a backslash into the pattern and lose every O'Brien.
        String pattern = '%' + term.trim() + '%';
        Integer rows = maxRows == null || maxRows <= 0 ? 20 : maxRows;
        Id skip = excludeId;
        return [
            SELECT Id, Name, Member_Count__c, BillingCity, BillingState
            FROM Account
            WHERE RecordTypeId = :recordTypeId AND Name LIKE :pattern AND Id != :skip
            WITH USER_MODE
            ORDER BY Name
            LIMIT :rows
        ];
    }

    /**
     * Of the records given, the ones this user may actually edit. Object level access is
     * not the whole answer on a record that sharing may withhold, so the platform's own
     * record access view is asked rather than inferred.
     */
    @NamespaceAccessible
    public static Set<Id> getEditableIds(Set<Id> recordIds) {
        Set<Id> result = new Set<Id>();
        if (recordIds == null || recordIds.isEmpty()) {
            return result;
        }
        Id userId = UserInfo.getUserId();
        for (UserRecordAccess access : [
            SELECT RecordId
            FROM UserRecordAccess
            WHERE UserId = :userId AND RecordId IN :recordIds AND HasEditAccess = TRUE
            WITH USER_MODE
            LIMIT 200
        ]) {
            result.add(access.RecordId);
        }
        return result;
    }

    @NamespaceAccessible
    public static List<Household_Member__c> getMemberships(Set<Id> householdIds) {
        if (householdIds == null || householdIds.isEmpty()) {
            return new List<Household_Member__c>();
        }
        Date today = Date.today();
        return [
            SELECT
                Id,
                Household__c,
                Contact__c,
                Account__c,
                Role__c,
                Is_Primary__c,
                Start_Date__c,
                End_Date__c
            FROM Household_Member__c
            WHERE Household__c IN :householdIds AND (End_Date__c = NULL OR End_Date__c > :today)
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
            LIMIT 10000
        ];
    }

    @NamespaceAccessible
    public static List<Household_Member__c> getMembershipsForPeople(Set<Id> personIds) {
        if (personIds == null || personIds.isEmpty()) {
            return new List<Household_Member__c>();
        }
        Date today = Date.today();
        return [
            SELECT
                Id,
                Household__c,
                Contact__c,
                Account__c,
                Role__c,
                Is_Primary__c,
                Start_Date__c,
                End_Date__c
            FROM Household_Member__c
            WHERE
                (Contact__c IN :personIds
                OR Account__c IN :personIds)
                AND (End_Date__c = NULL
                OR End_Date__c > :today)
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
            LIMIT 10000
        ];
    }

    /**
     * Every household the naming batch may rewrite. Households whose wording a person has
     * taken over are left out of the query rather than filtered later. R-H8.
     */
    @NamespaceAccessible
    public static Database.QueryLocator getHouseholdsForRecomputeLocator() {
        Id recordTypeId = HouseholdService.householdRecordTypeId();
        return Database.getQueryLocator(
            [
                SELECT Id
                FROM Account
                WHERE RecordTypeId = :recordTypeId AND Custom_Name__c = FALSE
                WITH SYSTEM_MODE
            ]
        );
    }
}

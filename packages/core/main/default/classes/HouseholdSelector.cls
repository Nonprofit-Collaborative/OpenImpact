/**
 * Every query the household feature makes. No other household class contains SOQL.
 */
@NamespaceAccessible
public with sharing class HouseholdSelector {
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
            WITH USER_MODE
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
            WITH USER_MODE
            ORDER BY CreatedDate
            LIMIT 10000
        ];
    }

    /**
     * People with the record type of the account they belong to, so that a caller can tell
     * a household from an organization without a second query.
     */
    @NamespaceAccessible
    public static List<Contact> getContactsWithHouseholds(Set<Id> contactIds) {
        if (contactIds == null || contactIds.isEmpty()) {
            return new List<Contact>();
        }
        return [
            SELECT Id, AccountId, Account.RecordTypeId
            FROM Contact
            WHERE Id IN :contactIds
            WITH USER_MODE
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
            WITH USER_MODE
            LIMIT 10000
        ];
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
        String pattern = '%' + String.escapeSingleQuotes(term.trim()) + '%';
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
            WHERE Household__c IN :householdIds AND (End_Date__c = NULL OR End_Date__c >= :today)
            WITH USER_MODE
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
                OR End_Date__c >= :today)
            WITH USER_MODE
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
                WITH USER_MODE
            ]
        );
    }
}

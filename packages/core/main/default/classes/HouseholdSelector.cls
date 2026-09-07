/**
 * Every query the household feature makes. No other household class contains SOQL.
 */
public with sharing class HouseholdSelector {
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

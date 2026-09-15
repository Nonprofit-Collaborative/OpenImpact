/**
 * The server side of two small household screens: the Household panel on a person's record,
 * and the Make primary action on the household's members panel.
 *
 * Everything here is something a person asked for by clicking, so every read and every
 * write runs with that person's own access (ADR-0021). A household this user cannot see is
 * not shown, and a primary contact this user cannot set is refused with a message they can
 * read rather than a raw platform error.
 */
public with sharing class HouseholdOfPersonController {
    /**
     * One household as the panel on a person's record shows it.
     */
    public class HouseholdView {
        @AuraEnabled
        public Id householdId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public Integer memberCount;
        @AuraEnabled
        public String formalGreeting;
    }

    /**
     * The households this person currently belongs to, in the order they would be listed.
     * Empty when they are in none, which the panel says in plain words.
     *
     * In the simple way of belonging it is the account the contact points at, when that
     * account is a household. In the flexible way it is every household with a current
     * membership record naming the person, which can be more than one.
     */
    @AuraEnabled(cacheable=true)
    public static List<HouseholdView> getHouseholdsForPerson(Id personId) {
        try {
            if (personId == null) {
                return new List<HouseholdView>();
            }
            Set<Id> householdIds = HouseholdService.isJunctionMode()
                ? HouseholdService.householdIdsForPeople(new Set<Id>{ personId })
                : householdIdFromContact(personId);
            return toViews(householdsAsUser(householdIds));
        } catch (Exception e) {
            throw asUserError(Label.Core_HouseholdPanel_OfPersonLoadFailed);
        }
    }

    /**
     * Makes this person the household's primary contact in the flexible way of belonging:
     * their membership record is marked primary and every other current membership of the
     * household is unmarked. The simple way needs no Apex at all, because the screen writes
     * the household's own primary contact field through the platform.
     */
    @AuraEnabled
    public static void makePrimary(Id householdId, Id personId) {
        try {
            if (householdId == null || personId == null) {
                throw new HouseholdException(Label.Core_HouseholdPanel_NotAMember);
            }
            List<Household_Member__c> changed = new List<Household_Member__c>();
            Boolean found = false;
            for (Household_Member__c membership : currentMembershipsAsUser(householdId)) {
                Boolean isPerson =
                    membership.Contact__c == personId ||
                    membership.Account__c == personId;
                found = found || isPerson;
                if (membership.Is_Primary__c != isPerson) {
                    changed.add(
                        new Household_Member__c(Id = membership.Id, Is_Primary__c = isPerson)
                    );
                }
            }
            if (!found) {
                throw new HouseholdException(Label.Core_HouseholdPanel_NotAMember);
            }
            if (!changed.isEmpty()) {
                Database.update(changed, AccessLevel.USER_MODE);
            }
        } catch (HouseholdException e) {
            throw asUserError(e.getMessage());
        } catch (Exception e) {
            ErrorLogger.log(e, Label.Core_Households_ErrorContextMembership, householdId);
            throw asUserError(Label.Core_HouseholdPanel_MakePrimaryFailed);
        }
    }

    // ------------------------------------------------------------------ helpers

    /**
     * The household a contact points at, when it is one. A person stored as an account has
     * no such pointer in the simple way of belonging, so the answer for them is empty.
     */
    private static Set<Id> householdIdFromContact(Id personId) {
        Set<Id> result = new Set<Id>();
        if (personId.getSObjectType() != Contact.SObjectType) {
            return result;
        }
        Id householdRecordTypeId = HouseholdService.householdRecordTypeId();
        for (Contact record : [
            SELECT AccountId, Account.RecordTypeId
            FROM Contact
            WHERE Id = :personId AND AccountId != NULL
            WITH USER_MODE
            LIMIT 1
        ]) {
            if (record.Account.RecordTypeId == householdRecordTypeId) {
                result.add(record.AccountId);
            }
        }
        return result;
    }

    private static List<Account> householdsAsUser(Set<Id> householdIds) {
        if (householdIds == null || householdIds.isEmpty()) {
            return new List<Account>();
        }
        return [
            SELECT Id, Name, Member_Count__c, Household_Formal_Greeting__c
            FROM Account
            WHERE Id IN :householdIds
            WITH USER_MODE
            ORDER BY Name
            LIMIT 200
        ];
    }

    private static List<Household_Member__c> currentMembershipsAsUser(Id householdId) {
        Date today = Date.today();
        return [
            SELECT Id, Contact__c, Account__c, Is_Primary__c
            FROM Household_Member__c
            WHERE Household__c = :householdId AND (End_Date__c = NULL OR End_Date__c > :today)
            WITH USER_MODE
            LIMIT 10000
        ];
    }

    private static List<HouseholdView> toViews(List<Account> households) {
        List<HouseholdView> result = new List<HouseholdView>();
        for (Account household : households) {
            HouseholdView view = new HouseholdView();
            view.householdId = household.Id;
            view.name = household.Name;
            view.memberCount = household.Member_Count__c == null
                ? 0
                : household.Member_Count__c.intValue();
            view.formalGreeting = household.Household_Formal_Greeting__c;
            result.add(view);
        }
        return result;
    }

    private static AuraHandledException asUserError(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}

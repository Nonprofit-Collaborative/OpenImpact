/**
 * The gift queries that recognition needs: soft credit maintenance and matching gift linkage.
 *
 * The gift feature's own queries live in its own selector. This one exists so that G-08, G-09 and
 * G-10 read gifts without reaching into another feature's class, and so that every query they make
 * is in one file (plan Section 9.3).
 *
 * Two access levels, deliberately. Automation reads in system mode, because the credits Open
 * Impact maintains must be right whatever the saving user can see; anything a person asked for
 * reads in user mode, so the screen shows them only their own access.
 */
public with sharing class GiftLookupSelector {
    /**
     * Gifts as automatic soft credit maintenance needs them.
     */
    public static List<Gift__c> selectForRecognition(Set<Id> giftIds) {
        if (giftIds == null || giftIds.isEmpty()) {
            return new List<Gift__c>();
        }
        return [
            SELECT Id, Amount__c, Status__c, Donor_Contact__c, Donor_Account__c, Household__c
            FROM Gift__c
            WHERE Id IN :giftIds
            WITH SYSTEM_MODE
            LIMIT 10000
        ];
    }

    /**
     * Gifts as the matching gift screen needs them: who gave, how much, what the donor account is,
     * and where the donor works.
     */
    public static List<Gift__c> selectForMatching(Set<Id> giftIds) {
        if (giftIds == null || giftIds.isEmpty()) {
            return new List<Gift__c>();
        }
        return [
            SELECT
                Id,
                Name,
                Amount__c,
                Gift_Date__c,
                Status__c,
                Matched_Gift__c,
                Donor_Contact__c,
                Donor_Contact__r.Name,
                Donor_Contact__r.Employer__c,
                Donor_Account__c,
                Donor_Account__r.Name,
                Donor_Account__r.Employer__c,
                Donor_Account__r.RecordType.DeveloperName
            FROM Gift__c
            WHERE Id IN :giftIds
            WITH USER_MODE
            LIMIT 200
        ];
    }
}

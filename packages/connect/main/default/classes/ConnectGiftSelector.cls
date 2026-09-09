/**
 * All SOQL the inbound gift API runs against Gift__c and Gift_Allocation__c.
 *
 * Every query runs in user mode, because the caller of this API is an ordinary integration user
 * and must not be able to read a gift through the endpoint that they could not read in the app
 * (plan Section 4.13).
 */
public with sharing class ConnectGiftSelector {
    /**
     * The gifts already recorded under these external ids, which is the whole of idempotency
     * (R-G7). External_Id__c is unique, so at most one gift comes back per identifier.
     */
    public static List<Gift__c> selectByExternalIds(Set<String> externalIds) {
        if (externalIds == null || externalIds.isEmpty()) {
            return new List<Gift__c>();
        }
        return [
            SELECT
                Id,
                Name,
                External_Id__c,
                Amount__c,
                Gift_Date__c,
                Type__c,
                Status__c,
                Payment_Reference__c,
                Donor_Contact__c,
                Donor_Account__c,
                Appeal__c,
                (SELECT Id, Fund__c, Amount__c FROM Gift_Allocations__r)
            FROM Gift__c
            WHERE External_Id__c IN :externalIds
            WITH USER_MODE
            LIMIT 500
        ];
    }

    /**
     * The gifts just created, with the gift number the platform assigned and the allocation the
     * Giving package gave them (R-GA2). Both are read back rather than assumed: the number only
     * exists after the insert, and the allocation is what the API points at the fund the caller
     * asked for, so the answer can state the designation the gift really carries.
     */
    public static List<Gift__c> selectWithAllocationsById(Set<Id> giftIds) {
        if (giftIds == null || giftIds.isEmpty()) {
            return new List<Gift__c>();
        }
        return [
            SELECT Id, Name, External_Id__c, (SELECT Id, Gift__c, Fund__c, Amount__c FROM Gift_Allocations__r)
            FROM Gift__c
            WHERE Id IN :giftIds
            WITH USER_MODE
            LIMIT 500
        ];
    }
}

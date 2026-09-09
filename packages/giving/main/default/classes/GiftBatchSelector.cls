/**
 * All SOQL against `Gift_Batch__c` and `Gift_Batch_Row__c`. Every query runs in user mode, so a
 * person only ever reads the batches they are allowed to read (plan Section 4.13).
 *
 * The entered total is a query rather than a field. R-GB2 keeps it out of the database on
 * purpose: it is the one number this feature exists to check, and a stored copy of a sum is a
 * second place for it to be wrong.
 */
public with sharing class GiftBatchSelector {
    private static final String STATUS_OPEN = 'Open';

    /** The batches given, without their rows. */
    public static List<Gift_Batch__c> selectById(Set<Id> batchIds) {
        return [
            SELECT
                Id,
                Name,
                Description__c,
                Status__c,
                Control_Total__c,
                Default_Gift_Date__c,
                Default_Fund__c,
                Default_Appeal__c,
                Default_Payment_Method__c,
                Posted_At__c,
                Posted_By__c,
                Gift_Count__c
            FROM Gift_Batch__c
            WHERE Id IN :batchIds
            WITH USER_MODE
        ];
    }

    /**
     * One batch, read with a row lock, which is half of what makes a second post impossible
     * (R-GB4). A second transaction attempting the same post waits here and then reads the
     * status this one wrote.
     *
     * User mode is deliberate: a person who cannot edit the batch cannot post it either.
     */
    public static Gift_Batch__c selectForPost(Id batchId) {
        List<Gift_Batch__c> batches = [
            SELECT
                Id,
                Name,
                Status__c,
                Control_Total__c,
                Default_Gift_Date__c,
                Default_Fund__c,
                Default_Appeal__c,
                Default_Payment_Method__c
            FROM Gift_Batch__c
            WHERE Id = :batchId
            WITH USER_MODE
            FOR UPDATE
        ];
        return batches.isEmpty() ? null : batches[0];
    }

    /** The batches still being typed, most recently touched first, so a person can resume one. */
    public static List<Gift_Batch__c> selectOpen() {
        return [
            SELECT
                Id,
                Name,
                Description__c,
                Status__c,
                Control_Total__c,
                Default_Gift_Date__c,
                LastModifiedDate
            FROM Gift_Batch__c
            WHERE Status__c = :STATUS_OPEN
            WITH USER_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 50
        ];
    }

    /** The lines of one batch, in the order the paper was in. */
    public static List<Gift_Batch_Row__c> selectRows(Id batchId) {
        return [
            SELECT
                Id,
                Name,
                Gift_Batch__c,
                Row_Number__c,
                Donor_Contact__c,
                Donor_Account__c,
                Amount__c,
                Gift_Date__c,
                Fund__c,
                Appeal__c,
                Payment_Method__c,
                Payment_Reference__c,
                Gift__c
            FROM Gift_Batch_Row__c
            WHERE Gift_Batch__c = :batchId
            WITH USER_MODE
            ORDER BY Row_Number__c ASC NULLS LAST, Name ASC
        ];
    }

    /** The batch each of these rows belongs to, for the post lock. */
    public static Map<Id, Gift_Batch__c> selectBatchesForRows(Set<Id> batchIds) {
        return new Map<Id, Gift_Batch__c>(
            [
                SELECT Id, Name, Status__c
                FROM Gift_Batch__c
                WHERE Id IN :batchIds
                WITH SYSTEM_MODE
            ]
        );
    }

    /**
     * What has been typed so far, summed by the database rather than by the browser (R-GB2).
     * A batch with no rows totals zero rather than nothing, so the caller never has a null to
     * subtract.
     */
    public static Decimal enteredTotal(Id batchId) {
        List<AggregateResult> results = [
            SELECT SUM(Amount__c) total
            FROM Gift_Batch_Row__c
            WHERE Gift_Batch__c = :batchId
            WITH USER_MODE
        ];
        if (results.isEmpty() || results[0].get('total') == null) {
            return 0;
        }
        return (Decimal) results[0].get('total');
    }
}

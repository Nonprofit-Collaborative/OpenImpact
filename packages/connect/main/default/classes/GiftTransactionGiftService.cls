/**
 * The Gift Transaction mirror, Gift Transactions to Gifts (feature X-07, R-GT6): each Gift
 * Transaction of the paid status dated on or after the start date, that no gift names yet,
 * becomes a gift.
 *
 * Called only by `GiftTransactionMirrorBatch`, one chunk at a time, as the person who started or
 * scheduled the run. Connect holds no trigger on a Nonprofit Cloud object (ADR-0013), so a run is
 * how a gift entered in Nonprofit Cloud, or written there by a payment integration, reaches
 * BarnCRM.
 *
 * Gifts are ordinary gifts inserted in user mode with partial success, carrying the Gift
 * Transaction ID in the insert itself, so the unique attribute stops a second gift even when two
 * runs overlap and nothing needs undoing. Giving's own rules derive the household and allocate
 * the default fund. The mirror never edits a gift afterwards (R-G4, R-G14).
 */
public with sharing class GiftTransactionGiftService {
    private static final String TYPE_OTHER = 'Other';
    private static final String STATUS_RECEIVED = 'Received';

    /**
     * Makes a gift from each of these Gift Transactions that no gift names yet. Refusals stay on
     * the result, grouped by message, for the run to write once when it ends (R-GT7).
     */
    public static GiftTransactionMirrorService.Result makeGifts(List<SObject> giftTransactions) {
        GiftTransactionMirrorService.Result result = new GiftTransactionMirrorService.Result();
        if (giftTransactions == null || giftTransactions.isEmpty()) {
            return result;
        }
        Set<String> ids = new Set<String>();
        for (SObject giftTransaction : giftTransactions) {
            ids.add(String.valueOf(giftTransaction.Id));
        }
        Set<String> linked = GiftTransactionMirrorSelector.linkedGiftTransactionIds(ids);

        List<Gift__c> gifts = new List<Gift__c>();
        List<SObject> madeFrom = new List<SObject>();
        for (SObject giftTransaction : giftTransactions) {
            // Already named by a gift, or listed twice here: one gift each.
            if (!linked.add(String.valueOf(giftTransaction.Id))) {
                result.unchanged++;
                continue;
            }
            Gift__c gift = giftFrom(giftTransaction);
            String refusal = refusalFor(gift);
            if (refusal != null) {
                result.failed++;
                result.refusals.add(refusal, nameOf(giftTransaction), giftTransaction.Id);
                continue;
            }
            gifts.add(gift);
            madeFrom.add(giftTransaction);
        }
        if (gifts.isEmpty()) {
            return result;
        }
        List<Database.SaveResult> saved = Database.insert(gifts, false, AccessLevel.USER_MODE);
        for (Integer i = 0; i < saved.size(); i++) {
            if (saved[i].isSuccess()) {
                result.created++;
                continue;
            }
            Boolean duplicate = false;
            for (Database.Error error : saved[i].getErrors()) {
                duplicate |= isLinkDuplicate(error);
            }
            if (duplicate) {
                // Another run made its gift first: the Gift Transaction already has one.
                result.unchanged++;
                continue;
            }
            result.failed++;
            result.refusals.add(
                GiftTransactionMirrorService.messageOf(saved[i].getErrors()),
                nameOf(madeFrom[i]),
                madeFrom[i].Id
            );
        }
        return result;
    }

    /** R-GT6: the gift a Gift Transaction becomes, before it is checked. */
    @TestVisible
    private static Gift__c giftFrom(SObject giftTransaction) {
        Object donor = giftTransaction.get(GiftTransactionMirrorSchema.DONOR_FIELD);
        Id donorId = donor == null ? null : (Id) donor;
        return new Gift__c(
            Amount__c = GiftTransactionMirrorSchema.decimalOf(
                giftTransaction.get(GiftTransactionMirrorSchema.AMOUNT_FIELD)
            ),
            Gift_Date__c = (Date) giftTransaction.get(GiftTransactionMirrorSchema.DATE_FIELD),
            Type__c = TYPE_OTHER,
            Status__c = STATUS_RECEIVED,
            Donor_Account__c = donorId != null &&
                donorId.getSObjectType() == Account.SObjectType
                ? donorId
                : null,
            Gift_Transaction_Id__c = String.valueOf(giftTransaction.Id)
        );
    }

    /** Why this gift cannot be made, in words, or null when it can. */
    @TestVisible
    private static String refusalFor(Gift__c gift) {
        if (gift.Amount__c == null || gift.Amount__c <= 0) {
            return Label.Connect_GiftTransactionMirror_AmountNotAboveZero;
        }
        if (gift.Donor_Account__c == null) {
            return Label.Connect_GiftTransactionMirror_NoDonor;
        }
        return null;
    }

    private static String nameOf(SObject giftTransaction) {
        Object name = giftTransaction.get(GiftTransactionMirrorSchema.NAME_FIELD);
        return name == null ? String.valueOf(giftTransaction.Id) : String.valueOf(name);
    }

    /** Only a duplicate on the gift's link means another run made the gift first. */
    private static Boolean isLinkDuplicate(Database.Error error) {
        if (error.getStatusCode() != StatusCode.DUPLICATE_VALUE) {
            return false;
        }
        String link = Gift__c.Gift_Transaction_Id__c.getDescribe().getName();
        List<String> fields = error.getFields();
        // Some unique index refusals name the field only in the message.
        return fields != null && !fields.isEmpty()
            ? fields.contains(link)
            : error.getMessage().contains(link);
    }
}

/**
 * The Gift Transaction mirror reconciliation (feature X-07, R-GT10): for a date range, the gifts
 * the mirror copies (R-GT3) against the Gift Transactions of the paid status, each side's count
 * and total, and every difference.
 *
 * The shape of the Opportunity mirror's (R-OM11, ADR-0058 decision 9): a page rather than a
 * report, because a packaged report type over a Nonprofit Cloud object would stop Connect
 * installing without it. It reads in user mode and writes nothing, so each person sees the
 * differences among the records they can see. A range too large to compare in one transaction is
 * refused rather than shown in part: each side's read stops one past the most it compares, the
 * four reads' rows at that most must fit what the transaction has left, and the gifts are read 200
 * at a time.
 */
public with sharing class GiftTransactionMirrorReconciliation {
    /** The most gifts, and separately the most Gift Transactions, one comparison reads. */
    @TestVisible
    private static Integer maxRecords = 10000;
    /** The most differences listed; the count still covers them all. */
    @TestVisible
    private static Integer maxRows = 500;

    public class ReconciliationException extends Exception {
    }

    /** One gift, one Gift Transaction, or a linked pair, and why they are listed. */
    public class Difference {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public Id giftId;
        @AuraEnabled
        public String giftName;
        @AuraEnabled
        public Decimal giftAmount;
        @AuraEnabled
        public Date giftDate;
        @AuraEnabled
        public String giftTransactionId;
        @AuraEnabled
        public String giftTransactionName;
        @AuraEnabled
        public Decimal giftTransactionAmount;
        @AuraEnabled
        public Date transactionDate;
        @AuraEnabled
        public String reason;
    }

    /** What the page shows for a range. */
    public class Comparison {
        @AuraEnabled
        public Integer giftCount = 0;
        @AuraEnabled
        public Decimal giftTotal = 0;
        @AuraEnabled
        public Integer giftTransactionCount = 0;
        @AuraEnabled
        public Decimal giftTransactionTotal = 0;
        @AuraEnabled
        public Integer differenceCount = 0;
        @AuraEnabled
        public List<Difference> differences = new List<Difference>();

        private void add(Difference difference) {
            differenceCount++;
            if (differences.size() < maxRows) {
                difference.key = difference.giftId != null
                    ? String.valueOf(difference.giftId)
                    : difference.giftTransactionId;
                differences.add(difference);
            }
        }
    }

    /**
     * Compares the gifts of R-GT3 dated in the range with the Gift Transactions of the paid status
     * dated in it, as the running user can see them.
     *
     * @throws ReconciliationException, in words the page shows as they are
     */
    public static Comparison compare(Date fromDate, Date toDate) {
        if (fromDate == null || toDate == null) {
            throw new ReconciliationException(
                Label.Connect_GiftTransactionMirror_ErrorDatesRequired
            );
        }
        if (fromDate > toDate) {
            throw new ReconciliationException(Label.Connect_GiftTransactionMirror_ErrorDateOrder);
        }
        if (!GiftTransactionMirrorService.isAvailable()) {
            throw new ReconciliationException(Label.Connect_GiftTransactionMirror_Unavailable);
        }
        String status = GiftTransactionMirrorService.paidStatus();
        if (status == null || !GiftTransactionMirrorSchema.isActiveStatus(status)) {
            throw new ReconciliationException(
                status == null
                    ? Label.Connect_GiftTransactionMirror_NoStatus
                    : String.format(
                          Label.Connect_GiftTransactionMirror_UnknownStatus,
                          new List<Object>{ status }
                      )
            );
        }
        // User mode reads of a field the viewer cannot see fail with the platform's own words.
        if (!Gift__c.Gift_Transaction_Id__c.getDescribe().isAccessible()) {
            throw new ReconciliationException(Label.Connect_GiftTransactionMirror_NoLinkAccess);
        }
        if (!GiftTransactionMirrorSchema.canRead(GiftTransactionMirrorSchema.READ)) {
            throw new ReconciliationException(Label.Connect_GiftTransactionMirror_NoRead);
        }
        String objectName = GiftTransactionMirrorSchema.objectName();
        // Bound by name in the selector's gift query, as are the dates and statuses.
        Integer cap = maxRecords + 1;
        Set<String> statuses = GiftTransactionMirrorService.MIRRORED_STATUSES;
        String inKind = GiftTransactionMirrorService.TYPE_IN_KIND;
        // Each gift can cost a second row for its Gift Transaction, each one a check for a gift.
        if (4 * cap > Limits.getLimitQueryRows() - Limits.getQueryRows()) {
            throw new ReconciliationException(Label.Connect_GiftTransactionMirror_ErrorTooMany);
        }
        List<SObject> paid = GiftTransactionMirrorSelector.giftTransactionsInRange(
            objectName,
            status,
            fromDate,
            toDate,
            cap
        );
        if (paid.size() > maxRecords) {
            throw new ReconciliationException(Label.Connect_GiftTransactionMirror_ErrorTooMany);
        }

        Comparison result = new Comparison();
        Map<String, SObject> paidById = new Map<String, SObject>();
        for (SObject giftTransaction : paid) {
            paidById.put(String.valueOf(giftTransaction.Id), giftTransaction);
            result.giftTransactionCount++;
            result.giftTransactionTotal += amountOf(giftTransaction);
        }

        Set<String> named = new Set<String>();
        // A gift in the range may name a Gift Transaction dated outside it, or of another status.
        List<Gift__c> elsewhere = new List<Gift__c>();
        Set<Id> elsewhereIds = new Set<Id>();
        for (
            List<Gift__c> chunk : Database.query(GiftTransactionMirrorSelector.GIFTS_IN_RANGE_QUERY)
        ) {
            if (result.giftCount + chunk.size() > maxRecords) {
                throw new ReconciliationException(Label.Connect_GiftTransactionMirror_ErrorTooMany);
            }
            for (Gift__c gift : chunk) {
                result.giftCount++;
                result.giftTotal += gift.Amount__c == null ? 0 : gift.Amount__c;
                if (gift.Gift_Transaction_Id__c == null) {
                    result.add(
                        pair(gift, null, Label.Connect_GiftTransactionMirror_DiffNoGiftTransaction)
                    );
                } else if (paidById.containsKey(gift.Gift_Transaction_Id__c)) {
                    named.add(gift.Gift_Transaction_Id__c);
                    compareLinked(result, gift, paidById.get(gift.Gift_Transaction_Id__c), status);
                } else {
                    Id linked = ConnectSync.idOf(
                        gift.Gift_Transaction_Id__c,
                        GiftTransactionMirrorSchema.objectType()
                    );
                    elsewhere.add(gift);
                    if (linked != null) {
                        elsewhereIds.add(linked);
                    }
                }
            }
        }
        Map<Id, SObject> otherById = GiftTransactionMirrorSelector.giftTransactionsById(
            objectName,
            GiftTransactionMirrorSchema.READ,
            elsewhereIds
        );
        for (Gift__c gift : elsewhere) {
            Id linked = ConnectSync.idOf(
                gift.Gift_Transaction_Id__c,
                GiftTransactionMirrorSchema.objectType()
            );
            compareLinked(result, gift, linked == null ? null : otherById.get(linked), status);
        }

        // A paid Gift Transaction is without a gift only when no gift the mirror copies names it.
        Set<String> unnamed = new Set<String>(paidById.keySet());
        unnamed.removeAll(named);
        unnamed.removeAll(
            GiftTransactionMirrorSelector.linkedByMirroredGifts(unnamed, statuses, inKind)
        );
        for (SObject giftTransaction : paid) {
            if (unnamed.contains(String.valueOf(giftTransaction.Id))) {
                result.add(
                    pair(null, giftTransaction, Label.Connect_GiftTransactionMirror_DiffNoGift)
                );
            }
        }
        return result;
    }

    /** Lists a linked gift whose Gift Transaction is gone or differs from it. */
    private static void compareLinked(
        Comparison result,
        Gift__c gift,
        SObject giftTransaction,
        String status
    ) {
        if (giftTransaction == null) {
            Difference missing = pair(gift, null, Label.Connect_GiftTransactionMirror_DiffMissing);
            missing.giftTransactionId = gift.Gift_Transaction_Id__c;
            result.add(missing);
            return;
        }
        List<String> reasons = new List<String>();
        Decimal giftAmount = gift.Amount__c == null ? 0 : gift.Amount__c;
        if (giftAmount != amountOf(giftTransaction)) {
            reasons.add(Label.Connect_GiftTransactionMirror_DiffAmount);
        }
        if (
            gift.Gift_Date__c != (Date) giftTransaction.get(GiftTransactionMirrorSchema.DATE_FIELD)
        ) {
            reasons.add(Label.Connect_GiftTransactionMirror_DiffDate);
        }
        if (
            !ConnectSync.same(status, giftTransaction.get(GiftTransactionMirrorSchema.STATUS_FIELD))
        ) {
            reasons.add(Label.Connect_GiftTransactionMirror_DiffStatus);
        }
        if (!reasons.isEmpty()) {
            result.add(pair(gift, giftTransaction, String.join(reasons, ', ')));
        }
    }

    private static Difference pair(Gift__c gift, SObject giftTransaction, String reason) {
        Difference difference = new Difference();
        difference.reason = reason;
        if (gift != null) {
            difference.giftId = gift.Id;
            difference.giftName = gift.Name;
            difference.giftAmount = gift.Amount__c;
            difference.giftDate = gift.Gift_Date__c;
        }
        if (giftTransaction != null) {
            Object name = giftTransaction.get(GiftTransactionMirrorSchema.NAME_FIELD);
            difference.giftTransactionId = String.valueOf(giftTransaction.Id);
            difference.giftTransactionName = name == null ? null : String.valueOf(name);
            difference.giftTransactionAmount = amountOf(giftTransaction);
            difference.transactionDate = (Date) giftTransaction.get(
                GiftTransactionMirrorSchema.DATE_FIELD
            );
        }
        return difference;
    }

    private static Decimal amountOf(SObject giftTransaction) {
        Decimal amount = GiftTransactionMirrorSchema.decimalOf(
            giftTransaction.get(GiftTransactionMirrorSchema.AMOUNT_FIELD)
        );
        return amount == null ? 0 : amount;
    }
}

/**
 * The Opportunity mirror reconciliation (feature X-01, R-OM11): for a date range, the gifts in the
 * totals against the won Opportunities, each side's count and total, and every difference.
 *
 * A page rather than a report, because a packaged report type over Opportunity would stop Connect
 * installing where Opportunity does not exist (ADR-0013). It reads in user mode and writes
 * nothing, so each person sees the differences among the records they can see. A range too large
 * to compare in one transaction is refused rather than shown in part (ADR-0051).
 */
public with sharing class OpportunityMirrorReconciliation {
    /** The most gifts, and separately the most won Opportunities, one comparison reads. */
    @TestVisible
    private static Integer maxRecords = 10000;
    /** The most differences listed; the count still covers them all. */
    @TestVisible
    private static Integer maxRows = 500;

    public class ReconciliationException extends Exception {
    }

    /** One gift, one Opportunity, or a linked pair, and why they are listed. */
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
        public String opportunityId;
        @AuraEnabled
        public String opportunityName;
        @AuraEnabled
        public Decimal opportunityAmount;
        @AuraEnabled
        public Date closeDate;
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
        public Integer opportunityCount = 0;
        @AuraEnabled
        public Decimal opportunityTotal = 0;
        @AuraEnabled
        public Integer differenceCount = 0;
        @AuraEnabled
        public List<Difference> differences = new List<Difference>();

        private void add(Difference difference) {
            differenceCount++;
            if (differences.size() < maxRows) {
                difference.key = difference.giftId != null
                    ? String.valueOf(difference.giftId)
                    : difference.opportunityId;
                differences.add(difference);
            }
        }
    }

    /**
     * Compares the gifts in the totals dated in the range with the won Opportunities closed in
     * it, as the running user can see them.
     *
     * @throws ReconciliationException, in words the page shows as they are
     */
    public static Comparison compare(Date fromDate, Date toDate) {
        if (fromDate == null || toDate == null) {
            throw new ReconciliationException(Label.Connect_OpportunityMirror_ErrorDatesRequired);
        }
        if (fromDate > toDate) {
            throw new ReconciliationException(Label.Connect_OpportunityMirror_ErrorDateOrder);
        }
        if (!OpportunityMirrorService.isAvailable()) {
            throw new ReconciliationException(Label.Connect_OpportunityMirror_Unavailable);
        }
        // User mode reads of a field the viewer cannot see fail with the platform's own words.
        if (!Gift__c.Opportunity_Id__c.getDescribe().isAccessible()) {
            throw new ReconciliationException(Label.Connect_OpportunityMirror_NoLinkAccess);
        }
        String opportunityObject = OpportunityMirrorService.opportunityType()
            .getDescribe()
            .getName();
        if (
            OpportunityMirrorSelector.countGiftsInRange(fromDate, toDate) > maxRecords ||
            OpportunityMirrorSelector.countWonInRange(opportunityObject, fromDate, toDate) >
            maxRecords
        ) {
            throw new ReconciliationException(Label.Connect_OpportunityMirror_ErrorTooMany);
        }

        Comparison result = new Comparison();
        Map<String, SObject> wonById = new Map<String, SObject>();
        for (
            SObject opportunity : OpportunityMirrorSelector.wonInRange(
                opportunityObject,
                fromDate,
                toDate
            )
        ) {
            wonById.put(String.valueOf(opportunity.Id), opportunity);
            result.opportunityCount++;
            result.opportunityTotal += amountOf(opportunity.get('Amount'));
        }

        List<Gift__c> gifts = OpportunityMirrorSelector.giftsInRange(fromDate, toDate);
        // A gift in the range may name an Opportunity closed outside it, or one not won.
        Set<Id> elsewhere = new Set<Id>();
        for (Gift__c gift : gifts) {
            if (gift.Opportunity_Id__c != null && !wonById.containsKey(gift.Opportunity_Id__c)) {
                elsewhere.add(Id.valueOf(gift.Opportunity_Id__c));
            }
        }
        Map<Id, SObject> otherById = OpportunityMirrorSelector.opportunitiesById(
            opportunityObject,
            new List<String>{ 'Id', 'Name', 'Amount', 'CloseDate', 'IsWon' },
            elsewhere
        );

        Set<String> named = new Set<String>();
        for (Gift__c gift : gifts) {
            result.giftCount++;
            result.giftTotal += amountOf(gift.Amount__c);
            if (gift.Opportunity_Id__c == null) {
                result.add(pair(gift, null, Label.Connect_OpportunityMirror_DiffNoOpportunity));
                continue;
            }
            named.add(gift.Opportunity_Id__c);
            SObject opportunity = wonById.containsKey(gift.Opportunity_Id__c)
                ? wonById.get(gift.Opportunity_Id__c)
                : otherById.get(Id.valueOf(gift.Opportunity_Id__c));
            if (opportunity == null) {
                Difference missing = pair(gift, null, Label.Connect_OpportunityMirror_DiffMissing);
                missing.opportunityId = gift.Opportunity_Id__c;
                result.add(missing);
                continue;
            }
            List<String> reasons = new List<String>();
            if (amountOf(gift.Amount__c) != amountOf(opportunity.get('Amount'))) {
                reasons.add(Label.Connect_OpportunityMirror_DiffAmount);
            }
            if (gift.Gift_Date__c != (Date) opportunity.get('CloseDate')) {
                reasons.add(Label.Connect_OpportunityMirror_DiffDate);
            }
            if (opportunity.get('IsWon') != true) {
                reasons.add(Label.Connect_OpportunityMirror_DiffNotWon);
            }
            if (!reasons.isEmpty()) {
                result.add(pair(gift, opportunity, String.join(reasons, ', ')));
            }
        }

        // A won Opportunity is without a gift only when no gift anywhere names it.
        Set<String> unnamed = new Set<String>(wonById.keySet());
        unnamed.removeAll(named);
        unnamed.removeAll(OpportunityMirrorSelector.linkedOpportunityIds(unnamed));
        for (SObject opportunity : wonById.values()) {
            if (unnamed.contains(String.valueOf(opportunity.Id))) {
                result.add(pair(null, opportunity, Label.Connect_OpportunityMirror_DiffNoGift));
            }
        }
        return result;
    }

    private static Difference pair(Gift__c gift, SObject opportunity, String reason) {
        Difference difference = new Difference();
        difference.reason = reason;
        if (gift != null) {
            difference.giftId = gift.Id;
            difference.giftName = gift.Name;
            difference.giftAmount = gift.Amount__c;
            difference.giftDate = gift.Gift_Date__c;
        }
        if (opportunity != null) {
            difference.opportunityId = String.valueOf(opportunity.Id);
            difference.opportunityName = (String) opportunity.get('Name');
            difference.opportunityAmount = (Decimal) opportunity.get('Amount');
            difference.closeDate = (Date) opportunity.get('CloseDate');
        }
        return difference;
    }

    private static Decimal amountOf(Object amount) {
        return amount == null ? 0 : (Decimal) amount;
    }
}

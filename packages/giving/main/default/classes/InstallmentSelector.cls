/**
 * Queries for Installment__c and for the gifts paid against an installment.
 */
public with sharing class InstallmentSelector {
    private static final String STATUS_RECEIVED = 'Received';
    private static final String STATUS_SCHEDULED = 'Scheduled';
    private static final String STATUS_OVERDUE = 'Overdue';

    /**
     * Every installment of the commitments named, in schedule order.
     */
    public List<Installment__c> selectByCommitmentIds(Set<Id> commitmentIds) {
        return [
            SELECT
                Id,
                Name,
                Commitment__c,
                Sequence__c,
                Due_Date__c,
                Expected_Amount__c,
                Status__c,
                Paid_Amount__c
            FROM Installment__c
            WHERE Commitment__c IN :commitmentIds
            WITH USER_MODE
            ORDER BY Commitment__c, Sequence__c
        ];
    }

    /**
     * The installments named.
     */
    public List<Installment__c> selectByIds(Set<Id> installmentIds) {
        return [
            SELECT
                Id,
                Name,
                Commitment__c,
                Sequence__c,
                Due_Date__c,
                Expected_Amount__c,
                Status__c,
                Paid_Amount__c
            FROM Installment__c
            WHERE Id IN :installmentIds
            WITH USER_MODE
        ];
    }

    /**
     * Unpaid installments whose due date is on or before the cutoff, for the daily job.
     */
    public List<Installment__c> selectUnpaidDueBefore(Date cutoff, Integer maximum) {
        return [
            SELECT Id, Commitment__c, Sequence__c, Due_Date__c, Expected_Amount__c, Status__c
            FROM Installment__c
            WHERE Status__c IN (:STATUS_SCHEDULED, :STATUS_OVERDUE) AND Due_Date__c <= :cutoff
            WITH USER_MODE
            ORDER BY Due_Date__c
            LIMIT :maximum
        ];
    }

    /**
     * What has been received against each installment named, by installment.
     */
    public Map<Id, Decimal> sumReceivedGifts(Set<Id> installmentIds) {
        Map<Id, Decimal> totals = new Map<Id, Decimal>();
        if (installmentIds == null || installmentIds.isEmpty()) {
            return totals;
        }
        for (AggregateResult row : [
            SELECT Installment__c installmentId, SUM(Amount__c) total
            FROM Gift__c
            WHERE Installment__c IN :installmentIds AND Status__c = :STATUS_RECEIVED
            WITH USER_MODE
            GROUP BY Installment__c
        ]) {
            Decimal total = (Decimal) row.get('total');
            totals.put((Id) row.get('installmentId'), total == null ? 0 : total);
        }
        return totals;
    }

    /**
     * How many gifts of any status are linked to each installment named.
     */
    public Map<Id, Integer> countGifts(Set<Id> installmentIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (installmentIds == null || installmentIds.isEmpty()) {
            return counts;
        }
        for (AggregateResult row : [
            SELECT Installment__c installmentId, COUNT(Id) total
            FROM Gift__c
            WHERE Installment__c IN :installmentIds
            WITH USER_MODE
            GROUP BY Installment__c
        ]) {
            counts.put((Id) row.get('installmentId'), (Integer) row.get('total'));
        }
        return counts;
    }
}

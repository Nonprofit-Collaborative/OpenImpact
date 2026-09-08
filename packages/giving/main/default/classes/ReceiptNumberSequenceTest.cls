/**
 * The first of the three tests ADR-0016 names: **a number is allocated once and never reused.**
 *
 * Everything about receipt numbering exists to make one question answerable: what happened to
 * number N. These tests are that question asked three ways.
 */
@IsTest
private class ReceiptNumberSequenceTest {
    private static final Integer YEAR = 2026;

    @TestSetup
    static void setUp() {
        ReceiptTestDataFactory.setUpReceipting();
    }

    /**
     * Consecutive allocations strictly increase. Not "are different": increase, in order, with no
     * value repeated and none going backwards.
     */
    @IsTest
    static void consecutiveAllocationsStrictlyIncrease() {
        Test.startTest();
        List<String> allocated = new List<String>();
        for (Integer index = 0; index < 5; index++) {
            allocated.add(
                ReceiptNumberSequence.allocateOne(ReceiptNumberSequence.TYPE_PER_GIFT, YEAR)
            );
        }
        Test.stopTest();

        Assert.areEqual(
            'HFH-2026-000001',
            allocated[0],
            'The series starts at the counter in settings.'
        );
        Set<String> unique = new Set<String>(allocated);
        Assert.areEqual(5, unique.size(), 'No number is ever handed out twice.');
        for (Integer index = 1; index < allocated.size(); index++) {
            Assert.isTrue(
                counterOf(allocated[index]) > counterOf(allocated[index - 1]),
                'Each number is larger than the one before it: ' +
                    allocated[index - 1] +
                    ' then ' +
                    allocated[index]
            );
        }
    }

    /**
     * A block taken by a batch chunk and a single number taken afterwards do not overlap. This is
     * the case that produces two donors holding the same receipt number if the sequence is wrong,
     * which is the one failure nobody can recover from.
     */
    @IsTest
    static void blockAllocationDoesNotOverlapALaterSingleAllocation() {
        Test.startTest();
        List<String> block = ReceiptNumberSequence.allocate(
            ReceiptNumberSequence.TYPE_STATEMENT,
            YEAR,
            25
        );
        String afterwards = ReceiptNumberSequence.allocateOne(
            ReceiptNumberSequence.TYPE_STATEMENT,
            YEAR
        );
        Test.stopTest();

        Assert.areEqual(25, block.size(), 'A block of twenty five is twenty five numbers.');
        Assert.areEqual(25, new Set<String>(block).size(), 'A block contains no repeats.');
        Assert.isFalse(
            new Set<String>(block).contains(afterwards),
            'The number taken after the block is not one of the block: ' + afterwards
        );
        Assert.areEqual(
            counterOf(block[block.size() - 1]) + 1,
            counterOf(afterwards),
            'The next number continues from the end of the block.'
        );
    }

    /**
     * A number that a failed generation consumed is reconciled into a Void receipt and is **not**
     * handed out again. An auditor asking about it finds a record saying the document was never
     * produced, which is an answer; silence is not.
     */
    @IsTest
    static void aNumberConsumedByAFailedGenerationIsReconciledIntoAVoidReceipt() {
        List<String> consumed = ReceiptNumberSequence.allocate(
            ReceiptNumberSequence.TYPE_STATEMENT,
            YEAR,
            3
        );
        // The middle document is the one that made it to a record. The other two are numbers that
        // were handed out to a chunk that then failed.
        Contact donor = GivingTestDataFactory.insertHouseholdContact(
            'The Reyes Family',
            'Ana',
            'Reyes'
        );
        insert new Receipt__c(
            Receipt_Number__c = consumed[1],
            Type__c = ReceiptNumberSequence.TYPE_STATEMENT,
            Status__c = ReceiptService.STATUS_ISSUED,
            Statement_Year__c = YEAR,
            Donor_Contact__c = donor.Id,
            Total_Amount__c = 250,
            Issue_Date__c = Date.today(),
            Series_Key__c = ReceiptNumberSequence.seriesKeyFor(
                ReceiptNumberSequence.TYPE_STATEMENT,
                YEAR
            )
        );

        Test.startTest();
        Integer accountedFor = ReceiptNumberSequence.reconcile(
            ReceiptNumberSequence.TYPE_STATEMENT,
            YEAR,
            null
        );
        String next = ReceiptNumberSequence.allocateOne(ReceiptNumberSequence.TYPE_STATEMENT, YEAR);
        Test.stopTest();

        Assert.areEqual(2, accountedFor, 'The two numbers with no receipt are accounted for.');

        Map<String, Receipt__c> byNumber = new Map<String, Receipt__c>();
        for (Receipt__c receipt : [
            SELECT Receipt_Number__c, Status__c, Void_Reason__c, Voided_On__c
            FROM Receipt__c
        ]) {
            byNumber.put(receipt.Receipt_Number__c, receipt);
        }

        for (String consumedNumber : new List<String>{ consumed[0], consumed[2] }) {
            Receipt__c reconciled = byNumber.get(consumedNumber);
            Assert.isNotNull(
                reconciled,
                'Number ' + consumedNumber + ' has a record, not silence.'
            );
            Assert.areEqual(ReceiptService.STATUS_VOID, reconciled.Status__c, 'It is void.');
            Assert.areEqual(
                ReceiptNumberSequence.VOID_REASON_GENERATION_FAILED,
                reconciled.Void_Reason__c,
                'It says why: the document was never produced.'
            );
            Assert.isNotNull(reconciled.Voided_On__c, 'It says when it was accounted for.');
        }

        Assert.areEqual(
            ReceiptService.STATUS_ISSUED,
            byNumber.get(consumed[1]).Status__c,
            'Reconciliation leaves a surviving receipt alone.'
        );
        Assert.isFalse(
            new Set<String>(consumed).contains(next),
            'A reconciled number is never handed out again: ' + next
        );
    }

    /** The counter part of a formatted number, so a test can compare two of them. */
    private static Integer counterOf(String receiptNumber) {
        return Integer.valueOf(receiptNumber.substringAfterLast('-'));
    }
}

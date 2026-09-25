/**
 * ReceiptGenerationFailureSelector counts the void receipts a failed run left behind (R-RC3). The findings
 * built from the count are tested in HealthCheckGivingChecksTest.
 */
@IsTest
private class ReceiptGenerationFailureSelectorTest {
    @IsTest
    static void anOrgWithNoFailedRunsCountsZero() {
        Test.startTest();
        ReceiptGenerationFailureSelector.Result result = ReceiptGenerationFailureSelector.generationFailures();
        Test.stopTest();

        System.assertEquals(true, result.available, 'An administrator can read receipts');
        System.assertEquals(0, result.count, 'Nothing has failed in a fresh org');
    }

    @IsTest
    static void aPersonWhoCannotReadReceiptsIsNotToldZero() {
        User nobody = TestDataFactory.createUser('Nobody', new List<String>());

        ReceiptGenerationFailureSelector.Result result;
        Test.startTest();
        System.runAs(nobody) {
            result = ReceiptGenerationFailureSelector.generationFailures();
        }
        Test.stopTest();

        System.assertEquals(
            false,
            result.available,
            'Without read access the question was not answered, which is not the same as zero'
        );
    }
}

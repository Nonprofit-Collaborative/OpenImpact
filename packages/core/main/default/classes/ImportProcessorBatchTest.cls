/**
 * The Batch Apex wrapper: a whole run end to end, and the promise that a chunk which dies
 * does not take the run with it.
 */
@IsTest
private class ImportProcessorBatchTest {
    @TestSetup
    static void setUp() {
        TestDataFactory.defaultSettings();
    }

    private static Import_Batch__c staged(Integer howManyRows) {
        Import_Template__c template = ImportTestDataFactory.template(
            ImportTestDataFactory.donorMapping(),
            ImportTemplateService.RULE_EMAIL
        );
        Import_Batch__c batch = ImportTestDataFactory.batch(template);
        List<Map<String, String>> values = new List<Map<String, String>>();
        for (Integer i = 0; i < howManyRows; i++) {
            values.add(
                ImportTestDataFactory.donorRow(
                    'Person' + i,
                    'Surname' + i,
                    'person' + i + '@example.org',
                    null
                )
            );
        }
        ImportTestDataFactory.rows(batch, values);
        return batch;
    }

    @IsTest
    static void aDryRunFinishesWithCountsAndWritesNothing() {
        Import_Batch__c batch = staged(3);

        Test.startTest();
        Database.executeBatch(new ImportProcessorBatch(batch.Id, true), 200);
        Test.stopTest();

        Import_Batch__c after = ImportBatchSelector.selectById(batch.Id);
        Assert.areEqual(
            ImportBatchService.STATUS_DRY_RUN_COMPLETE,
            after.Status__c,
            'The run ended ready for a commit.'
        );
        Assert.areEqual(3, after.Rows_Created__c, 'Three rows would create somebody.');
        Assert.areEqual(0, [SELECT COUNT() FROM Contact], 'And nobody was actually created.');
        Assert.isTrue(
            after.Run_Log__c.contains(Label.Core_Import_LogDryRunHeader),
            'The run log says plainly that nothing was written.'
        );
    }

    @IsTest
    static void aCommitLoadsTheRowsAndReportsWhatItDid() {
        Import_Batch__c batch = staged(3);
        batch.Status__c = ImportBatchService.STATUS_DRY_RUN_COMPLETE;
        update batch;

        Test.startTest();
        Database.executeBatch(new ImportProcessorBatch(batch.Id, false), 200);
        Test.stopTest();

        Import_Batch__c after = ImportBatchSelector.selectById(batch.Id);
        Assert.areEqual(ImportBatchService.STATUS_COMPLETE, after.Status__c, 'It completed.');
        Assert.areEqual(3, after.Rows_Created__c, 'Three rows created somebody.');
        Assert.areEqual(3, [SELECT COUNT() FROM Contact], 'And three people exist.');
        Assert.isNotNull(after.Completed_At__c, 'With a finish time on the record.');
    }

    @IsTest
    static void honorsTheChunkSizeAsTheBatchScope() {
        Import_Batch__c batch = staged(5);
        batch.Chunk_Size__c = 2;
        batch.Status__c = ImportBatchService.STATUS_DRY_RUN_COMPLETE;
        update batch;

        Test.startTest();
        // Two rows per chunk, which is what the org's setting asks for (R-IB2).
        Database.executeBatch(new ImportProcessorBatch(batch.Id, false), 2);
        Test.stopTest();

        Assert.areEqual(
            5,
            [SELECT COUNT() FROM Contact],
            'Every row was processed even though the chunk was smaller than the file.'
        );
    }

    @IsTest
    static void aChunkThatDiesRejectsItsOwnRowsAndSaysWhy() {
        Import_Batch__c batch = staged(2);
        // Deleting the template is the simplest way to make the chunk fail for a reason the
        // administrator would recognize, and it exercises the same path a limit error takes.
        delete [SELECT Id FROM Import_Template__c LIMIT 1];

        Test.startTest();
        Database.executeBatch(new ImportProcessorBatch(batch.Id, false), 200);
        Test.stopTest();

        Import_Batch__c after = ImportBatchSelector.selectById(batch.Id);
        Assert.areEqual(
            ImportBatchService.STATUS_FAILED,
            after.Status__c,
            'The run says it failed rather than reporting a clean finish.'
        );
        for (Import_Row__c row : ImportTestDataFactory.reload(batch.Id)) {
            Assert.areEqual(
                ImportRowProcessor.STATUS_REJECTED,
                row.Status__c,
                'Every row of the lost chunk is marked, so nothing disappears unexplained.'
            );
            Assert.isNotNull(row.Error_Message__c, 'With a reason on each one.');
        }
    }

    @IsTest
    static void aRunOverNoRowsStillFinishesCleanly() {
        Import_Template__c template = ImportTestDataFactory.template(
            ImportTestDataFactory.donorMapping(),
            ImportTemplateService.RULE_EMAIL
        );
        Import_Batch__c batch = ImportTestDataFactory.batch(template);

        Test.startTest();
        Database.executeBatch(new ImportProcessorBatch(batch.Id, true), 200);
        Test.stopTest();

        Import_Batch__c after = ImportBatchSelector.selectById(batch.Id);
        Assert.areEqual(
            ImportBatchService.STATUS_DRY_RUN_COMPLETE,
            after.Status__c,
            'An empty run is not a failed run.'
        );
        Assert.areEqual(0, after.Rows_Created__c, 'And it created nothing.');
    }
}

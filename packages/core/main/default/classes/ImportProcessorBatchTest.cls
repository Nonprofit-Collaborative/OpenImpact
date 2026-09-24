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

        // Two rows per chunk, which is what the org's setting asks for (R-IB2). A test may run
        // only one chunk of a real batch job, so the job is driven here the way the platform
        // drives it: its own query, then one execute per chunk of that size, then finish.
        ImportProcessorBatch job = new ImportProcessorBatch(batch.Id, false);
        Integer chunkSize = batch.Chunk_Size__c.intValue();
        List<List<Import_Row__c>> chunks = new List<List<Import_Row__c>>();
        Database.QueryLocatorIterator rows = job.start(null).iterator();
        while (rows.hasNext()) {
            if (chunks.isEmpty() || chunks[chunks.size() - 1].size() == chunkSize) {
                chunks.add(new List<Import_Row__c>());
            }
            chunks[chunks.size() - 1].add((Import_Row__c) rows.next());
        }

        Test.startTest();
        for (List<Import_Row__c> chunk : chunks) {
            job.execute(null, chunk);
        }
        job.finish(null);
        Test.stopTest();

        Assert.areEqual(3, chunks.size(), 'Five rows at two a chunk is three chunks.');
        Assert.areEqual(
            5,
            [SELECT COUNT() FROM Contact],
            'Every row was processed even though the chunk was smaller than the file.'
        );
    }

    /** A processor that counts the chunks it has seen in the state it carries. */
    private class CountingProcessor implements ImportEntityProcessor {
        public List<ImportMapping.Target> targets() {
            return new List<ImportMapping.Target>();
        }

        public ImportEntityResult resolve(
            Import_Batch__c batch,
            Import_Template__c template,
            List<Import_Row__c> rows,
            Map<Id, Map<String, Map<String, String>>> entitiesByRowId,
            Boolean dryRun
        ) {
            String seen = ImportEntityProcessors.carriedState;
            ImportEntityProcessors.carriedState = (seen == null ? '' : seen) + 'x';
            return new ImportEntityResult();
        }

        public List<Schema.SObjectType> taggedObjects() {
            return new List<Schema.SObjectType>();
        }

        public Map<Id, String> reasonsToKeep(
            Id batchId,
            Schema.SObjectType type,
            Set<Id> recordIds
        ) {
            return new Map<Id, String>();
        }
    }

    @IsTest
    static void theProcessorStateIsCarriedFromChunkToChunk() {
        ImportMapping mapping = new ImportMapping();
        for (
            String target : new List<String>{
                'Contact1.Email',
                'Contact1.LastName',
                'Gift.Amount__c'
            }
        ) {
            mapping.columns.add(new ImportMapping.Column(target, target));
        }
        Import_Template__c template = ImportTestDataFactory.template(
            mapping.serialize(),
            ImportTemplateService.RULE_EMAIL
        );
        Import_Batch__c batch = ImportTestDataFactory.batch(template);
        List<Map<String, String>> values = new List<Map<String, String>>();
        for (Integer i = 0; i < 2; i++) {
            values.add(
                new Map<String, String>{
                    'Contact1.Email' => 'person' +
                    i +
                    '@example.org',
                    'Contact1.LastName' => 'Surname' + i,
                    'Gift.Amount__c' => '10'
                }
            );
        }
        ImportTestDataFactory.rows(batch, values);
        ImportEntityProcessors.processorOverride = new CountingProcessor();
        ImportProcessorBatch job = new ImportProcessorBatch(batch.Id, true);
        List<Import_Row__c> rows = new List<Import_Row__c>();
        Database.QueryLocatorIterator staged = job.start(null).iterator();
        while (staged.hasNext()) {
            rows.add((Import_Row__c) staged.next());
        }

        Test.startTest();
        job.execute(null, new List<Import_Row__c>{ rows[0] });
        // A new chunk is a new transaction, whose statics start empty.
        ImportEntityProcessors.carriedState = null;
        job.execute(null, new List<Import_Row__c>{ rows[1] });
        Test.stopTest();

        Assert.areEqual(
            'xx',
            ImportEntityProcessors.carriedState,
            'The second chunk started from what the first left.'
        );
    }

    /** A processor that reports the settings it ran under, and what a commit was handed. */
    private class SettingsProcessor implements ImportEntityProcessor {
        public List<ImportMapping.Target> targets() {
            return new List<ImportMapping.Target>();
        }

        public ImportEntityResult resolve(
            Import_Batch__c batch,
            Import_Template__c template,
            List<Import_Row__c> rows,
            Map<Id, Map<String, Map<String, String>>> entitiesByRowId,
            Boolean dryRun
        ) {
            ImportEntityResult result = new ImportEntityResult();
            if (dryRun) {
                result.settings = '{"window":7}';
            } else {
                handedToTheCommit = batch.Processor_Settings_JSON__c;
                result.settings = '{"window":0}';
            }
            return result;
        }

        public List<Schema.SObjectType> taggedObjects() {
            return new List<Schema.SObjectType>();
        }

        public Map<Id, String> reasonsToKeep(
            Id batchId,
            Schema.SObjectType type,
            Set<Id> recordIds
        ) {
            return new Map<Id, String>();
        }
    }

    private static String handedToTheCommit;

    @IsTest
    static void theCommitIsHandedTheSettingsItsDryRunRecorded() {
        ImportMapping mapping = new ImportMapping();
        for (
            String target : new List<String>{
                'Contact1.Email',
                'Contact1.LastName',
                'Gift.Amount__c'
            }
        ) {
            mapping.columns.add(new ImportMapping.Column(target, target));
        }
        Import_Batch__c batch = ImportTestDataFactory.batch(
            ImportTestDataFactory.template(mapping.serialize(), ImportTemplateService.RULE_EMAIL)
        );
        ImportTestDataFactory.rows(
            batch,
            new List<Map<String, String>>{
                new Map<String, String>{
                    'Contact1.Email' => 'ana@example.org',
                    'Contact1.LastName' => 'Ramirez',
                    'Gift.Amount__c' => '10'
                }
            }
        );
        ImportEntityProcessors.processorOverride = new SettingsProcessor();

        Test.startTest();
        ImportProcessorBatch previewing = new ImportProcessorBatch(batch.Id, true);
        previewing.execute(null, ImportTestDataFactory.reload(batch.Id));
        previewing.finish(null);
        Import_Batch__c afterDryRun = ImportBatchSelector.selectById(batch.Id);
        ImportBatchService.resetRows(batch.Id);
        ImportProcessorBatch committing = new ImportProcessorBatch(batch.Id, false);
        committing.execute(null, ImportTestDataFactory.reload(batch.Id));
        committing.finish(null);
        Test.stopTest();

        Assert.areEqual(
            '{"window":7}',
            afterDryRun.Processor_Settings_JSON__c,
            'The dry run recorded what it ran under (R-IB11).'
        );
        Assert.areEqual('{"window":7}', handedToTheCommit, 'And the commit was handed it.');
        Assert.areEqual(
            '{"window":7}',
            ImportBatchSelector.selectById(batch.Id).Processor_Settings_JSON__c,
            'A commit does not replace what its dry run recorded.'
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
    static void aChunkThatDiesAfterWritingLeavesNothingBehind() {
        Import_Batch__c batch = staged(2);
        batch.Status__c = ImportBatchService.STATUS_DRY_RUN_COMPLETE;
        update batch;
        // The chunk creates both people, then dies.
        ImportProcessorBatch.failAfterProcessForTest = true;

        Test.startTest();
        Database.executeBatch(new ImportProcessorBatch(batch.Id, false), 200);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Contact], 'The people it made were undone.');
        for (Import_Row__c row : ImportTestDataFactory.reload(batch.Id)) {
            Assert.areEqual(ImportRowProcessor.STATUS_REJECTED, row.Status__c, 'Rejected.');
            Assert.areEqual('Failed for the test.', row.Error_Message__c, 'Saying why.');
            Assert.isNull(row.Contact_1__c, 'Naming nobody the rollback removed.');
        }
        Assert.areEqual(
            ImportBatchService.STATUS_FAILED,
            ImportBatchSelector.selectById(batch.Id).Status__c,
            'The run says it failed.'
        );
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

/**
 * The life of a batch: created, staged in pages, dry run before commit, and finished with
 * counts read back from the rows rather than carried in memory.
 */
@IsTest
private class ImportBatchServiceTest {
    @TestSetup
    static void setUp() {
        TestDataFactory.defaultSettings();
    }

    private static Import_Template__c newTemplate() {
        return ImportTestDataFactory.template(
            ImportTestDataFactory.donorMapping(),
            ImportTemplateService.RULE_EMAIL
        );
    }

    @IsTest
    static void createsABatchWithTheOrgChunkSize() {
        Nonprofit_Settings__c settings = Nonprofit_Settings__c.getOrgDefaults();
        settings.Import_Chunk_Size__c = 50;
        TestDataFactory.saveSettings(settings);
        Import_Template__c template = newTemplate();

        Test.startTest();
        Import_Batch__c batch = ImportBatchService.create(template.Id, null, 'donors.csv');
        Test.stopTest();

        Assert.areEqual(50, batch.Chunk_Size__c, 'The batch takes the chunk size the org set.');
        Assert.areEqual(ImportBatchService.STATUS_DRAFT, batch.Status__c, 'It starts as a draft.');
        Assert.isTrue(batch.Is_Dry_Run__c, 'And as a dry run, because nothing has been committed.');
    }

    @IsTest
    static void fallsBackToTheDefaultChunkSizeWhenTheSettingIsNonsense() {
        Nonprofit_Settings__c settings = Nonprofit_Settings__c.getOrgDefaults();
        settings.Import_Chunk_Size__c = 0;
        TestDataFactory.saveSettings(settings);
        Test.startTest();
        Integer size = ImportBatchService.chunkSize();
        Test.stopTest();
        Assert.areEqual(
            ImportBatchService.DEFAULT_CHUNK_SIZE,
            size,
            'A chunk of zero rows would never finish, so the shipped default is used.'
        );
    }

    @IsTest
    static void stagesRowsInPagesAndKeepsFileOrder() {
        Import_Batch__c batch = ImportTestDataFactory.batch(newTemplate());

        Test.startTest();
        Integer afterFirst = ImportBatchService.stageRows(
            batch.Id,
            new List<Map<String, Object>>{
                new Map<String, Object>{ 'Email' => 'one@example.org', 'Last Name' => 'One' }
            },
            2
        );
        Integer afterSecond = ImportBatchService.stageRows(
            batch.Id,
            new List<Map<String, Object>>{
                new Map<String, Object>{ 'Email' => 'two@example.org', 'Last Name' => 'Two' }
            },
            3
        );
        Test.stopTest();

        Assert.areEqual(1, afterFirst, 'The first page staged one row.');
        Assert.areEqual(2, afterSecond, 'The count accumulates across pages.');
        List<Import_Row__c> rows = ImportTestDataFactory.reload(batch.Id);
        Assert.areEqual(2, rows[0].Row_Number__c, 'The first data row is file row two.');
        Assert.areEqual(3, rows[1].Row_Number__c, 'And the second is file row three.');
    }

    @IsTest
    static void stagingNothingChangesNothing() {
        Import_Batch__c batch = ImportTestDataFactory.batch(newTemplate());
        Test.startTest();
        Integer total = ImportBatchService.stageRows(batch.Id, null, 2);
        Test.stopTest();
        Assert.areEqual(0, total, 'An empty page is not an error.');
    }

    @IsTest
    static void refusesToStartWithNoRows() {
        Import_Batch__c batch = ImportTestDataFactory.batch(newTemplate());
        Test.startTest();
        try {
            ImportBatchService.startDryRun(batch.Id);
            Assert.fail('A file with no rows cannot be dry run.');
        } catch (ImportException e) {
            Assert.areEqual(Label.Core_Import_ErrorNoRows, e.getMessage(), 'Said plainly.');
        }
        Test.stopTest();
    }

    @IsTest
    static void refusesToCommitBeforeADryRun() {
        Import_Template__c template = newTemplate();
        Import_Batch__c batch = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(
            batch,
            new List<Map<String, String>>{
                ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null)
            }
        );

        Test.startTest();
        try {
            ImportBatchService.startCommit(batch.Id);
            Assert.fail('R-IB1: a commit needs a completed dry run first.');
        } catch (ImportException e) {
            Assert.areEqual(
                Label.Core_Import_ErrorDryRunFirst,
                e.getMessage(),
                'And says so in the words the admin guide uses.'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void refusesAMappingThatIdentifiesNobody() {
        ImportMapping useless = new ImportMapping();
        useless.columns.add(new ImportMapping.Column('City', 'Contact1.MailingCity'));
        Import_Template__c template = ImportTestDataFactory.template(
            useless.serialize(),
            ImportTemplateService.RULE_EMAIL
        );
        Import_Batch__c batch = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(
            batch,
            new List<Map<String, String>>{ new Map<String, String>{ 'City' => 'Portland' } }
        );

        Test.startTest();
        try {
            ImportBatchService.startDryRun(batch.Id);
            Assert.fail('A mapping that identifies nobody is refused before the run.');
        } catch (ImportException e) {
            Assert.areEqual(
                Label.Core_Import_ErrorMappingIdentifiesNobody,
                e.getMessage(),
                'With the message the admin guide quotes.'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void resettingRowsPutsThemAllBackToPending() {
        Import_Batch__c batch = ImportTestDataFactory.batch(newTemplate());
        List<Import_Row__c> rows = ImportTestDataFactory.rows(
            batch,
            new List<Map<String, String>>{
                ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null)
            }
        );
        rows[0].Status__c = ImportRowProcessor.STATUS_REJECTED;
        rows[0].Error_Message__c = 'Something went wrong';
        update rows;

        Test.startTest();
        ImportBatchService.resetRows(batch.Id);
        Test.stopTest();

        Import_Row__c after = ImportTestDataFactory.reload(batch.Id)[0];
        Assert.areEqual(ImportRowProcessor.STATUS_PENDING, after.Status__c, 'Back to pending.');
        Assert.isNull(after.Error_Message__c, 'And the old reason is cleared with it.');
    }

    @IsTest
    static void finishingADryRunCountsFromTheRowsAndCommitsNothing() {
        Import_Batch__c batch = ImportTestDataFactory.batch(newTemplate());
        List<Import_Row__c> rows = ImportTestDataFactory.rows(
            batch,
            new List<Map<String, String>>{
                ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null),
                ImportTestDataFactory.donorRow('Ben', 'Okafor', 'ben@example.org', null)
            }
        );
        rows[0].Status__c = ImportRowProcessor.STATUS_CREATED;
        rows[1].Status__c = ImportRowProcessor.STATUS_REJECTED;
        update rows;

        Test.startTest();
        Import_Batch__c after = ImportBatchService.finish(
            batch.Id,
            true,
            false,
            new List<String>{ 'A line of the run log' }
        );
        Test.stopTest();

        Assert.areEqual(1, after.Rows_Created__c, 'Counted from the rows themselves.');
        Assert.areEqual(1, after.Rows_Rejected__c, 'Including the failures.');
        Assert.areEqual(
            ImportBatchService.STATUS_DRY_RUN_COMPLETE,
            after.Status__c,
            'A dry run ends ready for a commit.'
        );
        Assert.isNull(after.Committed_By__c, 'Nobody committed it.');
        Assert.isNull(after.Undo_Deadline__c, 'And there is nothing to undo.');
    }

    @IsTest
    static void finishingACommitRecordsWhoAndOpensTheUndoWindow() {
        Import_Template__c template = newTemplate();
        Import_Batch__c batch = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(
            batch,
            new List<Map<String, String>>{
                ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null)
            }
        );

        Test.startTest();
        Import_Batch__c after = ImportBatchService.finish(batch.Id, false, false, null);
        Test.stopTest();

        Assert.areEqual(ImportBatchService.STATUS_COMPLETE, after.Status__c, 'It completed.');
        Assert.areEqual(UserInfo.getUserId(), after.Committed_By__c, 'The committer is recorded.');
        Assert.isNotNull(after.Undo_Deadline__c, 'And the undo window is open (R-IB6).');
        Assert.areEqual(
            Date.today(),
            [SELECT Last_Import_Date__c FROM Import_Template__c WHERE Id = :template.Id]
            .Last_Import_Date__c,
            'The template records that its feed was loaded today.'
        );
    }

    @IsTest
    static void aFailedRunSaysSoRatherThanReportingSuccess() {
        Import_Batch__c batch = ImportTestDataFactory.batch(newTemplate());
        ImportTestDataFactory.rows(
            batch,
            new List<Map<String, String>>{
                ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null)
            }
        );
        Test.startTest();
        Import_Batch__c after = ImportBatchService.finish(
            batch.Id,
            false,
            true,
            new List<String>{ 'Chunk 1 failed' }
        );
        Test.stopTest();
        Assert.areEqual(ImportBatchService.STATUS_FAILED, after.Status__c, 'Marked as failed.');
        Assert.isTrue(after.Run_Log__c.contains('Chunk 1 failed'), 'With the reason in the log.');
    }

    @IsTest
    static void refusesToActOnABatchThatIsGone() {
        Import_Batch__c batch = ImportTestDataFactory.batch(newTemplate());
        Id batchId = batch.Id;
        delete batch;
        Test.startTest();
        try {
            ImportBatchService.startDryRun(batchId);
            Assert.fail('A deleted batch cannot be run.');
        } catch (ImportException e) {
            Assert.areEqual(Label.Core_Import_ErrorBatchGone, e.getMessage(), 'Said plainly.');
        }
        Test.stopTest();
    }
}

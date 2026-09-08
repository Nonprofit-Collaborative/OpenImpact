/**
 * The controller: the permission gate on everything that changes anything, and the shapes the
 * two screens are built against.
 */
@IsTest
private class ImportControllerTest {
    @TestSetup
    static void setUp() {
        TestDataFactory.defaultSettings();
    }

    private static Import_Template__c permittedTemplate() {
        ImportController.permissionOverride = true;
        return ImportTestDataFactory.template(
            ImportTestDataFactory.donorMapping(),
            ImportTemplateService.RULE_EMAIL
        );
    }

    @IsTest
    static void refusesEveryChangeWithoutThePermission() {
        ImportController.permissionOverride = false;
        Test.startTest();
        try {
            ImportController.getTemplates();
            Assert.fail('Importing needs the Manage Nonprofit Settings permission.');
        } catch (Exception e) {
            Assert.isTrue(
                e.getMessage().contains('Manage Nonprofit Settings'),
                'And says which permission and who to ask: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void reportsWhetherTheUserMayImport() {
        ImportController.permissionOverride = true;
        Assert.isTrue(ImportController.canImport(), 'Permitted.');
        ImportController.permissionOverride = false;
        Assert.isFalse(ImportController.canImport(), 'Not permitted.');
    }

    @IsTest
    static void listsTemplatesForTheWizard() {
        ImportController.permissionOverride = true;
        Test.startTest();
        List<ImportController.TemplateView> templates = ImportController.getTemplates();
        Test.stopTest();
        Assert.isFalse(templates.isEmpty(), 'The shipped mappings are offered on first use.');
        Assert.isNotNull(templates[0].name, 'Each one has a name to show.');
        Assert.isNotNull(templates[0].mapping, 'And its mapping, so the picker can start from it.');
    }

    @IsTest
    static void suggestsAMappingAndPrefersTheTemplateOwnChoices() {
        Import_Template__c template = permittedTemplate();

        Test.startTest();
        String document = ImportController.suggestMapping(
            template.Id,
            new List<String>{ 'First Name', 'Email', 'Board seat expiry' }
        );
        Test.stopTest();

        Map<String, String> targets = ImportMapping.parse(document).targetsBySourceKey();
        Assert.areEqual('Contact1.Email', targets.get('email'), 'A known heading is suggested.');
        Assert.isFalse(
            targets.containsKey('board seat expiry'),
            'And one nobody recognizes loads nothing rather than being guessed at.'
        );
    }

    @IsTest
    static void createsABatchAndSavesTheMappingWithIt() {
        Import_Template__c template = permittedTemplate();
        ImportMapping mapping = ImportMapping.parse(ImportTestDataFactory.donorMapping());
        mapping.columns.add(new ImportMapping.Column('Phone', 'Contact1.Phone'));

        Test.startTest();
        ImportController.BatchView view = ImportController.createBatch(
            template.Id,
            null,
            'donors.csv',
            mapping.serialize(),
            ImportTemplateService.RULE_EMAIL
        );
        Test.stopTest();

        Assert.isNotNull(view.id, 'The batch was created.');
        Assert.areEqual('donors.csv', view.fileName, 'With the name the administrator uploaded.');
        Assert.isTrue(
            [SELECT Column_Mapping_JSON__c FROM Import_Template__c WHERE Id = :template.Id]
                .Column_Mapping_JSON__c.contains('Contact1.Phone'),
            'And the mapping was saved back, so next month needs no work.'
        );
    }

    @IsTest
    static void stagesRowsFromTheBrowserPage() {
        Import_Template__c template = permittedTemplate();
        Import_Batch__c batch = ImportTestDataFactory.batch(template);
        String rowsJson = JSON.serialize(
            new List<Map<String, String>>{
                ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null)
            }
        );

        Test.startTest();
        Integer total = ImportController.stageRows(batch.Id, rowsJson, 2);
        Test.stopTest();

        Assert.areEqual(1, total, 'One row staged.');
        Assert.areEqual(
            2,
            ImportTestDataFactory.reload(batch.Id)[0].Row_Number__c,
            'File row two.'
        );
    }

    @IsTest
    static void runsADryRunAndReportsTheBatchBack() {
        Import_Template__c template = permittedTemplate();
        Import_Batch__c batch = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(
            batch,
            new List<Map<String, String>>{
                ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null)
            }
        );

        Test.startTest();
        ImportController.BatchView view = ImportController.startDryRun(batch.Id);
        Test.stopTest();

        Assert.isNotNull(view, 'The screen gets the batch back to poll on.');
        Assert.areEqual(0, [SELECT COUNT() FROM Contact], 'A dry run wrote nothing.');
        Assert.areEqual(
            ImportBatchService.STATUS_DRY_RUN_COMPLETE,
            ImportBatchSelector.selectById(batch.Id).Status__c,
            'And it finished, because the batch ran inside the test.'
        );
    }

    @IsTest
    static void returnsRejectedRowsForTheExceptionsFile() {
        Import_Template__c template = permittedTemplate();
        Import_Batch__c batch = ImportTestDataFactory.batch(template);
        List<Import_Row__c> rows = ImportTestDataFactory.rows(
            batch,
            new List<Map<String, String>>{
                ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null),
                ImportTestDataFactory.donorRow('Nobody', null, null, null)
            }
        );
        rows[1].Status__c = ImportRowProcessor.STATUS_REJECTED;
        rows[1].Error_Message__c = Label.Core_Import_ErrorLastNameMissing;
        update rows;

        Test.startTest();
        List<ImportController.RowView> rejected = ImportController.getRows(
            batch.Id,
            ImportRowProcessor.STATUS_REJECTED,
            0
        );
        Test.stopTest();

        Assert.areEqual(1, rejected.size(), 'Only the rejected row comes back.');
        Assert.areEqual(3, rejected[0].rowNumber, 'Named by its row number in the file.');
        Assert.areEqual(
            Label.Core_Import_ErrorLastNameMissing,
            rejected[0].errorMessage,
            'With the reason the administrator can act on.'
        );
        Assert.isNotNull(rejected[0].values, 'And the original values, for the exceptions file.');
    }

    @IsTest
    static void listsRecentImportsWithoutThePermission() {
        ImportController.permissionOverride = true;
        Import_Template__c template = ImportTestDataFactory.template(
            ImportTestDataFactory.donorMapping(),
            ImportTemplateService.RULE_EMAIL
        );
        ImportTestDataFactory.batch(template);
        ImportController.permissionOverride = false;

        Test.startTest();
        List<ImportController.BatchView> recent = ImportController.getRecentBatches(5);
        Test.stopTest();

        Assert.areEqual(
            1,
            recent.size(),
            'A colleague can watch how an import is going without the administrator permission.'
        );
    }

    @IsTest
    static void keepsTheUploadedFileWhenOneIsSent() {
        ImportController.permissionOverride = true;
        Test.startTest();
        String documentId = ImportController.saveFile(
            'donors.csv',
            EncodingUtil.base64Encode(Blob.valueOf('Email\nana@example.org'))
        );
        Test.stopTest();
        Assert.isNotNull(documentId, 'The original can be downloaded again.');
    }

    @IsTest
    static void sendingNoFileIsNotAnError() {
        ImportController.permissionOverride = true;
        Test.startTest();
        Assert.isNull(
            ImportController.saveFile('donors.csv', null),
            'A file too large to send is simply not kept; the import still runs.'
        );
        Test.stopTest();
    }

    @IsTest
    static void aMissingBatchReadsAsNothingRatherThanThrowing() {
        Test.startTest();
        Assert.isNull(ImportController.getBatch(null), 'No batch, no view, no exception.');
        Test.stopTest();
    }
}

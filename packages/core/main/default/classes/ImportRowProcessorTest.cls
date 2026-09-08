/**
 * The processor: what a row means, what a dry run promises, and what happens to a row that
 * cannot be loaded.
 *
 * The assertion that matters most here is the one in `dryRunWritesNothing`: the preview an
 * administrator decides on has to be free.
 */
@IsTest
private class ImportRowProcessorTest {
    private static Import_Template__c template;
    private static Import_Batch__c batch;

    private static void given(List<Map<String, String>> values) {
        TestDataFactory.defaultSettings();
        template = ImportTestDataFactory.template(
            ImportTestDataFactory.donorMapping(),
            ImportTemplateService.RULE_EMAIL
        );
        batch = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(batch, values);
    }

    private static ImportRowProcessor.Outcome run(Boolean dryRun) {
        return ImportRowProcessor.process(
            batch,
            template,
            ImportMapping.parse(template.Column_Mapping_JSON__c),
            ImportTestDataFactory.reload(batch.Id),
            dryRun
        );
    }

    @IsTest
    static void createsAPersonAndTheirHousehold() {
        given(
            new List<Map<String, String>>{
                ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null)
            }
        );
        Test.startTest();
        ImportRowProcessor.Outcome outcome = run(false);
        Test.stopTest();

        Assert.areEqual(1, outcome.created, 'The row created a person.');
        List<Contact> contacts = [SELECT Id, LastName, AccountId FROM Contact];
        Assert.areEqual(1, contacts.size(), 'One contact was inserted.');
        Assert.isNotNull(
            contacts[0].AccountId,
            'And the household trigger gave them a household, which the importer did not build.'
        );
        Import_Row__c row = ImportTestDataFactory.reload(batch.Id)[0];
        Assert.areEqual(ImportRowProcessor.STATUS_CREATED, row.Status__c, 'The row says so.');
        Assert.areEqual(contacts[0].Id, row.Contact_1__c, 'And points at what it created.');
    }

    @IsTest
    static void tagsEveryRecordWithTheImportThatCreatedIt() {
        given(
            new List<Map<String, String>>{
                ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', 'Rose City')
            }
        );
        Test.startTest();
        run(false);
        Test.stopTest();

        Assert.areEqual(
            batch.Id,
            [SELECT Created_By_Import_Batch__c FROM Contact LIMIT 1].Created_By_Import_Batch__c,
            'The person carries the batch tag (R-IB3).'
        );
        Assert.areEqual(
            batch.Id,
            [
                SELECT Created_By_Import_Batch__c
                FROM Account
                WHERE Name = 'Rose City'
                LIMIT 1
            ]
            .Created_By_Import_Batch__c,
            'So does the organization.'
        );
    }

    @IsTest
    static void dryRunWritesNothing() {
        given(
            new List<Map<String, String>>{
                ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', 'Rose City')
            }
        );
        Test.startTest();
        ImportRowProcessor.Outcome outcome = run(true);
        Test.stopTest();

        Assert.areEqual(1, outcome.created, 'The preview says the row would create something.');
        Assert.areEqual(0, [SELECT COUNT() FROM Contact], 'And nothing at all was written.');
        Assert.areEqual(0, [SELECT COUNT() FROM Account], 'Not an organization either.');
        Assert.areEqual(
            ImportRowProcessor.STATUS_CREATED,
            ImportTestDataFactory.reload(batch.Id)[0].Status__c,
            'The staged row still records what would happen, which is what the preview shows.'
        );
    }

    @IsTest
    static void matchesAnExistingPersonInsteadOfDuplicatingThem() {
        insert new Contact(FirstName = 'Ana', LastName = 'Ramirez', Email = 'ana@example.org');
        given(
            new List<Map<String, String>>{
                ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null)
            }
        );
        Test.startTest();
        ImportRowProcessor.Outcome outcome = run(false);
        Test.stopTest();

        Assert.areEqual(0, outcome.created, 'Nobody new was created.');
        Assert.areEqual(1, [SELECT COUNT() FROM Contact], 'There is still one Ana Ramirez.');
        Assert.areEqual(
            1,
            outcome.matched + outcome.updated,
            'The row matched the person already there.'
        );
    }

    @IsTest
    static void runningTheSameFileTwiceDoesNotDuplicate() {
        given(
            new List<Map<String, String>>{
                ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', 'Rose City')
            }
        );
        Test.startTest();
        run(false);
        ImportBatchService.resetRows(batch.Id);
        run(false);
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM Contact], 'Idempotent per row (R-IB4).');
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Account WHERE Name = 'Rose City'],
            'And the organization was not created twice either.'
        );
    }

    @IsTest
    static void twoRowsNamingOneNewOrganizationCreateItOnce() {
        given(
            new List<Map<String, String>>{
                ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', 'Rose City'),
                ImportTestDataFactory.donorRow('Ben', 'Okafor', 'ben@example.org', 'Rose City')
            }
        );
        Test.startTest();
        run(false);
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Account WHERE Name = 'Rose City'],
            'One file never creates the same organization twice.'
        );
        for (Import_Row__c row : ImportTestDataFactory.reload(batch.Id)) {
            Assert.isNotNull(row.Organization__c, 'Both rows point at it.');
        }
    }

    @IsTest
    static void rejectsARowWithNoLastNameAndKeepsTheRest() {
        given(
            new List<Map<String, String>>{
                ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null),
                ImportTestDataFactory.donorRow('Nobody', null, null, null)
            }
        );
        Test.startTest();
        ImportRowProcessor.Outcome outcome = run(false);
        Test.stopTest();

        Assert.areEqual(1, outcome.created, 'The good row went through.');
        Assert.areEqual(1, outcome.rejected, 'The bad row did not take it with it (R-IB5).');
        List<Import_Row__c> rows = ImportTestDataFactory.reload(batch.Id);
        Assert.areEqual(
            ImportRowProcessor.STATUS_REJECTED,
            rows[1].Status__c,
            'The failing row is marked rejected.'
        );
        Assert.areEqual(
            Label.Core_Import_ErrorLastNameMissing,
            rows[1].Error_Message__c,
            'With the reason the admin guide quotes word for word.'
        );
    }

    @IsTest
    static void rejectsARowThatDescribesNobody() {
        given(new List<Map<String, String>>{ new Map<String, String>{ 'City' => 'Portland' } });
        Test.startTest();
        ImportRowProcessor.Outcome outcome = run(false);
        Test.stopTest();
        Assert.areEqual(1, outcome.rejected, 'A row with only an address creates nothing.');
        Assert.areEqual(
            Label.Core_Import_ErrorRowIdentifiesNobody,
            ImportTestDataFactory.reload(batch.Id)[0].Error_Message__c,
            'And says why.'
        );
    }

    @IsTest
    static void staysBulkSafeAcrossAWholeChunk() {
        List<Map<String, String>> values = new List<Map<String, String>>();
        for (Integer i = 0; i < 50; i++) {
            values.add(
                ImportTestDataFactory.donorRow(
                    'Person' + i,
                    'Surname' + i,
                    'person' + i + '@example.org',
                    'Shared Organization'
                )
            );
        }
        given(values);

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        run(false);
        Integer queriesUsed = Limits.getQueries() - queriesBefore;
        Test.stopTest();

        Assert.areEqual(50, [SELECT COUNT() FROM Contact], 'Every row was loaded.');
        Assert.isTrue(
            queriesUsed < 25,
            'Fifty rows cost a handful of queries, not one per row: got ' + queriesUsed
        );
    }

    @IsTest
    static void splitsAFullNameColumn() {
        TestDataFactory.defaultSettings();
        ImportMapping mapping = new ImportMapping();
        mapping.columns.add(new ImportMapping.Column('Donor', 'Contact1.FullName'));
        mapping.columns.add(new ImportMapping.Column('Email', 'Contact1.Email'));
        template = ImportTestDataFactory.template(
            mapping.serialize(),
            ImportTemplateService.RULE_EMAIL
        );
        batch = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(
            batch,
            new List<Map<String, String>>{
                new Map<String, String>{ 'Donor' => 'Ana Ramirez', 'Email' => 'ana@example.org' },
                new Map<String, String>{ 'Donor' => 'Okafor, Ben', 'Email' => 'ben@example.org' }
            }
        );

        Test.startTest();
        run(false);
        Test.stopTest();

        Map<String, Contact> byEmail = new Map<String, Contact>();
        for (Contact record : [SELECT FirstName, LastName, Email FROM Contact]) {
            byEmail.put(record.Email, record);
        }
        Assert.areEqual(
            'Ana',
            byEmail.get('ana@example.org').FirstName,
            'First name from "Ana Ramirez".'
        );
        Assert.areEqual('Ramirez', byEmail.get('ana@example.org').LastName, 'And the last name.');
        Assert.areEqual(
            'Ben',
            byEmail.get('ben@example.org').FirstName,
            'The comma form reads too.'
        );
        Assert.areEqual('Okafor', byEmail.get('ben@example.org').LastName, 'Surname first.');
    }

    @IsTest
    static void saysInTheRunLogWhatItCouldNotLoad() {
        TestDataFactory.defaultSettings();
        ImportMapping mapping = new ImportMapping();
        mapping.columns.add(new ImportMapping.Column('Email', 'Contact1.Email'));
        mapping.columns.add(new ImportMapping.Column('Last Name', 'Contact1.LastName'));
        mapping.columns.add(new ImportMapping.Column('Amount', 'Gift.Amount__c'));
        template = ImportTestDataFactory.template(
            mapping.serialize(),
            ImportTemplateService.RULE_EMAIL
        );
        batch = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(
            batch,
            new List<Map<String, String>>{
                new Map<String, String>{
                    'Email' => 'ana@example.org',
                    'Last Name' => 'Ramirez',
                    'Amount' => '100'
                }
            }
        );

        Test.startTest();
        ImportRowProcessor.Outcome outcome = run(false);
        Test.stopTest();

        Assert.areEqual(1, outcome.created, 'The person still loaded.');
        Assert.isFalse(outcome.notes.isEmpty(), 'And the run log says the gift column did not.');
    }

    @IsTest
    static void anUnreadableStagedRowIsRejectedNotThrown() {
        given(
            new List<Map<String, String>>{
                ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null)
            }
        );
        List<Import_Row__c> rows = ImportTestDataFactory.reload(batch.Id);
        rows[0].Raw_Values_JSON__c = 'not JSON at all';
        update rows;

        Test.startTest();
        ImportRowProcessor.Outcome outcome = run(false);
        Test.stopTest();

        Assert.areEqual(1, outcome.rejected, 'The row is rejected.');
        Assert.areEqual(
            Label.Core_Import_ErrorRowUnreadable,
            ImportTestDataFactory.reload(batch.Id)[0].Error_Message__c,
            'With a reason, rather than an unhandled exception.'
        );
    }

    @IsTest
    static void anEmptyChunkDoesNothing() {
        TestDataFactory.defaultSettings();
        template = ImportTestDataFactory.template(
            ImportTestDataFactory.donorMapping(),
            ImportTemplateService.RULE_EMAIL
        );
        batch = ImportTestDataFactory.batch(template);
        Test.startTest();
        ImportRowProcessor.Outcome outcome = ImportRowProcessor.process(
            batch,
            template,
            ImportMapping.parse(template.Column_Mapping_JSON__c),
            new List<Import_Row__c>(),
            false
        );
        Test.stopTest();
        Assert.areEqual(0, outcome.created, 'Nothing in, nothing out, no exception.');
    }
}

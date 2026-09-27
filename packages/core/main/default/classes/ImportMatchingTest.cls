/**
 * C-32: matching per entity, the rule for several matches, values for every row of a file,
 * checkbox values, and the staged rows a commit leaves (canonical model R-IT8, R-IT9, R-IB14,
 * R-IB15). Affiliations are ImportAffiliationTest.
 *
 * The External ID rules match on a field the org itself has; Core ships no external ID field on
 * Contact or Account, so the test that loads by one returns early, on purpose, in an org without
 * one, and the refusal paths are tested everywhere.
 */
@IsTest
private class ImportMatchingTest {
    private static Import_Template__c template;
    private static Import_Batch__c batch;

    @TestSetup
    static void setUp() {
        TestDataFactory.defaultSettings();
    }

    private static void given(String mappingDocument, String rule, List<Map<String, String>> rows) {
        template = ImportTestDataFactory.template(mappingDocument, rule);
        batch = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(batch, rows);
    }

    private static void mostRecent() {
        template.Several_Matches__c = ImportTemplateService.SEVERAL_MOST_RECENT;
        update template;
    }

    private static ImportRowProcessor.Outcome run(Boolean dryRun) {
        return ImportRowProcessor.process(
            batch,
            template,
            ImportMapping.parse(template.Column_Mapping_JSON__c, template.Default_Values_JSON__c),
            ImportTestDataFactory.reload(batch.Id),
            dryRun
        );
    }

    /** Runs one pass the way the platform drives the batch, in chunks of this size. */
    private static Import_Batch__c runInChunks(Boolean dryRun, Integer chunkSize) {
        ImportBatchService.beginPass(batch.Id);
        ImportProcessorBatch job = new ImportProcessorBatch(batch.Id, dryRun);
        List<Import_Row__c> chunk = new List<Import_Row__c>();
        Database.QueryLocatorIterator rows = job.start(null).iterator();
        while (rows.hasNext()) {
            chunk.add((Import_Row__c) rows.next());
            if (chunk.size() == chunkSize || !rows.hasNext()) {
                job.execute(null, chunk);
                chunk = new List<Import_Row__c>();
            }
        }
        job.finish(null);
        return ImportBatchSelector.selectById(batch.Id);
    }

    private static List<Import_Row__c> rows() {
        return [
            SELECT
                Id,
                Row_Number__c,
                Status__c,
                Error_Message__c,
                Contact_1__c,
                Organization__c,
                Several_Matches__c
            FROM Import_Row__c
            WHERE Import_Batch__c = :batch.Id
            ORDER BY Row_Number__c
        ];
    }

    private static Id organizationType() {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization')
            .getRecordTypeId();
    }

    private static List<Map<String, String>> anaRows(Integer howMany) {
        List<Map<String, String>> values = new List<Map<String, String>>();
        for (Integer i = 0; i < howMany; i++) {
            values.add(ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null));
        }
        return values;
    }

    // -------------------------------------------------------------------------------------
    // Several matches (R-IT9)
    // -------------------------------------------------------------------------------------

    @IsTest
    static void aPersonSeveralRecordsMatchIsRejectedByDefaultAndListed() {
        insert new List<Contact>{
            new Contact(FirstName = 'Ana', LastName = 'Ramirez', Email = 'ana@example.org'),
            new Contact(FirstName = 'Ana', LastName = 'Ramirez', Email = 'ana@example.org')
        };
        given(ImportTestDataFactory.donorMapping(), ImportTemplateService.RULE_EMAIL, anaRows(1));

        Test.startTest();
        ImportRowProcessor.Outcome preview = run(true);
        ImportRowProcessor.Outcome committed = run(false);
        Test.stopTest();

        Assert.areEqual(1, preview.rejected, 'The dry run rejects the row: ' + preview.notes);
        Assert.areEqual(1, committed.rejected, 'And so does the commit.');
        Import_Row__c row = rows()[0];
        Assert.isTrue(row.Several_Matches__c, 'The row is marked for the dry run list.');
        Assert.areEqual(Label.Core_Import_ErrorSeveralPeople, row.Error_Message__c, 'It says why.');
        Assert.isNull(row.Contact_1__c, 'It names neither record.');
        Assert.areEqual(2, [SELECT COUNT() FROM Contact], 'Nobody was added or merged.');
    }

    @IsTest
    static void aPersonSeveralRecordsMatchTakesTheMostRecentlyChangedWhenAsked() {
        Contact older = new Contact(
            FirstName = 'Ana',
            LastName = 'Ramirez',
            Email = 'ana@example.org'
        );
        insert older;
        Contact newer = new Contact(
            FirstName = 'Ana',
            LastName = 'Ramirez',
            Email = 'ana@example.org'
        );
        insert newer;
        given(ImportTestDataFactory.donorMapping(), ImportTemplateService.RULE_EMAIL, anaRows(1));
        mostRecent();

        Test.startTest();
        ImportRowProcessor.Outcome committed = run(false);
        Test.stopTest();

        Assert.areEqual(0, committed.rejected, 'Not rejected: ' + rows()[0].Error_Message__c);
        Import_Row__c row = rows()[0];
        // Saved later, or in the same second with the higher identifier: either way the newer.
        Assert.areEqual(newer.Id, row.Contact_1__c, 'The most recently changed record.');
        Assert.isTrue(row.Several_Matches__c, 'And the row is still listed.');
        Assert.areEqual(2, [SELECT COUNT() FROM Contact], 'Nobody was added.');
    }

    @IsTest
    static void aRowWithNoFirstNameWhereTwoHoldTheKeyIsSeveralMatches() {
        insert new List<Contact>{
            new Contact(FirstName = 'John', LastName = 'Smith', MailingPostalCode = '12345'),
            new Contact(FirstName = 'Jane', LastName = 'Smith', MailingPostalCode = '12345')
        };
        ImportMapping mapping = new ImportMapping();
        mapping.columns.add(new ImportMapping.Column('Last', 'Contact1.LastName'));
        mapping.columns.add(new ImportMapping.Column('Zip', 'Contact1.MailingPostalCode'));
        given(
            mapping.serialize(),
            ImportTemplateService.RULE_NAME_POSTAL,
            new List<Map<String, String>>{
                new Map<String, String>{ 'Last' => 'Smith', 'Zip' => '12345' }
            }
        );

        Test.startTest();
        Import_Batch__c preview = runInChunks(true, 200);
        Import_Batch__c committed = runInChunks(false, 200);
        Test.stopTest();

        Assert.areEqual(1, preview.Rows_Rejected__c, 'Before C-32 the earliest won; now rejected.');
        Assert.areEqual(1, committed.Rows_Rejected__c, 'The commit agrees with the dry run.');
        Assert.isTrue(rows()[0].Several_Matches__c, 'And lists the row.');
        Assert.isTrue(
            committed.Run_Log__c.contains(
                String.format(Label.Core_Import_LogSeveralMatches, new List<String>{ '1' })
            ),
            'The run log counts the rows that matched several: ' + committed.Run_Log__c
        );
    }

    @IsTest
    static void aCoupleSharingAKeyIsStillNotSeveralMatches() {
        insert new List<Contact>{
            new Contact(FirstName = 'John', LastName = 'Smith', Email = 'smiths@example.org'),
            new Contact(FirstName = 'Jane', LastName = 'Smith', Email = 'smiths@example.org')
        };
        given(
            ImportTestDataFactory.donorMapping(),
            ImportTemplateService.RULE_EMAIL,
            new List<Map<String, String>>{
                ImportTestDataFactory.donorRow('Jane', 'Smith', 'smiths@example.org', null)
            }
        );

        Test.startTest();
        ImportRowProcessor.Outcome committed = run(false);
        Test.stopTest();

        Assert.areEqual(0, committed.rejected, 'The first name tells the couple apart.');
        Import_Row__c row = rows()[0];
        Assert.isFalse(row.Several_Matches__c, 'One Jane holds the key and her first name.');
        Assert.areEqual(
            'Jane',
            [SELECT FirstName FROM Contact WHERE Id = :row.Contact_1__c].FirstName,
            'Jane, not John.'
        );
    }

    @IsTest
    static void twoOrganizationsWithOneNameAreSeveralMatches() {
        insert new List<Account>{
            new Account(Name = 'Rose City', RecordTypeId = organizationType()),
            new Account(Name = 'Rose City', RecordTypeId = organizationType())
        };
        given(
            ImportTestDataFactory.donorMapping(),
            ImportTemplateService.RULE_EMAIL,
            new List<Map<String, String>>{
                ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', 'Rose City')
            }
        );

        Test.startTest();
        ImportRowProcessor.Outcome preview = run(true);
        ImportRowProcessor.Outcome committed = run(false);
        Test.stopTest();

        Assert.areEqual(1, preview.rejected, 'Rejected in the dry run.');
        Assert.areEqual(1, committed.rejected, 'And in the commit.');
        Import_Row__c row = rows()[0];
        Assert.areEqual(Label.Core_Import_ErrorSeveralOrganizations, row.Error_Message__c, 'Why.');
        Assert.isTrue(row.Several_Matches__c, 'Listed.');
        Assert.areEqual(0, [SELECT COUNT() FROM Contact], 'Nothing on the row was saved.');
    }

    @IsTest
    static void twoOrganizationsWithOneNameGiveTheMostRecentlyChangedWhenAsked() {
        Account older = new Account(Name = 'Rose City', RecordTypeId = organizationType());
        insert older;
        Account newer = new Account(Name = 'Rose City', RecordTypeId = organizationType());
        insert newer;
        given(
            ImportTestDataFactory.donorMapping(),
            ImportTemplateService.RULE_EMAIL,
            new List<Map<String, String>>{
                ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', 'Rose City')
            }
        );
        mostRecent();

        Test.startTest();
        run(false);
        Test.stopTest();

        Import_Row__c row = rows()[0];
        Assert.areEqual(newer.Id, row.Organization__c, 'The most recently changed organization.');
        Assert.areEqual(
            2,
            [SELECT COUNT() FROM Account WHERE RecordTypeId = :organizationType()],
            'No third one.'
        );
    }

    @IsTest
    static void twoHundredRowsMatchingSeveralAreEachRejectedInOneChunk() {
        List<Contact> twice = new List<Contact>();
        List<Map<String, String>> values = new List<Map<String, String>>();
        for (Integer i = 0; i < 200; i++) {
            String email = 'person' + i + '@example.org';
            twice.add(new Contact(FirstName = 'P' + i, LastName = 'Twice', Email = email));
            twice.add(new Contact(FirstName = 'P' + i, LastName = 'Twice', Email = email));
            values.add(ImportTestDataFactory.donorRow('P' + i, 'Twice', email, null));
        }
        insert twice;
        given(ImportTestDataFactory.donorMapping(), ImportTemplateService.RULE_EMAIL, values);

        Test.startTest();
        Integer before = Limits.getQueries();
        ImportRowProcessor.Outcome committed = run(false);
        Integer used = Limits.getQueries() - before;
        Test.stopTest();

        Assert.areEqual(200, committed.rejected, 'Every row found two records.');
        Assert.areEqual(400, [SELECT COUNT() FROM Contact], 'Nothing added.');
        Assert.isTrue(used < 25, 'A chunk costs a handful of queries: ' + used);
    }

    // -------------------------------------------------------------------------------------
    // Matching rules and fields (R-IT8)
    // -------------------------------------------------------------------------------------

    @IsTest
    static void aChosenFieldThatIsNotAMatchFieldIsRefusedWithItsName() {
        given(
            ImportTestDataFactory.donorMapping(),
            ImportTemplateService.RULE_EXTERNAL_ID,
            anaRows(1)
        );

        Test.startTest();
        ImportException saved;
        try {
            ImportTemplateService.saveMatching(template.Id, 'Name exact', 'LastName', null, null);
        } catch (ImportException e) {
            saved = e;
        }
        template.Person_Match_Field__c = 'LastName';
        update template;
        String refusal = ImportTemplateService.matchingRefusal(
            ImportTemplateSelector.selectById(template.Id)
        );
        Test.stopTest();

        Assert.isNotNull(saved, 'Last name is neither an external ID nor unique, so not saved.');
        Assert.isTrue(saved.getMessage().contains('LastName'), 'It names the field.');
        Assert.isTrue(refusal != null && refusal.contains('LastName'), 'A dry run is refused.');
    }

    @IsTest
    static void theOrganizationExternalIdRuleNeedsItsField() {
        given(ImportTestDataFactory.donorMapping(), ImportTemplateService.RULE_EMAIL, anaRows(1));
        template.Organization_Matching_Rule__c = ImportTemplateService.ORGANIZATION_RULE_EXTERNAL_ID;
        update template;

        Test.startTest();
        String refusal = ImportTemplateService.matchingRefusal(
            ImportTemplateSelector.selectById(template.Id)
        );
        ImportException saved;
        try {
            ImportTemplateService.saveMatching(template.Id, 'External ID', null, null, null);
        } catch (ImportException e) {
            saved = e;
        }
        Test.stopTest();

        Assert.areEqual(Label.Core_Import_ErrorOrganizationFieldRequired, refusal, 'Refused.');
        Assert.isNotNull(saved, 'And not saved without a field.');
    }

    @IsTest
    static void aRowNamingAnOrganizationWithoutItsMatchFieldIsRejected() {
        given(
            ImportTestDataFactory.donorMapping(),
            ImportTemplateService.RULE_EMAIL,
            new List<Map<String, String>>{
                ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', 'Rose City')
            }
        );
        // A field no row carries, standing for any: the row names the organization only.
        template.Organization_Matching_Rule__c = ImportTemplateService.ORGANIZATION_RULE_EXTERNAL_ID;
        template.Organization_Match_Field__c = 'Sample_Data_Key__c';
        update template;
        template = ImportTemplateSelector.selectById(template.Id);

        Test.startTest();
        ImportRowProcessor.Outcome committed = run(false);
        Test.stopTest();

        Assert.areEqual(1, committed.rejected, 'Neither matchable nor safely created.');
        Assert.areEqual(
            Label.Core_Import_ErrorOrganizationKeyMissing,
            rows()[0].Error_Message__c,
            'It says which column to fill.'
        );
        Assert.areEqual(0, [SELECT COUNT() FROM Contact], 'Nothing on the row was saved.');
    }

    @IsTest
    static void matchFieldsAreTheObjectsExternalIdAndUniqueTextFields() {
        Test.startTest();
        List<ImportMapping.Target> fields = ImportMatcher.matchFields(
            Import_Template__c.SObjectType
        );
        String lastName = ImportMatcher.matchField(Contact.SObjectType, 'LastName');
        Test.stopTest();

        Set<String> names = new Set<String>();
        for (ImportMapping.Target field : fields) {
            names.add(field.value.toLowerCase());
        }
        String key = Import_Template__c.Template_Key__c.getDescribe().getName().toLowerCase();
        Assert.isTrue(names.contains(key), 'The template key is external and unique: ' + names);
        Assert.isFalse(names.contains('name'), 'The name is neither.');
        Assert.isNull(lastName, 'Last name is no match field.');
    }

    @IsTest
    static void byFieldFindsRecordsIgnoringCaseAndMarksSeveral() {
        given(ImportTestDataFactory.donorMapping(), ImportTemplateService.RULE_EMAIL, anaRows(1));
        String key = template.Template_Key__c;

        Test.startTest();
        ImportMatcher.forgetHeldKeys();
        Map<String, Id> found = ImportMatcher.byField(
            Import_Template__c.SObjectType,
            'Template_Key__c',
            new Set<String>{ key },
            null
        );
        Test.stopTest();

        Assert.areEqual(template.Id, found.get(key.toLowerCase()), 'Found by its key.');
        Assert.isFalse(ImportMatcher.isHeldByMany(key.toLowerCase()), 'One record holds it.');
        Assert.areEqual(template.Id, ImportMatcher.mostRecent(key.toLowerCase()), 'The latest.');
    }

    @IsTest
    static void peopleAreMatchedOnAChosenExternalIdFieldWhereTheOrgHasOne() {
        List<ImportMapping.Target> fields = ImportMatcher.matchFields(Contact.SObjectType);
        if (fields.isEmpty()) {
            // Core ships no external ID field on Contact: nothing to match on in this org.
            Assert.isTrue(fields.isEmpty(), 'No field to choose.');
            return;
        }
        String field = fields[0].value;
        Contact ana = new Contact(FirstName = 'Ana', LastName = 'Ramirez');
        ana.put(field, 'D-100');
        insert ana;
        ImportMapping mapping = new ImportMapping();
        mapping.columns.add(new ImportMapping.Column('Donor', 'Contact1.' + field));
        mapping.columns.add(new ImportMapping.Column('Last Name', 'Contact1.LastName'));
        given(
            mapping.serialize(),
            ImportTemplateService.RULE_EXTERNAL_ID,
            new List<Map<String, String>>{
                new Map<String, String>{ 'Donor' => 'd-100', 'Last Name' => 'Ramirez' }
            }
        );
        ImportTemplateService.saveMatching(template.Id, 'Name exact', field, null, null);
        template = ImportTemplateSelector.selectById(template.Id);

        Test.startTest();
        run(false);
        Test.stopTest();

        Assert.areEqual(ana.Id, rows()[0].Contact_1__c, 'Found by the chosen field.');
        Assert.areEqual(1, [SELECT COUNT() FROM Contact], 'Not created again.');
    }

    // -------------------------------------------------------------------------------------
    // Values for every row of a file (R-IB14)
    // -------------------------------------------------------------------------------------

    @IsTest
    static void aFileValueFillsTheRowsWithoutOneAndLosesToTheRowsOwn() {
        ImportMapping mapping = ImportMapping.parse(ImportTestDataFactory.donorMapping());
        mapping.columns.add(new ImportMapping.Column('Job', 'Contact1.Title'));
        Map<String, String> withTitle = ImportTestDataFactory.donorRow(
            'Ana',
            'Ramirez',
            'ana@example.org',
            null
        );
        withTitle.put('Job', 'Treasurer');
        Map<String, String> withoutTitle = ImportTestDataFactory.donorRow(
            'Ben',
            'Okafor',
            'ben@example.org',
            null
        );
        given(
            mapping.serialize(),
            ImportTemplateService.RULE_EMAIL,
            new List<Map<String, String>>{ withTitle, withoutTitle }
        );
        // The template's default loses to the file's value, which loses to the row's own.
        template.Default_Values_JSON__c = '{"version":1,"defaults":[{"target":"Contact1.Title","value":"Donor"}]}';
        update template;
        batch.File_Values_JSON__c = ImportMapping.valuesDocument(
            new List<ImportMapping.Assignment>{
                new ImportMapping.Assignment('Contact1.Title', 'Gala guest')
            }
        );
        update batch;

        Test.startTest();
        run(false);
        Test.stopTest();

        Map<String, String> titles = new Map<String, String>();
        for (Contact person : [SELECT FirstName, Title FROM Contact]) {
            titles.put(person.FirstName, person.Title);
        }
        Assert.areEqual('Treasurer', titles.get('Ana'), 'The row keeps its own value.');
        Assert.areEqual('Gala guest', titles.get('Ben'), 'The file value fills the rest.');
    }

    @IsTest
    static void aBatchKeepsItsFileValuesAndRefusesTooMany() {
        given(ImportTestDataFactory.donorMapping(), ImportTemplateService.RULE_EMAIL, anaRows(1));
        List<ImportMapping.Assignment> values = new List<ImportMapping.Assignment>{
            new ImportMapping.Assignment('Gift.Appeal', 'Gala 2026'),
            new ImportMapping.Assignment('Contact1.Title', '  '),
            new ImportMapping.Assignment('Ignore', 'nothing')
        };
        List<ImportMapping.Assignment> tooMany = new List<ImportMapping.Assignment>();
        for (Integer i = 0; i <= ImportMapping.MAX_FILE_VALUES; i++) {
            tooMany.add(new ImportMapping.Assignment('Contact1.Title', 'Value ' + i));
        }

        Test.startTest();
        Import_Batch__c created = ImportBatchService.create(
            template.Id,
            null,
            'gala.csv',
            null,
            null,
            values
        );
        ImportException refused;
        try {
            ImportBatchService.create(template.Id, null, 'gala.csv', null, null, tooMany);
        } catch (ImportException e) {
            refused = e;
        }
        Test.stopTest();

        List<ImportMapping.Assignment> kept = ImportMapping.parseValues(
            [SELECT File_Values_JSON__c FROM Import_Batch__c WHERE Id = :created.Id]
            .File_Values_JSON__c
        );
        Assert.areEqual(1, kept.size(), 'Only the value with a target and a value is kept.');
        Assert.areEqual('Gift.Appeal', kept[0].target, 'The appeal.');
        Assert.areEqual('Gala 2026', kept[0].value, 'For Gala 2026.');
        Assert.isNotNull(refused, 'More values than a file may carry are refused, not cut.');
    }

    @IsTest
    static void fileValuesAreNeverSavedIntoTheTemplatesDocument() {
        ImportMapping mapping = ImportMapping.parse(ImportTestDataFactory.donorMapping());
        mapping.fileValues = new List<ImportMapping.Assignment>{
            new ImportMapping.Assignment('Gift.Appeal', 'Gala 2026')
        };

        Test.startTest();
        String document = mapping.serialize();
        Test.stopTest();

        Assert.isFalse(document.contains('Gala 2026'), 'The file values belong to the batch.');
        Assert.isTrue(mapping.mappedEntities().contains('Gift'), 'But they are part of the load.');
    }

    // -------------------------------------------------------------------------------------
    // Checkbox values (contributor guide, CI work item 2)
    // -------------------------------------------------------------------------------------

    @IsTest
    static void checkboxWordsReadAsTheAdminGuideSays() {
        for (String word : new List<String>{ 'true', 'YES', 'y', '1', 'x', 'Checked', 'on', 't' }) {
            Assert.areEqual(true, ImportRowProcessor.readCheckbox(word), word + ' ticks the box.');
        }
        for (String word : new List<String>{ 'false', 'No', 'n', '0', 'OFF', 'f' }) {
            Assert.areEqual(false, ImportRowProcessor.readCheckbox(word), word + ' unticks it.');
        }
        for (String word : new List<String>{ '', null, 'maybe', 'Opted out', '2' }) {
            Assert.isNull(ImportRowProcessor.readCheckbox(word), word + ' is not read.');
        }
    }

    @IsTest
    static void twoHundredCheckboxRowsLoadAndAnUnreadableValueIsNamedOnce() {
        ImportMapping mapping = ImportMapping.parse(ImportTestDataFactory.donorMapping());
        mapping.columns.add(new ImportMapping.Column('Opt Out', 'Contact1.HasOptedOutOfEmail'));
        List<Map<String, String>> values = new List<Map<String, String>>();
        for (Integer i = 0; i < 200; i++) {
            Map<String, String> row = ImportTestDataFactory.donorRow(
                'P' + i,
                'Box',
                'box' + i + '@example.org',
                null
            );
            row.put('Opt Out', Math.mod(i, 2) == 0 ? 'x' : 'Opted out ' + i);
            values.add(row);
        }
        given(mapping.serialize(), ImportTemplateService.RULE_EMAIL, values);

        Test.startTest();
        ImportRowProcessor.Outcome committed = run(false);
        Test.stopTest();

        Assert.areEqual(200, committed.created, 'Every row loaded: ' + committed.notes);
        Assert.areEqual(
            100,
            [SELECT COUNT() FROM Contact WHERE HasOptedOutOfEmail = TRUE],
            'x ticks the box.'
        );
        Integer mentions = 0;
        String label = Contact.HasOptedOutOfEmail.getDescribe().getLabel();
        for (String note : committed.notes) {
            if (note.contains(label) && note.contains('Opted out')) {
                mentions++;
            }
        }
        Assert.areEqual(1, mentions, 'The unreadable values are named once: ' + committed.notes);
    }

    @IsTest
    static void anUnreadableCheckboxValueNeverUnticksAMatchedPerson() {
        insert new Contact(
            FirstName = 'Ana',
            LastName = 'Ramirez',
            Email = 'ana@example.org',
            MailingCity = 'Portland',
            HasOptedOutOfEmail = true
        );
        ImportMapping mapping = ImportMapping.parse(ImportTestDataFactory.donorMapping());
        mapping.columns.add(new ImportMapping.Column('Opt Out', 'Contact1.HasOptedOutOfEmail'));
        Map<String, String> row = ImportTestDataFactory.donorRow(
            'Ana',
            'Ramirez',
            'ana@example.org',
            null
        );
        row.put('Opt Out', 'Unsubscribed');
        given(
            mapping.serialize(),
            ImportTemplateService.RULE_EMAIL,
            new List<Map<String, String>>{ row }
        );

        Test.startTest();
        ImportRowProcessor.Outcome preview = run(true);
        ImportRowProcessor.Outcome committed = run(false);
        Test.stopTest();

        Assert.areEqual(1, preview.matched, 'No change in the dry run: ' + preview.notes);
        Assert.areEqual(1, committed.matched, 'Nor in the commit.');
        Assert.isTrue(
            [SELECT HasOptedOutOfEmail FROM Contact LIMIT 1].HasOptedOutOfEmail,
            'The opt-out stands.'
        );
    }

    // -------------------------------------------------------------------------------------
    // Staged rows after a commit (R-IB15)
    // -------------------------------------------------------------------------------------

    @IsTest
    static void aCommitsStagedRowsGoExceptTheRejectedOnes() {
        List<Map<String, String>> values = anaRows(1);
        values.add(ImportTestDataFactory.donorRow('Ben', null, null, null));
        given(ImportTestDataFactory.donorMapping(), ImportTemplateService.RULE_EMAIL, values);
        ImportBatchService.purgeAfterCommit = true;

        Test.startTest();
        runInChunks(true, 200);
        Integer afterDryRun = [SELECT COUNT() FROM Import_Row__c WHERE Import_Batch__c = :batch.Id];
        Import_Batch__c committed = runInChunks(false, 200);
        Test.stopTest();

        Assert.areEqual(2, afterDryRun, 'A dry run keeps every row: the commit runs over them.');
        Assert.areEqual(1, committed.Rows_Created__c, 'Counted before the rows went.');
        Assert.areEqual(1, committed.Rows_Rejected__c, 'Both counts.');
        List<Import_Row__c> left = rows();
        Assert.areEqual(1, left.size(), 'Only the rejected row is left: ' + left);
        Assert.areEqual(ImportRowProcessor.STATUS_REJECTED, left[0].Status__c, 'The rejected one.');
    }

    @IsTest
    static void thePurgeTouchesOnlyItsOwnBatch() {
        given(ImportTestDataFactory.donorMapping(), ImportTemplateService.RULE_EMAIL, anaRows(3));
        Import_Batch__c other = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(other, anaRows(2));

        Test.startTest();
        Database.executeBatch(new ImportRowPurgeBatch(batch.Id), ImportRowPurgeBatch.SCOPE);
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Import_Row__c WHERE Import_Batch__c = :batch.Id],
            'Gone.'
        );
        Assert.areEqual(
            2,
            [SELECT COUNT() FROM Import_Row__c WHERE Import_Batch__c = :other.Id],
            'Another batch is untouched.'
        );
    }

    // -------------------------------------------------------------------------------------
    // Access
    // -------------------------------------------------------------------------------------

    @IsTest
    static void theMatchFieldsNeedTheImportPermission() {
        given(ImportTestDataFactory.donorMapping(), ImportTemplateService.RULE_EMAIL, anaRows(1));
        ImportController.permissionOverride = false;

        Test.startTest();
        AuraHandledException refused;
        try {
            ImportController.getMatchFields(template.Id);
        } catch (AuraHandledException e) {
            refused = e;
        }
        Test.stopTest();

        Assert.isNotNull(refused, 'Refused without the permission.');
        Assert.areEqual(Label.Core_Import_ErrorNoPermission, refused.getMessage(), 'Said so.');
    }

    @IsTest
    static void theDryRunListShowsOnlyRowsThatMatchedSeveral() {
        insert new List<Contact>{
            new Contact(FirstName = 'Ana', LastName = 'Ramirez', Email = 'ana@example.org'),
            new Contact(FirstName = 'Ana', LastName = 'Ramirez', Email = 'ana@example.org')
        };
        List<Map<String, String>> values = anaRows(1);
        values.add(ImportTestDataFactory.donorRow('Ben', 'Okafor', 'ben@example.org', null));
        given(ImportTestDataFactory.donorMapping(), ImportTemplateService.RULE_EMAIL, values);
        run(true);

        Test.startTest();
        List<ImportController.RowView> several = ImportController.getSeveralMatchRows(batch.Id, 0);
        Test.stopTest();

        Assert.areEqual(1, several.size(), 'Ana only.');
        Assert.isTrue(several[0].severalMatches, 'Marked.');
        Assert.areEqual(ImportRowProcessor.STATUS_REJECTED, several[0].status, 'And rejected.');
    }
}

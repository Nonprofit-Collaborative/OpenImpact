/**
 * C-33: a template that loads one object (canonical model R-IT10 to R-IT12). Insert, update by
 * record Id and upsert by an external ID; lookups by Id and by a field the administrator picks;
 * the rules for none and for several; what is never written; the same dry run, journal and undo.
 *
 * Affiliations stand for an object with lookups, and duplicate dismissals for one with an
 * external ID and no automation. Both are Core's, so the tests run on every org shape.
 */
@IsTest
private class ImportObjectLoaderTest {
    private static Import_Template__c template;
    private static Import_Batch__c batch;

    @TestSetup
    static void setUp() {
        TestDataFactory.defaultSettings();
    }

    private static Id organizationType() {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization')
            .getRecordTypeId();
    }

    /** A template loading this object, with these columns (source, target, lookup field). */
    private static void given(
        String objectName,
        String operation,
        List<List<String>> columns,
        List<Map<String, String>> rows
    ) {
        ImportMapping mapping = new ImportMapping();
        for (List<String> column : columns) {
            ImportMapping.Column mapped = new ImportMapping.Column(column[0], column[1]);
            mapped.lookupField = column.size() > 2 ? column[2] : null;
            mapping.columns.add(mapped);
        }
        template = ImportTestDataFactory.template(mapping.serialize(), null);
        template.Target_Object__c = objectName;
        template.Load_Operation__c = operation;
        update template;
        template = ImportTemplateSelector.selectById(template.Id);
        batch = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(batch, rows);
    }

    private static void set(Schema.SObjectField field, String value) {
        template.put(field, value);
        update template;
        template = ImportTemplateSelector.selectById(template.Id);
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
            SELECT Row_Number__c, Status__c, Error_Message__c, Gift_Id__c, Several_Matches__c
            FROM Import_Row__c
            WHERE Import_Batch__c = :batch.Id
            ORDER BY Row_Number__c
        ];
    }

    private static String rowErrors() {
        List<String> errors = new List<String>();
        for (Import_Row__c row : rows()) {
            errors.add(row.Row_Number__c + ' ' + row.Status__c + ': ' + row.Error_Message__c);
        }
        return String.join(errors, '; ');
    }

    private static List<List<String>> affiliationColumns(String organizationBy) {
        return new List<List<String>>{
            new List<String>{ 'Person', 'Record.Contact__c' },
            new List<String>{ 'Employer', 'Record.Organization__c', organizationBy },
            new List<String>{ 'Role', 'Record.Role__c' }
        };
    }

    private static Contact person(String last) {
        Contact created = new Contact(FirstName = 'Ana', LastName = last);
        insert created;
        return created;
    }

    private static Account organization(String name) {
        Account created = new Account(Name = name, RecordTypeId = organizationType());
        insert created;
        return created;
    }

    // -------------------------------------------------------------------------------------
    // Insert and lookups (R-IT10, R-IT11)
    // -------------------------------------------------------------------------------------

    @IsTest
    static void insertLoadsRecordsWithLookupsByIdAndByNameAndJournalsThem() {
        Contact ana = person('Ramirez');
        organization('Rose City');
        given(
            'Affiliation__c',
            ImportObjectLoader.OPERATION_INSERT,
            affiliationColumns('Name'),
            new List<Map<String, String>>{
                new Map<String, String>{
                    'Person' => ana.Id,
                    'Employer' => 'rose city',
                    'Role' => 'Treasurer'
                }
            }
        );

        Test.startTest();
        ImportRowProcessor.Outcome preview = run(true);
        Integer beforeCommit = [SELECT COUNT() FROM Affiliation__c];
        ImportRowProcessor.Outcome committed = run(false);
        Test.stopTest();

        Assert.areEqual(0, beforeCommit, 'The dry run writes nothing.');
        Assert.areEqual(1, preview.created, 'It says the row creates: ' + preview.notes);
        Assert.areEqual(1, committed.created, 'The commit does: ' + rowErrors());
        Affiliation__c loaded = [
            SELECT Id, Contact__c, Organization__c, Role__c
            FROM Affiliation__c
        ];
        Assert.areEqual(ana.Id, loaded.Contact__c, 'The person, named by Id.');
        Assert.isNotNull(loaded.Organization__c, 'The organization, named by its name.');
        Assert.areEqual('Treasurer', loaded.Role__c, 'The role.');
        Assert.areEqual(loaded.Id, rows()[0].Gift_Id__c, 'The row names what it created.');
        Import_Journal__c page = [SELECT Created_Count__c, Entries_JSON__c FROM Import_Journal__c];
        Assert.areEqual(1, page.Created_Count__c, 'An untagged creation is journaled.');
    }

    @IsTest
    static void aLookupThatFindsNobodyRejectsTheRowOrIsLeftEmptyWhenAsked() {
        Contact ana = person('Ramirez');
        given(
            'Affiliation__c',
            ImportObjectLoader.OPERATION_INSERT,
            affiliationColumns('Name'),
            new List<Map<String, String>>{
                new Map<String, String>{
                    'Person' => ana.Id,
                    'Employer' => 'Nobody Inc',
                    'Role' => 'Treasurer'
                }
            }
        );

        Test.startTest();
        ImportRowProcessor.Outcome rejected = run(true);
        String reason = rows()[0].Error_Message__c;
        set(Import_Template__c.Lookup_Not_Found__c, ImportObjectLoader.LOOKUP_LEAVE_EMPTY);
        ImportRowProcessor.Outcome leftEmpty = run(true);
        Test.stopTest();

        Assert.areEqual(1, rejected.rejected, 'Rejected by default.');
        Assert.isTrue(reason.contains('Nobody Inc'), 'Naming the value: ' + reason);
        Assert.areEqual(1, leftEmpty.created, 'Loaded without the lookup when asked.');
        String note = String.format(
            Label.Core_Import_LogLookupLeftEmpty,
            new List<String>{ Affiliation__c.Organization__c.getDescribe().getLabel() }
        );
        Assert.isTrue(leftEmpty.notes.contains(note), 'And said once: ' + leftEmpty.notes);
    }

    @IsTest
    static void aLookupThatFindsSeveralRejectsOrTakesTheMostRecentlyChanged() {
        Contact ana = person('Ramirez');
        organization('Rose City');
        Account newer = organization('Rose City');
        given(
            'Affiliation__c',
            ImportObjectLoader.OPERATION_INSERT,
            affiliationColumns('Name'),
            new List<Map<String, String>>{
                new Map<String, String>{
                    'Person' => ana.Id,
                    'Employer' => 'Rose City',
                    'Role' => 'Treasurer'
                }
            }
        );

        Test.startTest();
        ImportRowProcessor.Outcome rejected = run(true);
        Import_Row__c listed = rows()[0];
        set(Import_Template__c.Several_Matches__c, ImportTemplateService.SEVERAL_MOST_RECENT);
        ImportRowProcessor.Outcome committed = run(false);
        Test.stopTest();

        Assert.areEqual(1, rejected.rejected, 'Two organizations named so: rejected by default.');
        Assert.isTrue(listed.Several_Matches__c, 'And listed.');
        Assert.areEqual(1, committed.created, 'Loaded when asked: ' + rowErrors());
        Assert.areEqual(
            newer.Id,
            [SELECT Organization__c FROM Affiliation__c].Organization__c,
            'To the most recently changed.'
        );
        Assert.isTrue(rows()[0].Several_Matches__c, 'Still listed.');
    }

    @IsTest
    static void aValueItsFieldCannotTakeRejectsTheRowNamingIt() {
        Contact ana = person('Ramirez');
        Account employer = organization('Rose City');
        List<List<String>> columns = affiliationColumns(null);
        columns.add(new List<String>{ 'Since', 'Record.Start_Date__c' });
        given(
            'Affiliation__c',
            ImportObjectLoader.OPERATION_INSERT,
            columns,
            new List<Map<String, String>>{
                new Map<String, String>{
                    'Person' => ana.Id,
                    'Employer' => employer.Id,
                    'Role' => 'Treasurer',
                    'Since' => 'the spring'
                }
            }
        );

        Test.startTest();
        ImportRowProcessor.Outcome preview = run(true);
        Test.stopTest();

        Assert.areEqual(1, preview.rejected, 'Rejected in the dry run.');
        Assert.isTrue(
            rows()[0].Error_Message__c.contains('the spring'),
            'Naming the value: ' + rows()[0].Error_Message__c
        );
    }

    // -------------------------------------------------------------------------------------
    // Update by record Id
    // -------------------------------------------------------------------------------------

    @IsTest
    static void updateByIdChangesWhatDiffersAndRefusesAnIdItCannotFind() {
        Contact ana = person('Ramirez');
        Account employer = organization('Rose City');
        Affiliation__c existing = new Affiliation__c(
            Contact__c = ana.Id,
            Organization__c = employer.Id,
            Role__c = 'Volunteer'
        );
        Affiliation__c unchanged = new Affiliation__c(
            Contact__c = person('Okafor').Id,
            Organization__c = employer.Id,
            Role__c = 'Chair'
        );
        insert new List<Affiliation__c>{ existing, unchanged };
        given(
            'Affiliation__c',
            ImportObjectLoader.OPERATION_UPDATE,
            new List<List<String>>{
                new List<String>{ 'Id', 'Record.Id' },
                new List<String>{ 'Role', 'Record.Role__c' }
            },
            new List<Map<String, String>>{
                new Map<String, String>{ 'Id' => existing.Id, 'Role' => 'Treasurer' },
                new Map<String, String>{ 'Id' => unchanged.Id, 'Role' => 'Chair' },
                new Map<String, String>{ 'Id' => employer.Id, 'Role' => 'Chair' },
                new Map<String, String>{
                    'Id' => String.valueOf(existing.Id).left(15),
                    'Role' => 'X'
                }
            }
        );

        Test.startTest();
        ImportRowProcessor.Outcome preview = run(true);
        ImportRowProcessor.Outcome committed = run(false);
        Test.stopTest();

        Assert.areEqual(preview.updated, committed.updated, 'The dry run counted the commit.');
        Assert.areEqual(1, committed.updated, 'One role changed: ' + rowErrors());
        Assert.areEqual(1, committed.matched, 'One already held the value.');
        Assert.areEqual(2, committed.rejected, 'An Id of another object, and a repeat.');
        List<Import_Row__c> staged = rows();
        Assert.isTrue(
            staged[2].Error_Message__c.contains(String.valueOf(employer.Id).left(15)),
            'The Id of an organization is not an affiliation: ' + staged[2].Error_Message__c
        );
        Assert.areEqual(
            Label.Core_Import_ErrorRecordRepeated,
            staged[3].Error_Message__c,
            'The same record in its short form is a repeat.'
        );
        Assert.areEqual(
            'Treasurer',
            [SELECT Role__c FROM Affiliation__c WHERE Id = :existing.Id].Role__c,
            'Changed.'
        );
        Import_Journal__c page = [SELECT Entries_JSON__c FROM Import_Journal__c];
        Assert.isTrue(page.Entries_JSON__c.contains('Volunteer'), 'The old role is journaled.');
    }

    @IsTest
    static void updateByIdOfARecordThatIsGoneIsRejected() {
        Account employer = organization('Rose City');
        Affiliation__c gone = new Affiliation__c(
            Contact__c = person('Ramirez').Id,
            Organization__c = employer.Id,
            Role__c = 'Volunteer'
        );
        insert gone;
        delete gone;
        given(
            'Affiliation__c',
            ImportObjectLoader.OPERATION_UPDATE,
            new List<List<String>>{
                new List<String>{ 'Id', 'Record.Id' },
                new List<String>{ 'Role', 'Record.Role__c' }
            },
            new List<Map<String, String>>{
                new Map<String, String>{ 'Id' => gone.Id, 'Role' => 'Treasurer' }
            }
        );

        Test.startTest();
        run(true);
        Test.stopTest();

        Assert.areEqual(Label.Core_Import_ErrorRecordNotFound, rows()[0].Error_Message__c, 'Why.');
    }

    // -------------------------------------------------------------------------------------
    // Upsert by external ID
    // -------------------------------------------------------------------------------------

    private static void givenDismissals(List<Map<String, String>> values) {
        given(
            'Duplicate_Dismissal__c',
            ImportObjectLoader.OPERATION_UPSERT,
            new List<List<String>>{
                new List<String>{ 'Key', 'Record.Pair_Key__c' },
                new List<String>{ 'Reason', 'Record.Reason__c' }
            },
            values
        );
        set(Import_Template__c.Load_Match_Field__c, 'Pair_Key__c');
    }

    @IsTest
    static void upsertUpdatesWhatItFindsCreatesTheRestAndRefusesARepeat() {
        insert new Duplicate_Dismissal__c(Pair_Key__c = 'k1', Reason__c = 'old');
        givenDismissals(
            new List<Map<String, String>>{
                new Map<String, String>{ 'Key' => 'k1', 'Reason' => 'new' },
                new Map<String, String>{ 'Key' => 'k2', 'Reason' => 'first' },
                new Map<String, String>{ 'Key' => 'K2', 'Reason' => 'again' },
                new Map<String, String>{ 'Key' => '', 'Reason' => 'no key' }
            }
        );

        Test.startTest();
        Import_Batch__c preview = runInChunks(true, 2);
        Import_Batch__c committed = runInChunks(false, 2);
        Test.stopTest();

        Assert.areEqual(1, committed.Rows_Updated__c, 'k1 updated: ' + rowErrors());
        Assert.areEqual(1, committed.Rows_Created__c, 'k2 created.');
        Assert.areEqual(2, committed.Rows_Rejected__c, 'The repeat in the next chunk, and no key.');
        Assert.areEqual(preview.Rows_Created__c, committed.Rows_Created__c, 'As previewed.');
        Assert.areEqual(preview.Rows_Rejected__c, committed.Rows_Rejected__c, 'As previewed.');
        Assert.areEqual(
            Label.Core_Import_ErrorRecordRepeated,
            rows()[2].Error_Message__c,
            'A repeat across chunks is rejected as in one chunk.'
        );
        Assert.areEqual(
            'new',
            [SELECT Reason__c FROM Duplicate_Dismissal__c WHERE Pair_Key__c = 'k1'].Reason__c,
            'Updated.'
        );
        Assert.areEqual(2, [SELECT COUNT() FROM Duplicate_Dismissal__c], 'One created.');
    }

    @IsTest
    static void upsertWithoutItsFieldIsRefusedBeforeAnyRow() {
        given(
            'Duplicate_Dismissal__c',
            ImportObjectLoader.OPERATION_UPSERT,
            new List<List<String>>{ new List<String>{ 'Reason', 'Record.Reason__c' } },
            new List<Map<String, String>>{ new Map<String, String>{ 'Reason' => 'x' } }
        );

        Test.startTest();
        String none = ImportObjectLoader.refusal(
            template,
            ImportMapping.parse(template.Column_Mapping_JSON__c)
        );
        set(Import_Template__c.Load_Match_Field__c, 'Reason__c');
        String notKey = ImportObjectLoader.refusal(
            template,
            ImportMapping.parse(template.Column_Mapping_JSON__c)
        );
        set(Import_Template__c.Load_Match_Field__c, 'Pair_Key__c');
        String unmapped = ImportObjectLoader.refusal(
            template,
            ImportMapping.parse(template.Column_Mapping_JSON__c)
        );
        Test.stopTest();

        Assert.areEqual(Label.Core_Import_ErrorKeyFieldRequired, none, 'The field is needed.');
        Assert.isTrue(notKey.contains('Reason__c'), 'A field that is no external ID is named.');
        Assert.isTrue(
            unmapped.contains(Duplicate_Dismissal__c.Pair_Key__c.getDescribe().getLabel()),
            'And a column must feed it: ' + unmapped
        );
    }

    @IsTest
    static void twoHundredUpsertRowsInOneChunkStayBulk() {
        List<Duplicate_Dismissal__c> existing = new List<Duplicate_Dismissal__c>();
        List<Map<String, String>> values = new List<Map<String, String>>();
        for (Integer i = 0; i < 200; i++) {
            if (Math.mod(i, 2) == 0) {
                existing.add(new Duplicate_Dismissal__c(Pair_Key__c = 'p' + i, Reason__c = 'old'));
            }
            values.add(new Map<String, String>{ 'Key' => 'p' + i, 'Reason' => 'new' });
        }
        insert existing;
        givenDismissals(values);

        Test.startTest();
        Integer before = Limits.getQueries();
        ImportRowProcessor.Outcome committed = run(false);
        Integer used = Limits.getQueries() - before;
        Test.stopTest();

        Assert.areEqual(100, committed.updated, 'Half updated: ' + committed.notes);
        Assert.areEqual(100, committed.created, 'Half created.');
        Assert.areEqual(
            200,
            [SELECT COUNT() FROM Duplicate_Dismissal__c WHERE Reason__c = 'new'],
            'All.'
        );
        Assert.isTrue(used < 20, 'A handful of queries for the chunk: ' + used);
    }

    // -------------------------------------------------------------------------------------
    // What is never written (R-IT12)
    // -------------------------------------------------------------------------------------

    @IsTest
    static void aProtectedFieldIsNamedOnceAndNeverWritten() {
        Account employer = organization('Rose City');
        given(
            'Account',
            ImportObjectLoader.OPERATION_UPDATE,
            new List<List<String>>{
                new List<String>{ 'Id', 'Record.Id' },
                new List<String>{ 'Name', 'Record.Name' },
                new List<String>{ 'Greeting', 'Record.Household_Formal_Greeting__c' }
            },
            new List<Map<String, String>>{
                new Map<String, String>{
                    'Id' => employer.Id,
                    'Name' => 'Rose City Rotary',
                    'Greeting' => 'Dear friends'
                }
            }
        );

        Test.startTest();
        ImportRowProcessor.Outcome committed = run(false);
        Test.stopTest();

        Account after = [
            SELECT Name, Household_Formal_Greeting__c
            FROM Account
            WHERE Id = :employer.Id
        ];
        Assert.areEqual('Rose City Rotary', after.Name, 'An organization name loads.');
        Assert.areNotEqual('Dear friends', after.Household_Formal_Greeting__c, 'A greeting never.');
        String note = String.format(
            Label.Core_Import_LogFieldProtected,
            new List<String>{ Account.Household_Formal_Greeting__c.getDescribe().getLabel() }
        );
        Assert.isTrue(committed.notes.contains(note), 'Said once: ' + committed.notes);
    }

    @IsTest
    static void aHouseholdsNameIsNeverLoaded() {
        Contact ana = new Contact(FirstName = 'Ana', LastName = 'Ramirez');
        insert ana;
        Id householdId = [SELECT AccountId FROM Contact WHERE Id = :ana.Id].AccountId;
        if (householdId == null) {
            // No household automation in this org shape: nothing to protect.
            Assert.isNull(householdId, 'No household.');
            return;
        }
        String before = [SELECT Name FROM Account WHERE Id = :householdId].Name;
        given(
            'Account',
            ImportObjectLoader.OPERATION_UPDATE,
            new List<List<String>>{
                new List<String>{ 'Id', 'Record.Id' },
                new List<String>{ 'Name', 'Record.Name' }
            },
            new List<Map<String, String>>{
                new Map<String, String>{ 'Id' => householdId, 'Name' => 'Renamed' }
            }
        );

        Test.startTest();
        ImportRowProcessor.Outcome committed = run(false);
        Test.stopTest();

        Assert.areEqual(before, [SELECT Name FROM Account WHERE Id = :householdId].Name, 'Kept.');
        Assert.areEqual(1, committed.matched, 'Nothing else to change: ' + committed.notes);
    }

    @IsTest
    static void theBookkeepingObjectsCannotBeChosen() {
        Test.startTest();
        ImportException refused;
        try {
            ImportTemplateService.createObjectTemplate('Batches', 'Import_Batch__c');
        } catch (ImportException e) {
            refused = e;
        }
        List<ImportMapping.Target> objects = ImportObjectLoader.loadableObjects();
        Test.stopTest();

        Assert.isNotNull(refused, 'The package own records are never loaded.');
        Set<String> names = new Set<String>();
        for (ImportMapping.Target each : objects) {
            names.add(each.value.toLowerCase());
        }
        String affiliation = Affiliation__c.SObjectType.getDescribe().getName().toLowerCase();
        String batches = Import_Batch__c.SObjectType.getDescribe().getName().toLowerCase();
        Assert.isTrue(names.contains(affiliation), 'Affiliations are offered.');
        Assert.isFalse(names.contains(batches), 'Import batches are not.');
    }

    // -------------------------------------------------------------------------------------
    // Access, undo, the wizard's helpers
    // -------------------------------------------------------------------------------------

    @IsTest
    static void aUserWhoCannotCreateTheObjectIsRefusedOnEveryRow() {
        Contact ana = person('Ramirez');
        Account employer = organization('Rose City');
        given(
            'Affiliation__c',
            ImportObjectLoader.OPERATION_INSERT,
            affiliationColumns(null),
            new List<Map<String, String>>{
                new Map<String, String>{
                    'Person' => ana.Id,
                    'Employer' => employer.Id,
                    'Role' => 'Treasurer'
                }
            }
        );
        User minimum = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1]
            .Id,
            LastName = 'Noaccess',
            Email = 'noaccess@barncrm.test.invalid',
            Username = 'noaccess' + Datetime.now().getTime() + '@barncrm.test.invalid',
            Alias = 'noacc',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert minimum;
        }

        Test.startTest();
        ImportRowProcessor.Outcome outcome;
        System.runAs(minimum) {
            outcome = run(false);
        }
        Test.stopTest();

        Assert.areEqual(1, outcome.rejected, 'Refused.');
        Assert.areEqual(
            String.format(
                Label.Core_Import_ErrorObjectNoAccess,
                new List<String>{ Affiliation__c.SObjectType.getDescribe().getLabelPlural() }
            ),
            rows()[0].Error_Message__c,
            'Saying which access is missing.'
        );
        Assert.areEqual(0, [SELECT COUNT() FROM Affiliation__c], 'Nothing loaded.');
    }

    @IsTest
    static void undoRemovesWhatTheLoadCreatedAndPutsBackWhatItChanged() {
        ImportEntityProcessors.noneForTest = true;
        insert new Duplicate_Dismissal__c(Pair_Key__c = 'k1', Reason__c = 'old');
        givenDismissals(
            new List<Map<String, String>>{
                new Map<String, String>{ 'Key' => 'k1', 'Reason' => 'new' },
                new Map<String, String>{ 'Key' => 'k2', 'Reason' => 'first' }
            }
        );
        runInChunks(false, 200);
        update new Import_Batch__c(
            Id = batch.Id,
            Is_Dry_Run__c = false,
            Started_At__c = Datetime.now().addMinutes(-5),
            Completed_At__c = Datetime.now().addMinutes(1)
        );
        ImportUndoService.Preview preview = ImportUndoService.preview(batch.Id);
        // Latched and queued outside the test block, so the queued job never runs.
        ImportUndoService.start(batch.Id, preview.total);

        Test.startTest();
        for (String pass : ImportUndoBatch.passes()) {
            ImportUndoBatch job = new ImportUndoBatch(batch.Id, preview.total, pass, 0, false);
            List<SObject> scope = new List<SObject>();
            Database.QueryLocatorIterator records = job.start(null).iterator();
            while (records.hasNext()) {
                scope.add(records.next());
            }
            if (!scope.isEmpty()) {
                job.execute(null, scope);
            }
        }
        Test.stopTest();

        Assert.areEqual(1, preview.total, 'The one created record is counted.');
        Assert.areEqual(1, preview.updates, 'And the one change.');
        Assert.areEqual(
            Duplicate_Dismissal__c.SObjectType.getDescribe().getLabelPlural(),
            preview.others[0].label,
            'Under the loaded object label.'
        );
        List<Duplicate_Dismissal__c> left = [
            SELECT Pair_Key__c, Reason__c
            FROM Duplicate_Dismissal__c
        ];
        Assert.areEqual(1, left.size(), 'The created one is gone.');
        Assert.areEqual('old', left[0].Reason__c, 'The changed one is put back.');
    }

    @IsTest
    static void aHeadingThatIsAFieldIsSuggestedAndOthersAreNot() {
        Test.startTest();
        ImportMapping suggested = ImportObjectLoader.suggestMapping(
            Affiliation__c.SObjectType,
            new List<String>{ 'Role', 'start date', 'Record Id', 'Favourite colour', 'role' }
        );
        Test.stopTest();

        Assert.areEqual(
            'Record.' + Affiliation__c.Role__c.getDescribe().getName(),
            suggested.columns[0].target,
            'By label.'
        );
        Assert.areEqual(
            'Record.' + Affiliation__c.Start_Date__c.getDescribe().getName(),
            suggested.columns[1].target,
            'Ignoring case and spaces.'
        );
        Assert.areEqual('Record.Id', suggested.columns[2].target, 'The record Id.');
        Assert.areEqual(ImportMapping.TARGET_IGNORE, suggested.columns[3].target, 'Never a guess.');
        Assert.areEqual(ImportMapping.TARGET_IGNORE, suggested.columns[4].target, 'Nor twice.');
    }

    @IsTest
    static void theFieldPickerOffersWritableFieldsAndHowALookupFindsItsParent() {
        Import_Template__c created = ImportTemplateService.createObjectTemplate(
            'Board members',
            'Affiliation__c'
        );
        ImportController.permissionOverride = true;

        Test.startTest();
        List<ImportController.FieldChoice> fields = ImportController.getObjectFields(created.Id);
        Test.stopTest();

        Assert.areEqual('Record.Id', fields[0].value, 'The record Id first.');
        ImportController.FieldChoice organization;
        Set<String> values = new Set<String>();
        for (ImportController.FieldChoice field : fields) {
            values.add(field.value.toLowerCase());
            if (field.value == 'Record.' + Affiliation__c.Organization__c.getDescribe().getName()) {
                organization = field;
            }
        }
        Assert.isNotNull(organization, 'The organization lookup is offered.');
        Assert.isTrue(organization.isLookup, 'As a lookup.');
        Assert.areEqual('Id', organization.lookupFields[0].value, 'Found by Id first.');
        Assert.areEqual('Name', organization.lookupFields[1].value, 'Or by the organization name.');
        Assert.isFalse(values.contains('record.createddate'), 'Never a field Salesforce keeps.');
    }

    @IsTest
    static void aPersonAccountIsNamedByIdWhereTheOrgHasThem() {
        if (!OrgShapeDetector.detect().hasPersonAccounts) {
            // Platform-only shape (ADR-0013): no person accounts to point at.
            Assert.isFalse(OrgShapeDetector.detect().hasPersonAccounts, 'No person accounts.');
            return;
        }
        Id personType = new List<Id>(OrgShapeDetector.detect().personAccountRecordTypeIds)[0];
        SObject personAccount = Account.SObjectType.newSObject();
        personAccount.put('RecordTypeId', personType);
        personAccount.put('LastName', 'Ramirez');
        insert personAccount;
        Account employer = organization('Rose City');
        given(
            'Affiliation__c',
            ImportObjectLoader.OPERATION_INSERT,
            new List<List<String>>{
                new List<String>{ 'Person', 'Record.Person_Account__c' },
                new List<String>{ 'Employer', 'Record.Organization__c' }
            },
            new List<Map<String, String>>{
                new Map<String, String>{ 'Person' => personAccount.Id, 'Employer' => employer.Id }
            }
        );

        Test.startTest();
        ImportRowProcessor.Outcome committed = run(false);
        Test.stopTest();

        Assert.areEqual(1, committed.created, 'Loaded: ' + rowErrors());
        Assert.areEqual(
            personAccount.Id,
            [SELECT Person_Account__c FROM Affiliation__c].Person_Account__c,
            'Through the person account.'
        );
    }
}

/**
 * C-32: the affiliation on a row is Core's (canonical model R-IR8, R-AF5). A row's first person
 * is connected to its organization, a current affiliation between them is updated rather than
 * repeated, each creation is journaled because an affiliation carries no batch tag (R-IJ3), and
 * undo removes what the import created (R-IB9).
 */
@IsTest
private class ImportAffiliationTest {
    private static Import_Template__c template;
    private static Import_Batch__c batch;

    @TestSetup
    static void setUp() {
        TestDataFactory.defaultSettings();
    }

    private static String mapping() {
        ImportMapping mapping = ImportMapping.parse(ImportTestDataFactory.donorMapping());
        mapping.columns.add(new ImportMapping.Column('Role', 'Affiliation.Role__c'));
        mapping.columns.add(new ImportMapping.Column('Primary', 'Affiliation.Is_Primary__c'));
        return mapping.serialize();
    }

    private static Map<String, String> row(String first, String organization, String role) {
        Map<String, String> row = ImportTestDataFactory.donorRow(
            first,
            'Ramirez',
            first.toLowerCase() + '@example.org',
            organization
        );
        row.put('Role', role);
        row.put('Primary', 'yes');
        return row;
    }

    private static void given(List<Map<String, String>> values) {
        template = ImportTestDataFactory.template(mapping(), ImportTemplateService.RULE_EMAIL);
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

    /** Commits through the batch job's own finish, so the batch reads as committed. */
    private static void commitBatch() {
        // Core's undo is tested on its own: a module installed in the test org is not asked.
        ImportEntityProcessors.noneForTest = true;
        ImportBatchService.beginPass(batch.Id);
        ImportProcessorBatch job = new ImportProcessorBatch(batch.Id, false);
        job.execute(null, ImportTestDataFactory.reload(batch.Id));
        job.finish(null);
        // What starting the commit would have stamped (R-IB7), with a finish a minute ahead so
        // the commit's own follow-on work is not mistaken for an edit since (R-IB9).
        update new Import_Batch__c(
            Id = batch.Id,
            Is_Dry_Run__c = false,
            Started_At__c = Datetime.now().addMinutes(-5),
            Completed_At__c = Datetime.now().addMinutes(1)
        );
    }

    private static String rowErrors() {
        List<String> errors = new List<String>();
        for (Import_Row__c staged : ImportTestDataFactory.reload(batch.Id)) {
            errors.add(staged.Status__c + ': ' + staged.Error_Message__c);
        }
        return String.join(errors, '; ');
    }

    @IsTest
    static void aRowConnectsItsPersonToItsOrganization() {
        given(new List<Map<String, String>>{ row('Ana', 'Rose City', 'Treasurer') });

        Test.startTest();
        ImportRowProcessor.Outcome preview = run(true);
        Integer beforeCommit = [SELECT COUNT() FROM Affiliation__c];
        ImportRowProcessor.Outcome committed = run(false);
        Test.stopTest();

        Assert.areEqual(0, beforeCommit, 'The dry run writes nothing.');
        Assert.areEqual(1, preview.created, 'It counts the row as creating.');
        Assert.areEqual(1, committed.created, 'So does the commit: ' + rowErrors());
        Affiliation__c affiliation = [
            SELECT Contact__c, Organization__c, Role__c, Is_Primary__c
            FROM Affiliation__c
        ];
        Import_Row__c staged = ImportTestDataFactory.reload(batch.Id)[0];
        Assert.areEqual(staged.Contact_1__c, affiliation.Contact__c, 'The row person.');
        Assert.areEqual(
            staged.Organization__c,
            affiliation.Organization__c,
            'The row organization.'
        );
        Assert.areEqual('Treasurer', affiliation.Role__c, 'With the row role.');
        Assert.isTrue(affiliation.Is_Primary__c, 'And the primary flag.');
        Import_Journal__c page = [SELECT Created_Count__c, Entries_JSON__c FROM Import_Journal__c];
        Assert.areEqual(1, page.Created_Count__c, 'The creation is journaled: no tag holds it.');
        Assert.isTrue(page.Entries_JSON__c.contains(affiliation.Id), 'By its identifier.');
    }

    @IsTest
    static void aCurrentAffiliationIsUpdatedNotRepeatedAndTheChangeJournaled() {
        Account organization = new Account(
            Name = 'Rose City',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Organization')
                .getRecordTypeId()
        );
        insert organization;
        Contact ana = new Contact(
            FirstName = 'Ana',
            LastName = 'Ramirez',
            Email = 'ana@example.org',
            MailingCity = 'Portland'
        );
        insert ana;
        Affiliation__c existing = new Affiliation__c(
            Contact__c = ana.Id,
            Organization__c = organization.Id,
            Role__c = 'Volunteer',
            Is_Primary__c = true
        );
        insert existing;
        given(new List<Map<String, String>>{ row('Ana', 'Rose City', 'Treasurer') });

        Test.startTest();
        ImportRowProcessor.Outcome preview = run(true);
        ImportRowProcessor.Outcome committed = run(false);
        Test.stopTest();

        Assert.areEqual(1, preview.updated, 'The dry run sees the change: ' + preview.notes);
        Assert.areEqual(1, committed.updated, 'The commit makes it: ' + rowErrors());
        Assert.areEqual(1, [SELECT COUNT() FROM Affiliation__c], 'Not a second affiliation.');
        Assert.areEqual(
            'Treasurer',
            [SELECT Role__c FROM Affiliation__c WHERE Id = :existing.Id].Role__c,
            'The role is the row role.'
        );
        Import_Journal__c page = [SELECT Created_Count__c, Entries_JSON__c FROM Import_Journal__c];
        Assert.isNull(page.Created_Count__c, 'Nothing created.');
        Assert.isTrue(page.Entries_JSON__c.contains('Volunteer'), 'The old role is journaled.');
    }

    @IsTest
    static void aRowWithNoOrganizationHasNoAffiliationAndIsNotRejected() {
        given(new List<Map<String, String>>{ row('Ana', null, 'Treasurer') });

        Test.startTest();
        ImportRowProcessor.Outcome committed = run(false);
        Test.stopTest();

        Assert.areEqual(1, committed.created, 'The person still loads: ' + rowErrors());
        Assert.areEqual(0, [SELECT COUNT() FROM Affiliation__c], 'No affiliation.');
        Assert.isTrue(
            committed.notes.contains(Label.Core_Import_LogAffiliationLeftOut),
            'The run log says so once: ' + committed.notes
        );
    }

    @IsTest
    static void twoHundredRowsMakeTwoHundredAffiliationsInOneChunk() {
        List<Map<String, String>> values = new List<Map<String, String>>();
        for (Integer i = 0; i < 200; i++) {
            values.add(row('P' + i, 'Employer ' + Math.mod(i, 10), 'Staff'));
        }
        given(values);

        Test.startTest();
        Integer before = Limits.getQueries();
        ImportRowProcessor.Outcome committed = run(false);
        Integer used = Limits.getQueries() - before;
        Test.stopTest();

        Assert.areEqual(200, committed.created, 'Every row loaded: ' + rowErrors());
        Assert.areEqual(200, [SELECT COUNT() FROM Affiliation__c], 'One affiliation a row.');
        Assert.areEqual(
            10,
            [SELECT COUNT() FROM Account WHERE Name LIKE 'Employer %'],
            'Ten employers.'
        );
        Decimal journaled = (Decimal) [SELECT SUM(Created_Count__c) total FROM Import_Journal__c][0]
            .get('total');
        Assert.areEqual(200, journaled, 'Each creation journaled, on pages of at most 200.');
        Assert.isTrue(used < 100, 'Bulk, not one query a row: ' + used);
    }

    @IsTest
    static void twoRowsNamingOneNewAffiliationShareIt() {
        given(
            new List<Map<String, String>>{
                row('Ana', 'Rose City', 'Treasurer'),
                row('Ana', 'Rose City', 'Treasurer')
            }
        );

        Test.startTest();
        ImportRowProcessor.Outcome preview = run(true);
        ImportRowProcessor.Outcome committed = run(false);
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM Affiliation__c], 'One affiliation.');
        Assert.areEqual(preview.created, committed.created, 'Counted as the commit did it.');
    }

    @IsTest
    static void undoRemovesTheAffiliationsTheImportCreated() {
        given(new List<Map<String, String>>{ row('Ana', 'Rose City', 'Treasurer') });
        commitBatch();
        Assert.areEqual(1, [SELECT COUNT() FROM Affiliation__c], 'Precondition: one affiliation.');

        ImportUndoService.Preview preview = ImportUndoService.preview(batch.Id);
        // Latched and queued outside the test block, so the queued job never runs: the passes
        // below are the undo.
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

        Boolean counted = false;
        for (ImportUndoService.TaggedCount other : preview.others) {
            if (other.objectName == Affiliation__c.SObjectType.getDescribe().getName()) {
                counted = other.count == 1;
            }
        }
        Assert.isTrue(counted, 'The preview counts the affiliation: ' + preview.others);
        Assert.areEqual(0, preview.updates, 'A creation is not an update to put back.');
        Assert.areEqual(0, [SELECT COUNT() FROM Affiliation__c], 'The affiliation is gone.');
        Assert.areEqual(0, [SELECT COUNT() FROM Contact], 'And the person it named.');
    }

    @IsTest
    static void anAdministratorOnTheMinimumProfileLoadsAffiliations() {
        given(new List<Map<String, String>>{ row('Ana', 'Rose City', 'Treasurer') });
        User importer = importer();

        Test.startTest();
        ImportRowProcessor.Outcome committed;
        System.runAs(importer) {
            committed = run(false);
        }
        Test.stopTest();

        Assert.isFalse(
            committed.notes.contains(Label.Core_Import_LogAffiliationNoAccess),
            'BarnCRM Admin grants what an affiliation needs: ' + committed.notes
        );
        Assert.areEqual(1, [SELECT COUNT() FROM Affiliation__c], 'Loaded: ' + rowErrors());
    }

    @IsTest
    static void aPersonAccountIsAffiliatedThroughItsAccount() {
        if (!OrgShapeDetector.detect().hasPersonAccounts) {
            // Platform-only shape (ADR-0013): no person accounts to affiliate.
            Assert.isFalse(OrgShapeDetector.detect().hasPersonAccounts, 'No person accounts.');
            return;
        }
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
        given(new List<Map<String, String>>{ row('Ana', 'Rose City', 'Treasurer') });
        template.Person_Mode__c = ImportTemplateService.PERSON_MODE_PERSON_ACCOUNTS;
        update template;

        Test.startTest();
        ImportRowProcessor.Outcome committed = run(false);
        Test.stopTest();

        Assert.areEqual(1, committed.created, 'Loaded: ' + rowErrors());
        Affiliation__c affiliation = [SELECT Contact__c, Person_Account__c FROM Affiliation__c];
        Assert.isNull(affiliation.Contact__c, 'Not through a contact.');
        Assert.areEqual(
            ImportTestDataFactory.reload(batch.Id)[0].Person_1_Account__c,
            affiliation.Person_Account__c,
            'Through the person account.'
        );
    }

    private static User importer() {
        Profile minimum = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Minimum Access - Salesforce'
            LIMIT 1
        ];
        User person = new User(
            ProfileId = minimum.Id,
            LastName = 'Affiliations',
            Email = 'affiliations@barncrm.test.invalid',
            Username = 'affiliations' + Datetime.now().getTime() + '@barncrm.test.invalid',
            Alias = 'affimp',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert person;
            insert new PermissionSetAssignment(
                AssigneeId = person.Id,
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'Barn_Admin']
                .Id
            );
        }
        return person;
    }
}

/**
 * Importing people stored as person accounts: a row written in contact terms (Email,
 * MailingStreet, HasOptedOutOfEmail) lands in the account's person fields, and the next load
 * of the same file finds the people it made by the same key (R-IB12).
 *
 * These tests need an org with person accounts, and every one returns early, on purpose,
 * where the org has none: the Platform-only shape Core must also run on (ADR-0013) has no
 * person fields to write or read, so there is nothing true to assert there. The person
 * fields are named only as text and read through dynamic SOQL, so this class compiles on
 * that shape too (plan Section 4.2).
 */
@IsTest
private class ImportPersonAccountTest {
    private static Import_Template__c template;
    private static Import_Batch__c batch;

    private static Boolean orgHasPersonAccounts() {
        return OrgShapeDetector.detect().hasPersonAccounts &&
            ImportMatcher.accountHasField('PersonEmail');
    }

    private static String mapping() {
        ImportMapping mapping = ImportMapping.parse(ImportTestDataFactory.donorMapping());
        mapping.columns.add(new ImportMapping.Column('Street', 'Contact1.MailingStreet'));
        mapping.columns.add(new ImportMapping.Column('Zip', 'Contact1.MailingPostalCode'));
        mapping.columns.add(
            new ImportMapping.Column('Email Opt Out', 'Contact1.HasOptedOutOfEmail')
        );
        mapping.columns.add(new ImportMapping.Column('Do Not Call', 'Contact1.DoNotCall'));
        mapping.columns.add(new ImportMapping.Column('Birthdate', 'Contact1.Birthdate'));
        mapping.columns.add(new ImportMapping.Column('Title', 'Contact1.Title'));
        return mapping.serialize();
    }

    private static Map<String, String> anasRow(String title) {
        Map<String, String> row = ImportTestDataFactory.donorRow(
            'Ana',
            'Ramirez',
            'ana@example.org',
            null
        );
        row.put('Street', '12 Alder Street');
        row.put('Zip', '97201');
        row.put('Email Opt Out', 'Yes');
        row.put('Do Not Call', 'Yes');
        row.put('Birthdate', '1980-04-02');
        row.put('Title', title);
        return row;
    }

    private static void given(String rule, Map<String, String> row) {
        template = ImportTestDataFactory.template(mapping(), rule);
        template.Person_Mode__c = ImportTemplateService.PERSON_MODE_PERSON_ACCOUNTS;
        update template;
        batch = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(batch, new List<Map<String, String>>{ row });
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

    private static List<SObject> people() {
        Set<Id> personTypes = OrgShapeDetector.detect().personAccountRecordTypeIds;
        return Database.queryWithBinds(
            'SELECT Id, PersonEmail, PersonMailingStreet, PersonMailingCity, ' +
                'PersonMailingPostalCode, PersonHasOptedOutOfEmail, PersonDoNotCall, ' +
                'PersonBirthdate, PersonTitle FROM Account WHERE RecordTypeId IN :personTypes',
            new Map<String, Object>{ 'personTypes' => personTypes },
            AccessLevel.SYSTEM_MODE
        );
    }

    @IsTest
    static void aPersonAccountGetsTheEmailAddressAndOptOuts() {
        if (!orgHasPersonAccounts()) {
            // Platform-only shape (ADR-0013): no person fields exist to be written.
            return;
        }
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
        given(ImportTemplateService.RULE_EMAIL, anasRow('Treasurer'));

        Test.startTest();
        ImportRowProcessor.Outcome outcome = run(false);
        Test.stopTest();

        Assert.areEqual(1, outcome.created, 'The row created a person: ' + outcome.notes);
        List<SObject> people = people();
        Assert.areEqual(1, people.size(), 'One person account.');
        SObject ana = people[0];
        Assert.areEqual('ana@example.org', ana.get('PersonEmail'), 'The email stuck.');
        Assert.areEqual('12 Alder Street', ana.get('PersonMailingStreet'), 'So did the street.');
        Assert.areEqual('Portland', ana.get('PersonMailingCity'), 'The city.');
        Assert.areEqual('97201', ana.get('PersonMailingPostalCode'), 'The postal code.');
        Assert.areEqual(true, ana.get('PersonHasOptedOutOfEmail'), 'The email opt-out.');
        Assert.areEqual(true, ana.get('PersonDoNotCall'), 'Do Not Call.');
        Assert.areEqual(Date.newInstance(1980, 4, 2), ana.get('PersonBirthdate'), 'Birthdate.');
        Assert.areEqual('Treasurer', ana.get('PersonTitle'), 'And the title.');
        for (String note : outcome.notes) {
            Assert.isFalse(
                note.contains('which this org does not have'),
                'No contact attribute was reported unknown to the account: ' + note
            );
        }
    }

    @IsTest
    static void loadingTheFileAgainMatchesThePersonByEmail() {
        if (!orgHasPersonAccounts()) {
            // Platform-only shape (ADR-0013): no person accounts to match.
            return;
        }
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
        given(ImportTemplateService.RULE_EMAIL, anasRow('Treasurer'));
        run(false);
        Id first = people()[0].Id;

        given(ImportTemplateService.RULE_EMAIL, anasRow('Board Chair'));
        Test.startTest();
        ImportRowProcessor.Outcome preview = run(true);
        ImportRowProcessor.Outcome outcome = run(false);
        Test.stopTest();

        Assert.areEqual(0, preview.created, 'The dry run finds her rather than creating her.');
        Assert.areEqual(1, preview.updated, 'And says the new title would update her.');
        Assert.areEqual(0, outcome.created, 'So does the commit.');
        Assert.areEqual(1, outcome.updated, 'Which updates her.');
        List<SObject> people = people();
        Assert.areEqual(1, people.size(), 'Still one person account.');
        Assert.areEqual('Board Chair', people[0].get('PersonTitle'), 'With the new title.');
        Assert.areEqual(
            first,
            ImportTestDataFactory.reload(batch.Id)[0].Person_1_Account__c,
            'The row points at the person the first load made.'
        );
    }

    @IsTest
    static void loadingTheFileAgainMatchesThePersonByNameAndPostalCode() {
        if (!orgHasPersonAccounts()) {
            // Platform-only shape (ADR-0013): no person accounts to match.
            return;
        }
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
        given(ImportTemplateService.RULE_NAME_POSTAL, anasRow('Treasurer'));
        run(false);

        given(ImportTemplateService.RULE_NAME_POSTAL, anasRow('Treasurer'));
        Test.startTest();
        ImportRowProcessor.Outcome outcome = run(false);
        Test.stopTest();

        Assert.areEqual(0, outcome.created, 'The person made by the first load is found.');
        Assert.areEqual(1, people().size(), 'Still one person account.');
    }

    /**
     * The dry run remembers a person account it would create, because the commit now writes
     * the email the matcher reads: a later chunk counts them once (R-IB12).
     */
    @IsTest
    static void aDryRunRemembersAPersonAccountItWouldCreate() {
        if (!orgHasPersonAccounts()) {
            // Platform-only shape (ADR-0013): no person account would be created.
            return;
        }
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
        given(ImportTemplateService.RULE_EMAIL, anasRow('Treasurer'));

        Test.startTest();
        run(true);
        Test.stopTest();

        // Read in system mode: the key is the package's own bookkeeping, never shown, and
        // the running user need not be granted it.
        List<Import_Row__c> rows = Database.queryWithBinds(
            'SELECT Person_1_Key__c FROM Import_Row__c WHERE Import_Batch__c = :batchId',
            new Map<String, Object>{ 'batchId' => batch.Id },
            AccessLevel.SYSTEM_MODE
        );
        Assert.isNotNull(
            rows[0].Person_1_Key__c,
            'The row carries the key a later chunk finds her by.'
        );
    }
}

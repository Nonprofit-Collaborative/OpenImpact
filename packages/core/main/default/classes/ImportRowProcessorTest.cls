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

    // -------------------------------------------------------------------------------------
    // A row with two people in it
    // -------------------------------------------------------------------------------------

    /**
     * The couple mapping: a household name, and two people each carrying both a Name column
     * and the name parts.
     *
     * One mapping serves both ways of storing a person. Contact has no writable Name, so the
     * Name column is skipped there and the parts are used; an org that stores people as
     * accounts has Name and, unless Person Accounts are actually switched on in the org
     * running this test, none of the parts, so it takes Name and reports the rest in the run
     * log. Nothing here names a Person Account field at compile time (ADR-0009).
     */
    private static String coupleMapping() {
        ImportMapping mapping = new ImportMapping();
        mapping.columns.add(new ImportMapping.Column('Household', 'Household.Name'));
        mapping.columns.add(new ImportMapping.Column('Person 1', 'Contact1.Name'));
        mapping.columns.add(new ImportMapping.Column('First 1', 'Contact1.FirstName'));
        mapping.columns.add(new ImportMapping.Column('Last 1', 'Contact1.LastName'));
        mapping.columns.add(new ImportMapping.Column('Person 2', 'Contact2.Name'));
        mapping.columns.add(new ImportMapping.Column('First 2', 'Contact2.FirstName'));
        mapping.columns.add(new ImportMapping.Column('Last 2', 'Contact2.LastName'));
        return mapping.serialize();
    }

    /** One row naming a household and the two people who live in it. */
    private static void givenACoupleOnOneRow(String personMode) {
        template = ImportTestDataFactory.template(
            coupleMapping(),
            ImportTemplateService.RULE_EMAIL
        );
        template.Person_Mode__c = personMode;
        update template;
        batch = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(
            batch,
            new List<Map<String, String>>{
                new Map<String, String>{
                    'Household' => 'The Garcia Lee Household',
                    'Person 1' => 'Maria Garcia',
                    'First 1' => 'Maria',
                    'Last 1' => 'Garcia',
                    'Person 2' => 'Wei Lee',
                    'First 2' => 'Wei',
                    'Last 2' => 'Lee'
                }
            }
        );
    }

    /** The households this org has, which is the number a two person row has to produce. */
    private static List<Account> households() {
        return [
            SELECT Id, Name, Custom_Name__c, Member_Count__c
            FROM Account
            WHERE RecordTypeId = :HouseholdService.householdRecordTypeId()
        ];
    }

    /**
     * Junction mode, which is the mode a Nonprofit Cloud org is put into on its first day.
     *
     * The household itself is made by the household trigger for the first person (ADR-0037);
     * what this asserts is that the second person is joined to that one rather than being
     * given a household of their own, and that the join is a membership row, because that is
     * what membership means in this mode.
     */
    @IsTest
    static void aRowWithTwoPeopleMakesOneHouseholdInJunctionMode() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
        givenACoupleOnOneRow(ImportTemplateService.PERSON_MODE_CONTACTS);

        Test.startTest();
        run(false);
        Test.stopTest();

        List<Account> households = households();
        Assert.areEqual(1, households.size(), 'One row of two people is one household.');
        Assert.areEqual(
            'The Garcia Lee Household',
            households[0].Name,
            'Named from the row, which is what the household column on the row means.'
        );
        Assert.isTrue(households[0].Custom_Name__c, 'And named by hand, so naming leaves it be.');
        Assert.areEqual(
            2,
            [
                SELECT COUNT()
                FROM Household_Member__c
                WHERE Household__c = :households[0].Id AND Contact__c != NULL
            ],
            'Both people are joined to it by a membership row, which is what junction mode means.'
        );
        Assert.areEqual(2, [SELECT COUNT() FROM Contact], 'And there are two people, not one.');
    }

    /**
     * The same row in contact mode, where membership is the person's own account reference.
     * The behaviour an administrator sees is identical, which is the point of the service
     * the importer joins people through.
     */
    @IsTest
    static void aRowWithTwoPeopleMakesOneHouseholdInContactMode() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        givenACoupleOnOneRow(ImportTemplateService.PERSON_MODE_CONTACTS);

        Test.startTest();
        run(false);
        Test.stopTest();

        List<Account> households = households();
        Assert.areEqual(1, households.size(), 'One row of two people is still one household.');
        Assert.areEqual(
            'The Garcia Lee Household',
            households[0].Name,
            'Named from the row here too.'
        );
        Assert.isTrue(households[0].Custom_Name__c, 'And named by hand.');
        Assert.areEqual(
            2,
            [SELECT COUNT() FROM Contact WHERE AccountId = :households[0].Id],
            'Both people point at it, which is what contact mode means.'
        );
        Assert.areEqual(2, households[0].Member_Count__c, 'And the household counts both of them.');
    }

    /**
     * The configuration the product recommends: people stored as accounts, membership in
     * junction mode. This is the half the old importer could never do, because it joined the
     * second person by writing an account reference and skipped that entirely for a person
     * stored as an account.
     *
     * What this test substitutes and what it does not: the org shape is declared, through
     * `OrgShapeDetector.overrideShape` and `PersonRecordSelector.personRecordOverride`,
     * because a Platform only test org has no person accounts to make (ADR-0013), and the
     * person details are declared because that org has no person name fields to hold them.
     * The records, the membership rows and the household are real.
     */
    @IsTest
    static void aRowWithTwoPeopleMakesOneHouseholdWherePeopleAreStoredAsAccounts() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
        HouseholdService.personAccountOverride = true;
        PersonRecordSelector.personRecordOverride = true;
        PersonRecordSelector.personOverridesByName = new Map<String, HouseholdService.Person>{
            'Maria Garcia' => HouseholdTestDataFactory.person('Ms.', 'Maria', 'Garcia', 'Head'),
            'Wei Lee' => HouseholdTestDataFactory.person('Mr.', 'Wei', 'Lee', null)
        };
        OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
        shape.hasPersonAccounts = true;
        shape.personAccountRecordTypeIds = new Set<Id>{ organizationRecordTypeId() };
        OrgShapeDetector.overrideShape = shape;
        givenACoupleOnOneRow(ImportTemplateService.PERSON_MODE_PERSON_ACCOUNTS);

        Test.startTest();
        run(false);
        Test.stopTest();

        List<Account> households = households();
        Assert.areEqual(
            1,
            households.size(),
            'A couple stored as accounts is one household, not two and not none.'
        );
        Assert.areEqual(
            'The Garcia Lee Household',
            households[0].Name,
            'Named from the row, whichever object holds the people.'
        );
        Assert.isTrue(households[0].Custom_Name__c, 'And named by hand.');
        List<Household_Member__c> memberships = [
            SELECT Account__c
            FROM Household_Member__c
            WHERE Household__c = :households[0].Id AND Account__c != NULL
        ];
        Assert.areEqual(2, memberships.size(), 'Both people are joined to it.');
        Set<Id> members = new Set<Id>();
        for (Household_Member__c membership : memberships) {
            members.add(membership.Account__c);
        }
        Assert.areEqual(
            2,
            [SELECT COUNT() FROM Account WHERE Id IN :members AND Name != NULL],
            'And they are two different people.'
        );
        Import_Row__c row = ImportTestDataFactory.reload(batch.Id)[0];
        Assert.areEqual(
            households[0].Id,
            row.Household__c,
            'The row records the household it resolved to.'
        );
    }

    /**
     * A row that names only a second person, with nobody for them to join, still gets a
     * household of its own: the two pass save must not leave that person behind.
     */
    @IsTest
    static void aSecondPersonWithNobodyToJoinStillGetsAHousehold() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
        template = ImportTestDataFactory.template(
            coupleMapping(),
            ImportTemplateService.RULE_EMAIL
        );
        batch = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(
            batch,
            new List<Map<String, String>>{
                new Map<String, String>{ 'First 2' => 'Wei', 'Last 2' => 'Lee' }
            }
        );

        Test.startTest();
        run(false);
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM Contact], 'The person was created.');
        Assert.areEqual(1, households().size(), 'And given a household of their own.');
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Household_Member__c],
            'Joined to it by one membership row.'
        );
    }

    private static Id organizationRecordTypeId() {
        return Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
            .getRecordTypeInfosByDeveloperName()
            .get('Organization')
            .getRecordTypeId();
    }
}

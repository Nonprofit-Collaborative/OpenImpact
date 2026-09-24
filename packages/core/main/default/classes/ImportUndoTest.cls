/**
 * Undoing an import (canonical model R-IB7 to R-IB9): what it counts, what it refuses, what
 * it deletes and what it keeps.
 *
 * The job's passes chain from one another's finish, which a test runs only once, so the
 * delete passes are driven here through the job's own start query, one pass after another.
 */
@IsTest
private class ImportUndoTest {
    private static Import_Batch__c committedBatch() {
        TestDataFactory.defaultSettings();
        Import_Batch__c batch = ImportTestDataFactory.batch(
            ImportTestDataFactory.template(
                ImportTestDataFactory.donorMapping(),
                ImportTemplateService.RULE_EMAIL
            )
        );
        batch.Is_Dry_Run__c = false;
        batch.Status__c = ImportBatchService.STATUS_COMPLETE;
        batch.Started_At__c = Datetime.now().addMinutes(-5);
        batch.Completed_At__c = Datetime.now().addMinutes(1);
        batch.Committed_By__c = UserInfo.getUserId();
        batch.Undo_Deadline__c = Datetime.now().addDays(30);
        update batch;
        return batch;
    }

    /** A person the import created, and the household it created for them, both tagged. */
    private static Contact importedPerson(Import_Batch__c batch, String lastName) {
        Contact person = new Contact(
            FirstName = 'Ana',
            LastName = lastName,
            Created_By_Import_Batch__c = batch.Id
        );
        insert person;
        person = [SELECT Id, AccountId FROM Contact WHERE Id = :person.Id];
        update new Account(Id = person.AccountId, Created_By_Import_Batch__c = batch.Id);
        return person;
    }

    private static Account importedOrganization(Import_Batch__c batch) {
        Account organization = new Account(
            Name = 'Rose City Rotary',
            RecordTypeId = Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                .getRecordTypeInfosByDeveloperName()
                .get('Organization')
                .getRecordTypeId(),
            Created_By_Import_Batch__c = batch.Id
        );
        insert organization;
        return organization;
    }

    /** Starts the undo and runs its job, then the delete passes once more over what is left. */
    private static void undo(Import_Batch__c batch) {
        Integer total = ImportUndoService.preview(batch.Id).total;
        Test.startTest();
        ImportUndoService.start(batch.Id, total);
        Test.stopTest();
        runDeletePasses(batch, total, Datetime.now());
    }

    /**
     * The same, with the moment the undo started given, so a test can tell what the undo did
     * apart from what the test itself did a moment before.
     */
    private static void undo(Import_Batch__c batch, Datetime undoStartedAt) {
        Integer total = ImportUndoService.preview(batch.Id).total;
        // Latched and queued only: a test runs a queued job at Test.stopTest, and there is
        // none here, so the passes below are the only ones that run, each with this start.
        ImportUndoService.start(batch.Id, total);
        runDeletePasses(batch, total, undoStartedAt);
    }

    private static void runDeletePasses(
        Import_Batch__c batch,
        Integer total,
        Datetime undoStartedAt
    ) {
        List<String> passes = new List<String>{
            ImportUndoBatch.PASS_CONTACTS,
            ImportUndoBatch.PASS_PERSON_ACCOUNTS,
            ImportUndoBatch.PASS_ACCOUNTS
        };
        for (String pass : passes) {
            ImportUndoBatch job = new ImportUndoBatch(
                batch.Id,
                total,
                pass,
                0,
                false,
                undoStartedAt
            );
            Database.QueryLocatorIterator records = job.start(null).iterator();
            List<SObject> scope = new List<SObject>();
            while (records.hasNext()) {
                scope.add(records.next());
            }
            if (!scope.isEmpty()) {
                job.execute(null, scope);
            }
            if (pass == ImportUndoBatch.PASS_ACCOUNTS) {
                job.finish(null);
            }
        }
    }

    private static String undoJournal(Import_Batch__c batch) {
        String text = '';
        for (Import_Journal__c page : [
            SELECT Entries_JSON__c
            FROM Import_Journal__c
            WHERE Import_Batch__c = :batch.Id AND Phase__c = :ImportJournalService.PHASE_UNDO
        ]) {
            text += page.Entries_JSON__c;
        }
        return text;
    }

    private static Boolean exists(Id recordId) {
        return [SELECT COUNT() FROM Account WHERE Id = :recordId] +
            [SELECT COUNT() FROM Contact WHERE Id = :recordId] > 0;
    }

    @IsTest
    static void thePreviewCountsWhatCarriesTheTagByKind() {
        Import_Batch__c batch = committedBatch();
        importedPerson(batch, 'Ramirez');
        importedPerson(batch, 'Lee');
        importedOrganization(batch);
        insert new Contact(FirstName = 'Sam', LastName = 'Okafor');

        ImportUndoService.Preview view = ImportUndoService.preview(batch.Id);

        Assert.isTrue(view.allowed, 'A committed import inside its window can be undone.');
        Assert.areEqual(2, view.people, 'Two people carry the tag.');
        Assert.areEqual(2, view.households, 'And the two households made for them.');
        Assert.areEqual(1, view.organizations, 'And one organization.');
        Assert.areEqual(5, view.total, 'A person the import did not create is not counted.');
    }

    @IsTest
    static void undoDeletesWhatTheImportCreatedAndNothingElse() {
        Import_Batch__c batch = committedBatch();
        Contact imported = importedPerson(batch, 'Ramirez');
        Account organization = importedOrganization(batch);
        Contact existing = new Contact(FirstName = 'Sam', LastName = 'Okafor');
        insert existing;

        undo(batch);

        Assert.isFalse(exists(imported.Id), 'The person the import created is gone.');
        Assert.isFalse(exists(imported.AccountId), 'So is the household made for them.');
        Assert.isFalse(exists(organization.Id), 'And the organization.');
        Assert.isTrue(exists(existing.Id), 'A person the import did not create is untouched.');
        Assert.areEqual(0, [SELECT COUNT() FROM Error_Log__c], 'Every guard could run.');
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Contact WHERE Id = :imported.Id AND IsDeleted = TRUE ALL ROWS],
            'Deleted to the recycle bin, not destroyed (R-IB8).'
        );
        Import_Batch__c after = [
            SELECT Status__c, Run_Log__c
            FROM Import_Batch__c
            WHERE Id = :batch.Id
        ];
        Assert.areEqual(ImportBatchService.STATUS_UNDONE, after.Status__c, 'The batch is Undone.');
        Assert.isTrue(
            after.Run_Log__c.contains(UserInfo.getName()),
            'And the run log says who undid it (R-IB9).'
        );
    }

    @IsTest
    static void aRecordThatGainedSomethingSinceIsKept() {
        Import_Batch__c batch = committedBatch();
        Contact imported = importedPerson(batch, 'Ramirez');
        Account organization = importedOrganization(batch);
        Affiliation__c later = new Affiliation__c(
            Contact__c = imported.Id,
            Organization__c = organization.Id,
            Status__c = 'Current'
        );
        insert later;
        Test.setCreatedDate(later.Id, Datetime.now().addHours(1));

        undo(batch);

        Assert.isTrue(
            exists(imported.Id),
            'Somebody recorded an affiliation for this person since.'
        );
        Assert.isTrue(exists(organization.Id), 'And for this organization.');
        Assert.isTrue(exists(imported.AccountId), 'The kept person keeps their household.');
        Assert.isTrue(
            ImportJournalService.entryCount(batch.Id, ImportJournalService.PHASE_UNDO) >= 3,
            'Each kept record is journaled with its reason (R-IJ3).'
        );
    }

    @IsTest
    static void anOrganizationAnotherAccountNamedSinceIsKept() {
        Import_Batch__c batch = committedBatch();
        Account organization = importedOrganization(batch);
        Account later = new Account(Name = 'Okafor', Primary_Affiliation__c = organization.Id);
        insert later;
        Test.setCreatedDate(later.Id, Datetime.now().addHours(1));

        undo(batch);

        Assert.isTrue(exists(organization.Id), 'An account created since names it.');
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Error_Log__c],
            'A reference from the same object is checked without a semi-join SOQL refuses.'
        );
    }

    @IsTest
    static void aRecordSomebodyEditedSinceIsKept() {
        Import_Batch__c batch = committedBatch();
        batch.Started_At__c = Datetime.now().addHours(-3);
        batch.Completed_At__c = Datetime.now().addHours(-2);
        update batch;
        Contact imported = importedPerson(batch, 'Ramirez');

        // The person was saved just now, long after the commit settled, by somebody who is
        // not the undo: an edit since.
        undo(batch, Datetime.now().addHours(1));

        Assert.isTrue(exists(imported.Id), 'An edit since the import keeps the record (R-IB9).');
        Assert.isTrue(
            undoJournal(batch).contains(Label.Core_Import_UndoKeptEdited),
            'And the journal says why.'
        );
    }

    @IsTest
    static void anActivityRecordedSinceKeepsThePerson() {
        Import_Batch__c batch = committedBatch();
        Contact imported = importedPerson(batch, 'Ramirez');
        // An activity is a standard object Core never names: it is found through the
        // person's child relationships, the same way a gift is (R-IB9).
        Task call = new Task(Subject = 'Thank-you call', WhoId = imported.Id);
        insert call;
        Test.setCreatedDate(call.Id, Datetime.now().addHours(1));

        undo(batch);

        Assert.isTrue(exists(imported.Id), 'An activity logged since keeps the person.');
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'ImportUndoBatch.guardQuery'],
            'Every relationship could be checked.'
        );
    }

    @IsTest
    static void anUndoThePlatformStoppedEndsUndoFailedAndCanRunAgain() {
        Import_Batch__c batch = committedBatch();
        Contact imported = importedPerson(batch, 'Ramirez');
        Integer total = ImportUndoService.preview(batch.Id).total;
        // Latched and queued, never run: where a chunk the platform stopped leaves things,
        // with its delete rolled back and the records still there.
        ImportUndoService.start(batch.Id, total);
        ImportUndoBatch.jobErrorsForTest = 1;
        // The last pass finishing: the state execute would have set is lost with the chunk,
        // and only the job's error count says what happened.
        new ImportUndoBatch(batch.Id, total, ImportUndoBatch.PASS_ACCOUNTS, 0, false).finish(null);

        Assert.areEqual(
            ImportBatchService.STATUS_UNDO_FAILED,
            [SELECT Status__c FROM Import_Batch__c WHERE Id = :batch.Id].Status__c,
            'A chunk the platform stopped is a failure, not a success (R-IB8).'
        );
        ImportUndoService.Preview again = ImportUndoService.preview(batch.Id);
        Assert.isTrue(again.allowed, 'And the undo can be run again.');

        ImportUndoBatch.jobErrorsForTest = null;
        runDeletePasses(batch, again.total, Datetime.now());

        Assert.isFalse(exists(imported.Id), 'The second run finishes the work.');
        Assert.areEqual(
            ImportBatchService.STATUS_UNDONE,
            [SELECT Status__c FROM Import_Batch__c WHERE Id = :batch.Id].Status__c,
            'And ends Undone.'
        );
        Assert.isTrue(total > 0, 'There was something to undo.');
    }

    @IsTest
    static void anUndoWhoseJobWasAbortedCanRunAgain() {
        Import_Batch__c batch = committedBatch();
        importedPerson(batch, 'Ramirez');
        batch.Status__c = ImportBatchService.STATUS_UNDOING;
        update batch;

        ImportUndoService.Preview view = ImportUndoService.preview(batch.Id);

        Assert.isTrue(
            view.allowed,
            'Undoing with no undo job queued or running is an aborted undo, not a running one.'
        );
        Assert.areEqual(
            ImportBatchService.STATUS_UNDO_FAILED,
            ImportUndoService.effectiveStatus(
                [SELECT Status__c FROM Import_Batch__c WHERE Id = :batch.Id]
            ),
            'And it is shown as Undo failed (R-IB8).'
        );
    }

    @IsTest
    static void aHouseholdSomebodyElseHasJoinedIsKept() {
        Import_Batch__c batch = committedBatch();
        Contact imported = importedPerson(batch, 'Ramirez');
        Contact joined = new Contact(
            FirstName = 'Luis',
            LastName = 'Ramirez',
            AccountId = imported.AccountId
        );
        insert joined;

        undo(batch);

        Assert.isFalse(exists(imported.Id), 'The imported person is gone.');
        Assert.isTrue(exists(imported.AccountId), 'Their household is kept for the person in it.');
        Assert.isTrue(exists(joined.Id), 'Who is untouched.');
    }

    @IsTest
    static void undoIsRefusedForADryRunAClosedWindowOrAChangedCount() {
        Import_Batch__c batch = committedBatch();
        importedPerson(batch, 'Ramirez');

        batch.Is_Dry_Run__c = true;
        update batch;
        Assert.areEqual(
            Label.Core_Import_UndoErrorDryRun,
            ImportUndoService.preview(batch.Id).reason,
            'A dry run wrote nothing to undo.'
        );

        batch.Is_Dry_Run__c = false;
        batch.Undo_Deadline__c = Datetime.now().addDays(-1);
        update batch;
        Assert.isFalse(ImportUndoService.preview(batch.Id).allowed, 'The window has closed.');

        batch.Undo_Deadline__c = Datetime.now().addDays(1);
        update batch;
        try {
            ImportUndoService.start(batch.Id, 99);
            Assert.fail('A count that is not the count shown is refused.');
        } catch (ImportException expected) {
            Assert.isTrue(expected.getMessage().contains('99'), 'Naming the number confirmed.');
        }
        Assert.areEqual(
            ImportBatchService.STATUS_COMPLETE,
            [SELECT Status__c FROM Import_Batch__c WHERE Id = :batch.Id].Status__c,
            'And nothing was started.'
        );
    }

    @IsTest
    static void undoRunsOnce() {
        Import_Batch__c batch = committedBatch();
        importedPerson(batch, 'Ramirez');
        Test.startTest();
        ImportUndoService.start(batch.Id, 2);
        try {
            ImportUndoService.start(batch.Id, 2);
            Assert.fail('A second undo of the same import is refused, not queued.');
        } catch (ImportException expected) {
            Assert.areEqual(
                Label.Core_Import_UndoErrorAlreadyUndone,
                expected.getMessage(),
                'Saying why.'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void anImportThatCreatedNothingHasNothingToUndo() {
        Import_Batch__c batch = committedBatch();
        ImportUndoService.Preview view = ImportUndoService.preview(batch.Id);
        Assert.isFalse(view.allowed, 'There is nothing to undo.');
        Assert.areEqual(Label.Core_Import_UndoErrorNothingToUndo, view.reason, 'And it says so.');
    }

    private static Map<String, Object> cityWas(Contact person, String before, String after) {
        return ImportJournalService.updated(
            'Contact',
            person.Id,
            2,
            new Map<String, Object>{ 'MailingCity' => before },
            new Map<String, Object>{ 'MailingCity' => after }
        );
    }

    /**
     * A value the import wrote is put back where nobody has changed it since, left alone where
     * somebody has, and passed over silently where it is already back, which is what makes a
     * second run of a failed undo safe (R-IB8, R-IB9).
     */
    @IsTest
    static void undoPutsBackOnlyTheValuesNobodyHasChangedSince() {
        Import_Batch__c batch = committedBatch();
        Contact untouched = new Contact(LastName = 'Ramirez', MailingCity = 'Portland');
        Contact corrected = new Contact(LastName = 'Lee', MailingCity = 'Eugene');
        Contact alreadyBack = new Contact(LastName = 'Okafor', MailingCity = 'Salem');
        insert new List<Contact>{ untouched, corrected, alreadyBack };
        ImportJournalService.write(
            batch.Id,
            ImportJournalService.PHASE_COMMIT,
            new List<Map<String, Object>>{
                cityWas(untouched, 'Salem', 'Portland'),
                cityWas(corrected, 'Salem', 'Portland'),
                cityWas(alreadyBack, 'Salem', 'Portland')
            }
        );
        Assert.areEqual(3, ImportUndoService.preview(batch.Id).updates, 'The preview counts them.');

        Test.startTest();
        ImportUndoService.start(batch.Id, 0);
        Test.stopTest();

        Map<Id, Contact> after = new Map<Id, Contact>([SELECT MailingCity FROM Contact]);
        Assert.areEqual('Salem', after.get(untouched.Id).MailingCity, 'Put back.');
        Assert.areEqual('Eugene', after.get(corrected.Id).MailingCity, 'A correction is kept.');
        Assert.areEqual('Salem', after.get(alreadyBack.Id).MailingCity, 'Left as it is.');
        List<Map<String, Object>> journal = ImportJournalService.entries(
            ImportJournalService.pages(batch.Id, ImportJournalService.PHASE_UNDO, 10)[0]
        );
        Assert.areEqual(1, journal.size(), 'Only the correction is journaled as not put back.');
        Assert.areEqual(
            ImportJournalService.ACTION_NOT_RESTORED,
            journal[0].get('action'),
            'With its reason.'
        );
    }

    /** Values come back as the field's own type, and compare as values, not as text. */
    @IsTest
    static void journaledValuesCompareAndComeBackTyped() {
        Date birthday = Date.newInstance(1970, 5, 17);
        Assert.isTrue(ImportUndoBatch.same(birthday, '1970-05-17'), 'A date by its written form.');
        Assert.isTrue(ImportUndoBatch.same(5, 5.0), 'A number as a number.');
        Assert.isFalse(ImportUndoBatch.same('Salem', 'salem'), 'Text exactly.');
        Assert.isTrue(ImportUndoBatch.same(null, null), 'Nothing is nothing.');
        Assert.areEqual(
            birthday,
            ImportUndoBatch.typed('1970-05-17', Contact.Birthdate.getDescribe()),
            'A date comes back a date.'
        );
        Assert.areEqual(
            false,
            ImportUndoBatch.typed(false, Account.Custom_Name__c.getDescribe()),
            'And a checkbox a checkbox.'
        );
    }
}

/**
 * Bulk update (C-35, R-IB14, R-IB15): checked as the person, counted and confirmed, run in user
 * mode over only the records that still match, journaled, and undone.
 *
 * The records are saved queries: a package object with private sharing and no automation, so
 * the sharing case is a real one and nothing but the bulk update writes them. A job is run the
 * way the platform runs it (start, each chunk, finish) where a test needs to act between its
 * steps, and through Test.stopTest where it does not.
 */
@IsTest
private class BulkUpdateServiceTest {
    private static final String CITY = 'Object_Name__c';

    private static String documentFor(String prefix) {
        return JSON.serialize(
            new Map<String, Object>{
                'version' => 1,
                'object' => 'Saved_Query__c',
                'fields' => new List<String>{ 'Name', CITY },
                'filter' => new Map<String, Object>{
                    'conditions' => new List<Object>{
                        new Map<String, Object>{
                            'id' => 1,
                            'field' => 'Name',
                            'operator' => 'starts with',
                            'value' => prefix
                        }
                    }
                }
            }
        );
    }

    private static String setTo(String field, Object value) {
        return JSON.serialize(
            new List<Object>{
                new Map<String, Object>{ 'field' => field, 'action' => 'set', 'value' => value }
            }
        );
    }

    private static List<Saved_Query__c> records(String prefix, Integer howMany, String value) {
        List<Saved_Query__c> result = new List<Saved_Query__c>();
        for (Integer i = 0; i < howMany; i++) {
            result.add(
                new Saved_Query__c(
                    Name = prefix + String.valueOf(i).leftPad(4, '0'),
                    Object_Name__c = value
                )
            );
        }
        insert result;
        return result;
    }

    private static String refusal(String documentJson, String changesJson, Integer confirmed) {
        try {
            if (confirmed == null) {
                BulkUpdateService.preview(documentJson, changesJson);
            } else {
                BulkUpdateService.start(documentJson, changesJson, confirmed);
            }
        } catch (DataManagementException refused) {
            return refused.getMessage();
        } catch (QueryCompiler.QueryCompilerException refused) {
            return refused.getMessage();
        }
        return null;
    }

    /** Runs a started job's steps in this transaction, as the platform would. */
    private static void runJob(Id jobId) {
        BulkUpdateBatch job = new BulkUpdateBatch(jobId);
        Database.QueryLocatorIterator found = job.start(null).iterator();
        List<SObject> scope = new List<SObject>();
        while (found.hasNext()) {
            scope.add(found.next());
        }
        if (!scope.isEmpty()) {
            job.execute(null, scope);
        }
        job.finish(null);
    }

    private static Import_Batch__c jobRecord(Id jobId) {
        return [
            SELECT
                Id,
                Status__c,
                Operation__c,
                Operation_JSON__c,
                Row_Count__c,
                Rows_Updated__c,
                Rows_Matched__c,
                Rows_Rejected__c,
                Run_Log__c,
                Undo_Deadline__c,
                Committed_By__c,
                Import_Template__c
            FROM Import_Batch__c
            WHERE Id = :jobId
        ];
    }

    private static List<Map<String, Object>> journal(Id jobId, String phase) {
        List<Map<String, Object>> entries = new List<Map<String, Object>>();
        for (Import_Journal__c page : [
            SELECT Id, Entries_JSON__c
            FROM Import_Journal__c
            WHERE Import_Batch__c = :jobId AND Phase__c = :phase
        ]) {
            entries.addAll(ImportJournalService.entries(page));
        }
        return entries;
    }

    @IsTest
    static void updatesTwoHundredRecordsAndJournalsEachOne() {
        records('B', 200, 'Contact');
        String documentJson = documentFor('B');
        String changes = setTo(CITY, 'Account');
        Assert.areEqual(200, BulkUpdateService.preview(documentJson, changes).count);

        Test.startTest();
        Import_Batch__c started = BulkUpdateService.start(documentJson, changes, 200);
        Test.stopTest();

        Import_Batch__c job = jobRecord(started.Id);
        Assert.areEqual(BulkUpdateService.OPERATION_UPDATE, job.Operation__c);
        Assert.isNull(job.Import_Template__c, 'a bulk update has no template');
        Assert.areEqual(ImportBatchService.STATUS_COMPLETE, job.Status__c);
        Assert.areEqual(200, job.Rows_Updated__c.intValue());
        Assert.areEqual(UserInfo.getUserId(), job.Committed_By__c);
        Assert.isNotNull(job.Undo_Deadline__c);
        Assert.areEqual(0, [SELECT COUNT() FROM Import_Row__c], 'a bulk update stages no rows');
        Assert.areEqual(200, [SELECT COUNT() FROM Saved_Query__c WHERE Object_Name__c = 'Account']);
        List<Map<String, Object>> entries = journal(job.Id, ImportJournalService.PHASE_COMMIT);
        Assert.areEqual(200, entries.size());
        Map<String, Object> fields = (Map<String, Object>) entries[0].get('fields');
        Map<String, Object> city = (Map<String, Object>) fields.get(CITY);
        Assert.areEqual('Contact', city.get('before'));
        Assert.areEqual('Account', city.get('after'));
    }

    @IsTest
    static void refusesToStartWhenMoreMatchThanWereConfirmed() {
        records('C', 5, 'Contact');
        String message = refusal(documentFor('C'), setTo(CITY, 'Account'), 4);
        Assert.areEqual(
            String.format(Label.Core_BulkUpdate_ErrorMoreThanConfirmed, new List<String>{ '4' }),
            message
        );
        Assert.areEqual(0, [SELECT COUNT() FROM Import_Batch__c], 'no job was created');
        Assert.areEqual(0, [SELECT COUNT() FROM Saved_Query__c WHERE Object_Name__c = 'Account']);
    }

    @IsTest
    static void refusesMoreRecordsThanTheMaximum() {
        Barn_Settings__c settings = TestDataFactory.defaultSettings();
        settings.Bulk_Update_Max_Records__c = 3;
        TestDataFactory.saveSettings(settings);
        records('M', 5, 'Contact');
        String expected = String.format(
            Label.Core_BulkUpdate_ErrorOverMaximum,
            new List<String>{ '3' }
        );
        Assert.areEqual(expected, refusal(documentFor('M'), setTo(CITY, 'Account'), null));
        Assert.areEqual(expected, refusal(documentFor('M'), setTo(CITY, 'Account'), 5));
    }

    @IsTest
    static void processesAtMostTheConfirmedNumber() {
        records('L', 5, 'Contact');
        Import_Batch__c started = BulkUpdateService.start(
            documentFor('L'),
            setTo(CITY, 'Account'),
            5
        );
        // Two more match after the start; the job still changes only the five confirmed.
        records('L9', 2, 'Contact');
        runJob(started.Id);
        Assert.areEqual(5, jobRecord(started.Id).Rows_Updated__c.intValue());
        Assert.areEqual(2, [SELECT COUNT() FROM Saved_Query__c WHERE Object_Name__c = 'Contact']);
    }

    @IsTest
    static void leavesARecordThatNoLongerMatches() {
        List<Saved_Query__c> inserted = records('N', 4, 'Contact');
        Import_Batch__c started = BulkUpdateService.start(
            documentFor('N'),
            setTo(CITY, 'Account'),
            4
        );
        BulkUpdateBatch job = new BulkUpdateBatch(started.Id);
        Database.QueryLocatorIterator found = job.start(null).iterator();
        List<SObject> scope = new List<SObject>();
        while (found.hasNext()) {
            scope.add(found.next());
        }
        Assert.areEqual(4, scope.size());
        // Renamed after the job read it and before its chunk runs: it no longer matches.
        inserted[0].Name = 'Renamed';
        update inserted[0];
        job.execute(null, scope);
        job.finish(null);

        Import_Batch__c finished = jobRecord(started.Id);
        Assert.areEqual(3, finished.Rows_Updated__c.intValue());
        Assert.isTrue(
            finished.Run_Log__c.contains(
                String.format(
                    Label.Core_BulkUpdate_LogFinished,
                    new List<String>{ '3', '0', '1', '0' }
                )
            ),
            finished.Run_Log__c
        );
        Assert.areEqual(
            'Contact',
            [SELECT Object_Name__c FROM Saved_Query__c WHERE Id = :inserted[0].Id].Object_Name__c
        );
    }

    @IsTest
    static void journalsARecordThatDidNotSaveAndSavesTheRest() {
        List<Saved_Query__c> inserted = records('F', 3, 'short');
        inserted[0].Object_Name__c = 'x'.repeat(200);
        update inserted[0];
        String copy = JSON.serialize(
            new List<Object>{
                new Map<String, Object>{ 'field' => 'Name', 'action' => 'copy', 'source' => CITY }
            }
        );
        Import_Batch__c started = BulkUpdateService.start(documentFor('F'), copy, 3);
        runJob(started.Id);

        Import_Batch__c job = jobRecord(started.Id);
        Assert.areEqual(2, job.Rows_Updated__c.intValue());
        Assert.areEqual(
            1,
            job.Rows_Rejected__c.intValue(),
            'a value too long for Name fails that record only'
        );
        Boolean failedEntry = false;
        for (Map<String, Object> entry : journal(job.Id, ImportJournalService.PHASE_COMMIT)) {
            if (entry.get('action') == ImportJournalService.ACTION_FAILED) {
                failedEntry = true;
                Assert.areEqual(String.valueOf(inserted[0].Id), entry.get('id'));
                Assert.isNotNull(entry.get('reason'));
            }
        }
        Assert.isTrue(failedEntry);
    }

    @IsTest
    static void undoPutsBackEachValueNobodyChangedSince() {
        List<Saved_Query__c> inserted = records('U', 3, 'Contact');
        Import_Batch__c started = BulkUpdateService.start(
            documentFor('U'),
            setTo(CITY, 'Account'),
            3
        );
        runJob(started.Id);
        // Somebody corrects one record after the bulk update: the undo must leave it alone.
        inserted[0].Object_Name__c = 'Corrected';
        update inserted[0];

        ImportUndoService.Preview preview = ImportUndoService.preview(started.Id);
        Assert.isTrue(preview.allowed, preview.reason);
        Assert.areEqual(3, preview.updates);
        Assert.areEqual(0, preview.total, 'a bulk update created nothing to delete');
        Test.startTest();
        ImportUndoService.start(started.Id, preview.total);
        Test.stopTest();

        Map<Id, Saved_Query__c> now = new Map<Id, Saved_Query__c>(
            [SELECT Id, Object_Name__c FROM Saved_Query__c]
        );
        Assert.areEqual('Corrected', now.get(inserted[0].Id).Object_Name__c);
        Assert.areEqual('Contact', now.get(inserted[1].Id).Object_Name__c);
        Assert.areEqual('Contact', now.get(inserted[2].Id).Object_Name__c);
        Assert.areEqual(ImportBatchService.STATUS_UNDONE, jobRecord(started.Id).Status__c);
        Boolean notRestored = false;
        for (Map<String, Object> entry : journal(started.Id, ImportJournalService.PHASE_UNDO)) {
            notRestored |= entry.get('action') == ImportJournalService.ACTION_NOT_RESTORED;
        }
        Assert.isTrue(notRestored, 'the value somebody changed is journaled as not put back');
        Assert.areEqual(3, [SELECT COUNT() FROM Saved_Query__c], 'an undo deletes nothing');
    }

    @IsTest
    static void neverCountsOrChangesARecordThePersonCannotSee() {
        User owner = TestDataFactory.createUser('Bulkown', new List<String>{ 'Barn_Admin' });
        User colleague = TestDataFactory.createUser('Bulkcol', new List<String>{ 'Barn_Admin' });
        List<Saved_Query__c> theirs;
        System.runAs(owner) {
            theirs = records('S', 3, 'Contact');
        }
        System.runAs(colleague) {
            records('S', 2, 'Contact');
            BulkUpdateService.Preview preview = BulkUpdateService.preview(
                documentFor('S'),
                setTo(CITY, 'Account')
            );
            Assert.areEqual(2, preview.count, 'only the colleague\'s own records are counted');
            Import_Batch__c started = BulkUpdateService.start(
                documentFor('S'),
                setTo(CITY, 'Account'),
                2
            );
            runJob(started.Id);
            Assert.areEqual(2, jobRecord(started.Id).Rows_Updated__c.intValue());
        }
        Set<Id> theirIds = new Map<Id, Saved_Query__c>(theirs).keySet();
        for (Saved_Query__c query : [
            SELECT Object_Name__c
            FROM Saved_Query__c
            WHERE Id IN :theirIds
        ]) {
            Assert.areEqual('Contact', query.Object_Name__c, 'the owner\'s records are untouched');
        }
    }

    @IsTest
    static void refusesProtectedObjectsAndFields() {
        records('P', 1, 'Contact');
        String onJobs = JSON.serialize(
            new Map<String, Object>{
                'version' => 1,
                'object' => 'Import_Batch__c',
                'fields' => new List<String>()
            }
        );
        Assert.isTrue(
            refusal(onJobs, setTo('Run_Log__c', 'x'), null)
                .endsWith(Label.Core_BulkUpdate_ReasonBookkeeping)
        );
        Assert.areEqual(
            String.format(
                Label.Core_BulkUpdate_ErrorProtectedField,
                new List<String>{ 'Document', Label.Core_BulkUpdate_ReasonComputed }
            ),
            refusal(documentFor('P'), setTo('Query_JSON__c', '{}'), null)
        );
        Assert.isNotNull(refusal(documentFor('P'), setTo('CreatedDate', '2026-01-01'), null));
        String clearName = JSON.serialize(
            new List<Object>{ new Map<String, Object>{ 'field' => 'Name', 'action' => 'clear' } }
        );
        Assert.isNotNull(refusal(documentFor('P'), clearName, null), 'a required field');
    }

    @IsTest
    static void checksEveryChangeAgainstDescribe() {
        records('I', 1, 'Contact');
        String documentJson = documentFor('I');
        for (
            String hostile : new List<String>{
                'Name, Id',
                'Owner.Name',
                'Name WHERE Id != null',
                'No_Such_Field__c'
            }
        ) {
            Assert.isNotNull(refusal(documentJson, setTo(hostile, 'x'), null), hostile);
        }
        Assert.isNotNull(
            refusal(documentJson, setTo('Is_Shared__c', 'perhaps'), null),
            'a value must suit the field'
        );
        List<Object> six = new List<Object>();
        for (Integer i = 0; i < 6; i++) {
            six.add(
                new Map<String, Object>{ 'field' => 'Name', 'action' => 'set', 'value' => 'x' }
            );
        }
        Assert.areEqual(
            Label.Core_BulkUpdate_ErrorTooManyChanges,
            refusal(documentJson, JSON.serialize(six), null)
        );
        String boolIntoText = JSON.serialize(
            new List<Object>{
                new Map<String, Object>{
                    'field' => 'Name',
                    'action' => 'copy',
                    'source' => 'Is_Shared__c'
                }
            }
        );
        Assert.isNotNull(refusal(documentJson, boolIntoText, null), 'an incompatible copy');
    }

    @IsTest
    static void writesAHostileValueAsPlainText() {
        records('H', 1, 'Contact');
        String hostile = 'x\' OR Name != \'';
        Test.startTest();
        BulkUpdateService.start(documentFor('H'), setTo(CITY, hostile), 1);
        Test.stopTest();
        Assert.areEqual(hostile, [SELECT Object_Name__c FROM Saved_Query__c].Object_Name__c);
    }

    @IsTest
    static void previewShowsTheCountAndAFewBeforeAndAfter() {
        records('V', 7, 'Contact');
        BulkUpdateService.Preview preview = BulkUpdateService.preview(
            documentFor('V'),
            setTo(CITY, 'Account')
        );
        Assert.areEqual(7, preview.count);
        Assert.areEqual(BulkUpdateService.SAMPLE_SIZE, preview.sample.size());
        BulkUpdateService.FieldChange shown = preview.sample[0].changes[0];
        Assert.areEqual('Contact', shown.before);
        Assert.areEqual('Account', shown.after);
        Assert.isTrue(preview.sample[0].name.startsWith('V'));
        Assert.areEqual(0, [SELECT COUNT() FROM Import_Batch__c], 'a preview saves nothing');
    }

    @IsTest
    static void refusesWhenNothingMatches() {
        Assert.areEqual(
            Label.Core_BulkUpdate_ErrorNothingMatches,
            refusal(documentFor('Z'), setTo(CITY, 'Account'), null)
        );
    }

    @IsTest
    static void theControllerOffersUndoOnlyForBulkUpdates() {
        BulkUpdateController.permissionOverride = true;
        Import_Batch__c anImport = new Import_Batch__c(
            Status__c = ImportBatchService.STATUS_COMPLETE,
            Is_Dry_Run__c = false
        );
        insert anImport;
        try {
            BulkUpdateController.previewUndo(anImport.Id);
            Assert.fail('the bulk update permission must not reach an import undo');
        } catch (AuraHandledException refused) {
            Assert.areEqual(Label.Core_BulkUpdate_ErrorNotABulkUpdate, refused.getMessage());
        }

        BulkUpdateController.permissionOverride = false;
        try {
            BulkUpdateController.getRecentJobs();
            Assert.fail('bulk update must refuse without its permission');
        } catch (AuraHandledException refused) {
            Assert.areEqual(Label.Core_BulkUpdate_ErrorNoPermission, refused.getMessage());
        }
    }

    @IsTest
    static void describesOnlyTheFieldsThatMayBeWritten() {
        BulkUpdateController.permissionOverride = true;
        BulkUpdateController.QueryView view = BulkUpdateController.describeQuery(documentFor('D'));
        Set<String> targets = new Set<String>();
        for (BulkUpdateController.Target target : view.targets) {
            targets.add(target.name);
        }
        Assert.isTrue(targets.contains(CITY));
        Assert.isFalse(targets.contains('Query_JSON__c'), 'the document is computed');
        Assert.isFalse(targets.contains('CreatedDate'), 'a system field');
        Assert.isFalse(targets.contains('Id'));
    }
}

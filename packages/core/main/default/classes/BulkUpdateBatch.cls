/**
 * The work of one bulk update (C-35, canonical model R-IB14), run as the person who started it.
 *
 * - **Only what was confirmed.** The query reads at most the confirmed number of records, in
 *   record identifier order, in user mode.
 * - **Only records that still match.** Each chunk reads its records again with the query's
 *   filter, so a record changed since the job started so that it no longer matches is left
 *   alone and counted.
 * - **The person's own access.** The query and its changes are checked again as the person when
 *   the job starts and in every chunk, so access taken away in between stops the job rather
 *   than being worked around, and every save is `Database.update(records, false, USER_MODE)`.
 * - **Journaled.** Each chunk writes one commit page (R-IJ1): an Updated entry per record saved,
 *   with the value before and after for each field that changed, and a Failed entry per record
 *   the platform refused. The undo is an import's (`ImportUndoService`).
 *
 * The job record and the journal are the package's own bookkeeping, written in system mode
 * (ADR-0021).
 */
@NamespaceAccessible
public with sharing class BulkUpdateBatch implements Database.Batchable<SObject>, Database.Stateful {
    private final Id jobId;
    private String definition;
    private Integer confirmedCount = 0;
    private Integer updated = 0;
    private Integer unchanged = 0;
    private Integer noLongerMatching = 0;
    private Integer failedRecords = 0;
    private Boolean failed = false;
    private Boolean journalIncomplete = false;
    private String stoppedBecause;

    /**
     * Set only by tests: the error count a job reports when the platform stopped a chunk, which
     * a test cannot bring about for real.
     */
    @TestVisible
    private static Integer jobErrorsForTest;

    @NamespaceAccessible
    public BulkUpdateBatch(Id jobId) {
        this.jobId = jobId;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        Id owner = jobId;
        Import_Batch__c job = [
            SELECT Id, Operation_JSON__c
            FROM Import_Batch__c
            WHERE Id = :owner
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        definition = job.Operation_JSON__c;
        try {
            confirmedCount = BulkUpdateService.confirmedCountOf(definition);
            BulkUpdateService.Plan plan = BulkUpdateService.planFromDefinition(definition);
            QueryCompiler.Query query = plan.compiled.forUpdate(plan.readFields(), confirmedCount);
            return Database.getQueryLocatorWithBinds(
                query.soql,
                query.binds,
                AccessLevel.USER_MODE
            );
        } catch (Exception e) {
            failed = true;
            stoppedBecause = e.getMessage();
            if (!(e instanceof DataManagementException)) {
                ErrorLogger.log(e, 'BulkUpdateBatch.start', jobId);
            }
            // Nothing to do: a locator that reads no record, so finish still closes the job.
            return Database.getQueryLocatorWithBinds(
                'SELECT Id FROM Import_Batch__c WHERE Id = :owner AND Id = null',
                new Map<String, Object>{ 'owner' => owner },
                AccessLevel.SYSTEM_MODE
            );
        }
    }

    public void execute(Database.BatchableContext context, List<SObject> records) {
        if (failed == true && String.isNotBlank(stoppedBecause)) {
            return;
        }
        List<Map<String, Object>> journal = new List<Map<String, Object>>();
        try {
            BulkUpdateService.Plan plan = BulkUpdateService.planFromDefinition(definition);
            Set<Id> ids = new Map<Id, SObject>(records).keySet();
            List<SObject> current = QuerySelector.records(
                plan.compiled.stillMatching(plan.readFields(), ids)
            );
            noLongerMatching += ids.size() - current.size();
            apply(plan, current, journal);
        } catch (Exception e) {
            failed = true;
            ErrorLogger.log(e, 'BulkUpdateBatch.execute', jobId);
        }
        if (!ImportJournalService.write(jobId, ImportJournalService.PHASE_COMMIT, journal)) {
            journalIncomplete = true;
        }
    }

    /**
     * Saves the changes one chunk makes and journals each record. A record whose fields
     * already hold the new values is not saved: there is nothing to put back.
     */
    @TestVisible
    private void apply(
        BulkUpdateService.Plan plan,
        List<SObject> records,
        List<Map<String, Object>> journal
    ) {
        String objectName = plan.compiled.objectName;
        List<SObject> toSave = new List<SObject>();
        List<Map<String, Object>> beforeOf = new List<Map<String, Object>>();
        List<Map<String, Object>> afterOf = new List<Map<String, Object>>();
        for (SObject record : records) {
            SObject change = plan.compiled.objectType.newSObject(record.Id);
            Map<String, Object> before = new Map<String, Object>();
            Map<String, Object> after = new Map<String, Object>();
            for (BulkUpdateService.Change planned : plan.changes) {
                Object was = record.get(planned.target);
                Object becomes = planned.newValueFor(record);
                if (!same(was, becomes)) {
                    String field = planned.targetDescribe.getName();
                    before.put(field, was);
                    after.put(field, becomes);
                    change.put(planned.target, becomes);
                }
            }
            if (after.isEmpty()) {
                unchanged++;
                continue;
            }
            toSave.add(change);
            beforeOf.add(before);
            afterOf.add(after);
        }
        if (toSave.isEmpty()) {
            return;
        }
        List<Database.SaveResult> results = Database.update(toSave, false, AccessLevel.USER_MODE);
        for (Integer i = 0; i < results.size(); i++) {
            Id recordId = toSave[i].Id;
            if (results[i].isSuccess()) {
                updated++;
                journal.add(
                    ImportJournalService.updated(
                        objectName,
                        recordId,
                        null,
                        beforeOf[i],
                        afterOf[i]
                    )
                );
            } else {
                failedRecords++;
                journal.add(ImportJournalService.failed(objectName, recordId, message(results[i])));
            }
        }
    }

    public void finish(Database.BatchableContext context) {
        if (chunkStopped(context)) {
            failed = true;
        }
        try {
            Import_Batch__c job = [
                SELECT Id, Run_Log__c
                FROM Import_Batch__c
                WHERE Id = :jobId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            List<String> lines = new List<String>();
            if (String.isNotBlank(job.Run_Log__c)) {
                lines.add(job.Run_Log__c);
            }
            if (String.isNotBlank(stoppedBecause)) {
                lines.add(
                    String.format(
                        Label.Core_BulkUpdate_LogStopped,
                        new List<String>{ stoppedBecause }
                    )
                );
            }
            lines.add(
                String.format(
                    Label.Core_BulkUpdate_LogFinished,
                    new List<String>{
                        String.valueOf(updated),
                        String.valueOf(unchanged),
                        String.valueOf(noLongerMatching),
                        String.valueOf(failedRecords)
                    }
                )
            );
            if (journalIncomplete) {
                lines.add(Label.Core_BulkUpdate_LogJournalIncomplete);
            }
            job.Run_Log__c = String.join(lines, '\n').right(32768);
            job.Status__c = failed
                ? ImportBatchService.STATUS_FAILED
                : ImportBatchService.STATUS_COMPLETE;
            job.Completed_At__c = Datetime.now();
            job.Rows_Updated__c = updated;
            job.Rows_Matched__c = unchanged;
            job.Rows_Rejected__c = failedRecords;
            Database.update(job, AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            ErrorLogger.log(e, 'BulkUpdateBatch.finish', jobId);
        }
    }

    /**
     * Whether the platform stopped any chunk. A governor limit cannot be caught, so the job's
     * own error count is the one record of it, as in the import undo (R-IB8).
     */
    private Boolean chunkStopped(Database.BatchableContext context) {
        if (jobErrorsForTest != null) {
            return jobErrorsForTest > 0;
        }
        if (context == null || context.getJobId() == null) {
            return false;
        }
        Id asyncJobId = context.getJobId();
        List<AsyncApexJob> jobs = [
            SELECT NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :asyncJobId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return !jobs.isEmpty() && jobs[0].NumberOfErrors != null && jobs[0].NumberOfErrors > 0;
    }

    /**
     * Whether two values are the same for a bulk update: numbers as numbers, text exactly, so a
     * value that differs only in capitals is still written.
     */
    @TestVisible
    private static Boolean same(Object stored, Object wanted) {
        if (stored == null || wanted == null) {
            return stored == null && wanted == null;
        }
        if (stored instanceof Decimal || stored instanceof Integer || stored instanceof Long) {
            try {
                return Decimal.valueOf(String.valueOf(stored)) ==
                    Decimal.valueOf(String.valueOf(wanted));
            } catch (Exception notANumber) {
                return false;
            }
        }
        if (stored instanceof String || wanted instanceof String) {
            return String.valueOf(stored).equals(String.valueOf(wanted));
        }
        return stored == wanted;
    }

    private static String message(Database.SaveResult result) {
        List<String> parts = new List<String>();
        for (Database.Error error : result.getErrors()) {
            parts.add(error.getMessage());
        }
        return String.join(parts, ' ');
    }
}

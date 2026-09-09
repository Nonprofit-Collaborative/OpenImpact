/**
 * Runs an import a chunk at a time in Batch Apex, with the chunk size the org set (R-IB2).
 *
 * The chunk is the unit of failure as well as the unit of work. Each chunk runs inside its
 * own try, so a chunk that hits a limit or an unexpected exception is recorded on its own
 * rows and in the run log, and the next chunk still runs. That is what R-IB5 asks for: a
 * partial failure leaves nothing half committed and unexplained, because every row says what
 * happened to it and the batch says how many did not make it.
 *
 * Stateful, because the run log and the fact that something failed have to survive from one
 * chunk to the next. The counts are not carried here: they are read back from the rows when
 * the run finishes, so a resumed or retried run still reports the truth.
 */
public with sharing class ImportProcessorBatch implements Database.Batchable<SObject>, Database.Stateful {
    /** How many lines of the run log are kept. A chunk failure is worth more than a note. */
    private static final Integer MAX_LOG_LINES = 200;

    private final Id batchId;
    private final Boolean dryRun;
    private Boolean failed = false;
    private List<String> log = new List<String>();
    private Set<String> notes = new Set<String>();
    private Integer chunksRun = 0;

    public ImportProcessorBatch(Id batchId, Boolean dryRun) {
        this.batchId = batchId;
        this.dryRun = dryRun == true;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        String pending = ImportRowProcessor.STATUS_PENDING;
        Id owner = batchId;
        return Database.getQueryLocator(
            [
                SELECT
                    Id,
                    Import_Batch__c,
                    Row_Number__c,
                    Raw_Values_JSON__c,
                    Status__c,
                    Error_Message__c,
                    Household__c,
                    Contact_1__c,
                    Person_1_Account__c,
                    Contact_2__c,
                    Person_2_Account__c,
                    Organization__c,
                    Gift_Id__c,
                    Soft_Credit_Id__c
                FROM Import_Row__c
                WHERE Import_Batch__c = :owner AND Status__c = :pending
                ORDER BY Row_Number__c ASC
            ]
        );
    }

    public void execute(Database.BatchableContext context, List<Import_Row__c> scope) {
        chunksRun++;
        try {
            Import_Batch__c batch = ImportBatchSelector.selectById(batchId);
            Import_Template__c template = ImportTemplateSelector.selectById(
                batch == null ? null : batch.Import_Template__c
            );
            if (batch == null || template == null) {
                throw new ImportException(Label.Core_Import_ErrorTemplateGone);
            }
            ImportMapping mapping = ImportMapping.parse(
                template.Column_Mapping_JSON__c,
                template.Default_Values_JSON__c
            );
            ImportRowProcessor.Outcome outcome = ImportRowProcessor.process(
                batch,
                template,
                mapping,
                scope,
                dryRun
            );
            notes.addAll(outcome.notes);
            if (!dryRun) {
                // One journal page per chunk, and only on a commit: a dry run wrote nothing,
                // so there is nothing about it that has to outlive the staged rows (R-IJ1).
                ImportJournalService.writePage(
                    batchId,
                    ImportJournalService.PHASE_COMMIT,
                    outcome.journal
                );
            }
        } catch (Exception e) {
            // The chunk is lost, not the run. Every row in it is marked with the reason so
            // that nothing disappears without an explanation an administrator can read.
            failed = true;
            rejectChunk(scope, e.getMessage());
            addLog(
                String.format(
                    Label.Core_Import_LogChunkFailed,
                    new List<String>{ String.valueOf(chunksRun), e.getMessage() }
                )
            );
            ErrorLogger.log(e, 'ImportProcessorBatch.execute');
        }
    }

    public void finish(Database.BatchableContext context) {
        try {
            List<String> lines = new List<String>();
            lines.add(
                dryRun ? Label.Core_Import_LogDryRunHeader : Label.Core_Import_LogCommitHeader
            );
            lines.addAll(new List<String>(notes));
            lines.addAll(log);
            ImportBatchService.finish(batchId, dryRun, failed, lines);
        } catch (Exception e) {
            ErrorLogger.log(e, 'ImportProcessorBatch.finish');
        }
    }

    /**
     * Marks every row of a chunk that died as rejected, with the reason. In system mode for
     * the reason ADR-0021 gives: the staged rows are the package's own record of the run and
     * must be written even where the running user cannot edit them.
     */
    private void rejectChunk(List<Import_Row__c> scope, String reason) {
        List<Import_Row__c> rows = new List<Import_Row__c>();
        for (Import_Row__c row : scope) {
            rows.add(
                new Import_Row__c(
                    Id = row.Id,
                    Status__c = ImportRowProcessor.STATUS_REJECTED,
                    Error_Message__c = String.isBlank(reason)
                        ? Label.Core_Import_ErrorSaveFailed
                        : reason.abbreviate(4000)
                )
            );
        }
        if (!rows.isEmpty()) {
            Database.update(rows, false, AccessLevel.SYSTEM_MODE);
        }
    }

    private void addLog(String line) {
        if (log.size() < MAX_LOG_LINES) {
            log.add(line);
        }
    }
}

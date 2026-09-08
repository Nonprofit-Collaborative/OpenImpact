/**
 * The life of one import: created from an uploaded file, staged a chunk at a time, dry run,
 * committed, and finished with counts an administrator can trust.
 *
 * The rules this class exists to keep are R-IB1 and R-IB5. A commit is refused until a dry
 * run of the same file and template has completed, and the counts it reports come from the
 * staged rows themselves, never from a total carried in memory, so what the results screen
 * says is what is actually on the rows.
 */
@NamespaceAccessible
public with sharing class ImportBatchService {
    @NamespaceAccessible
    public static final String STATUS_DRAFT = 'Draft';
    @NamespaceAccessible
    public static final String STATUS_PARSING = 'Parsing';
    @NamespaceAccessible
    public static final String STATUS_DRY_RUN = 'Dry run';
    @NamespaceAccessible
    public static final String STATUS_DRY_RUN_COMPLETE = 'Dry run complete';
    @NamespaceAccessible
    public static final String STATUS_COMMITTING = 'Committing';
    @NamespaceAccessible
    public static final String STATUS_COMPLETE = 'Complete';
    @NamespaceAccessible
    public static final String STATUS_FAILED = 'Failed';
    @NamespaceAccessible
    public static final String STATUS_UNDONE = 'Undone';

    /** The chunk size used when the setting is missing or nonsensical. */
    @NamespaceAccessible
    public static final Integer DEFAULT_CHUNK_SIZE = 200;

    /** The narrowest and widest chunk the platform is asked for. */
    private static final Integer MIN_CHUNK_SIZE = 1;
    private static final Integer MAX_CHUNK_SIZE = 2000;

    /** How long after a commit a batch may still be undone (R-IB6). */
    @NamespaceAccessible
    public static final Integer UNDO_WINDOW_DAYS = 30;

    /**
     * Creates the batch record for one upload. The file has already been stored as a
     * Salesforce File by the component, and its identifier is kept so the original can be
     * downloaded again.
     */
    @NamespaceAccessible
    public static Import_Batch__c create(Id templateId, String fileId, String fileName) {
        Import_Template__c template = ImportTemplateSelector.selectById(templateId);
        if (template == null) {
            throw new ImportException(Label.Core_Import_ErrorTemplateGone);
        }
        Import_Batch__c batch = new Import_Batch__c(
            Import_Template__c = template.Id,
            File_Id__c = String.isBlank(fileId) ? null : fileId.left(18),
            File_Name__c = String.isBlank(fileName) ? null : fileName.abbreviate(255),
            Status__c = STATUS_DRAFT,
            Is_Dry_Run__c = true,
            Row_Count__c = 0,
            Rows_Created__c = 0,
            Rows_Updated__c = 0,
            Rows_Matched__c = 0,
            Rows_Rejected__c = 0,
            Chunk_Size__c = chunkSize()
        );
        Database.insert(batch, AccessLevel.USER_MODE);
        return batch;
    }

    /**
     * Stages one page of the file's rows. The component parses the file in the browser and
     * sends the rows in pages, so a large file never arrives as one request and the staging
     * itself is bulk.
     *
     * @param rows each row's values keyed by the file's column names, in file order
     * @param firstRowNumber the file row number of the first row in this page, counting the
     *        header row as row 1
     * @return how many rows the batch now has
     */
    @NamespaceAccessible
    public static Integer stageRows(
        Id batchId,
        List<Map<String, Object>> rows,
        Integer firstRowNumber
    ) {
        Import_Batch__c batch = ImportBatchSelector.selectById(batchId);
        if (batch == null) {
            throw new ImportException(Label.Core_Import_ErrorBatchGone);
        }
        if (rows == null || rows.isEmpty()) {
            return batch.Row_Count__c == null ? 0 : batch.Row_Count__c.intValue();
        }
        Integer start = firstRowNumber == null || firstRowNumber < 1 ? 1 : firstRowNumber;
        List<Import_Row__c> staged = new List<Import_Row__c>();
        for (Integer i = 0; i < rows.size(); i++) {
            staged.add(
                new Import_Row__c(
                    Import_Batch__c = batch.Id,
                    Row_Number__c = start + i,
                    Raw_Values_JSON__c = JSON.serialize(rows[i]).abbreviate(32768),
                    Status__c = ImportRowProcessor.STATUS_PENDING
                )
            );
        }
        Database.insert(staged, AccessLevel.USER_MODE);
        Integer total =
            (batch.Row_Count__c == null ? 0 : batch.Row_Count__c.intValue()) + staged.size();
        batch.Row_Count__c = total;
        batch.Status__c = STATUS_PARSING;
        Database.update(batch, AccessLevel.USER_MODE);
        return total;
    }

    /**
     * Starts a dry run: every row is reset to pending, nothing is written, and the counts
     * that come back are what a commit would do.
     */
    @NamespaceAccessible
    public static Id startDryRun(Id batchId) {
        return start(batchId, true);
    }

    /**
     * Starts a commit. Refused unless a dry run of this batch has completed (R-IB1), because
     * the preview is the only thing that makes a commit safe to press.
     */
    @NamespaceAccessible
    public static Id startCommit(Id batchId) {
        Import_Batch__c batch = ImportBatchSelector.selectById(batchId);
        if (batch == null) {
            throw new ImportException(Label.Core_Import_ErrorBatchGone);
        }
        if (!STATUS_DRY_RUN_COMPLETE.equals(batch.Status__c)) {
            throw new ImportException(Label.Core_Import_ErrorDryRunFirst);
        }
        return start(batchId, false);
    }

    private static Id start(Id batchId, Boolean dryRun) {
        Import_Batch__c batch = ImportBatchSelector.selectById(batchId);
        if (batch == null) {
            throw new ImportException(Label.Core_Import_ErrorBatchGone);
        }
        Import_Template__c template = ImportTemplateSelector.selectById(batch.Import_Template__c);
        if (template == null) {
            throw new ImportException(Label.Core_Import_ErrorTemplateGone);
        }
        ImportMapping mapping = ImportMapping.parse(
            template.Column_Mapping_JSON__c,
            template.Default_Values_JSON__c
        );
        if (!mapping.identifiesSomebody()) {
            throw new ImportException(Label.Core_Import_ErrorMappingIdentifiesNobody);
        }
        if (batch.Row_Count__c == null || batch.Row_Count__c <= 0) {
            throw new ImportException(Label.Core_Import_ErrorNoRows);
        }
        if (
            ImportTemplateService.isPersonAccountMode(template) &&
            OrgShapeDetector.detect().personAccountRecordTypeIds.isEmpty()
        ) {
            throw new ImportException(Label.Core_Import_ErrorPersonModeUnavailable);
        }
        resetRows(batch.Id);
        batch.Status__c = dryRun ? STATUS_DRY_RUN : STATUS_COMMITTING;
        batch.Is_Dry_Run__c = dryRun;
        batch.Started_At__c = Datetime.now();
        batch.Completed_At__c = null;
        batch.Run_Log__c = null;
        batch.Rows_Created__c = 0;
        batch.Rows_Updated__c = 0;
        batch.Rows_Matched__c = 0;
        batch.Rows_Rejected__c = 0;
        Database.update(batch, AccessLevel.USER_MODE);
        return Database.executeBatch(
            new ImportProcessorBatch(batch.Id, dryRun),
            scopeSize(batch.Chunk_Size__c)
        );
    }

    /**
     * Puts every staged row back to pending, so a re-run reports on the whole file rather
     * than on whatever the last pass happened to leave behind. Runs in system mode for the
     * reason ADR-0021 gives: the staged rows are the package's own bookkeeping.
     */
    @NamespaceAccessible
    public static void resetRows(Id batchId) {
        List<Import_Row__c> rows = Database.queryWithBinds(
            'SELECT Id FROM Import_Row__c WHERE Import_Batch__c = :batchId AND Status__c != :pending',
            new Map<String, Object>{
                'batchId' => batchId,
                'pending' => ImportRowProcessor.STATUS_PENDING
            },
            AccessLevel.SYSTEM_MODE
        );
        if (rows.isEmpty()) {
            return;
        }
        for (Import_Row__c row : rows) {
            row.Status__c = ImportRowProcessor.STATUS_PENDING;
            row.Error_Message__c = null;
        }
        Database.update(rows, false, AccessLevel.SYSTEM_MODE);
    }

    /**
     * Closes a run: counts read back from the rows, the status the run ended in, and the run
     * log. Called from the batch's finish, where the running user may be anyone, so the write
     * is in system mode (ADR-0021) over fields the package owns.
     */
    @NamespaceAccessible
    public static Import_Batch__c finish(
        Id batchId,
        Boolean dryRun,
        Boolean failed,
        List<String> logLines
    ) {
        Import_Batch__c batch = ImportBatchSelector.selectById(batchId);
        if (batch == null) {
            return null;
        }
        Map<String, Integer> counts = ImportBatchSelector.countRowsByStatus(batchId);
        batch.Rows_Created__c = count(counts, ImportRowProcessor.STATUS_CREATED);
        batch.Rows_Updated__c = count(counts, ImportRowProcessor.STATUS_UPDATED);
        batch.Rows_Matched__c = count(counts, ImportRowProcessor.STATUS_MATCHED);
        batch.Rows_Rejected__c = count(counts, ImportRowProcessor.STATUS_REJECTED);
        batch.Completed_At__c = Datetime.now();
        batch.Run_Log__c = String.join(logLines == null ? new List<String>() : logLines, '\n')
            .abbreviate(32768);
        if (failed == true) {
            batch.Status__c = STATUS_FAILED;
        } else if (dryRun == true) {
            batch.Status__c = STATUS_DRY_RUN_COMPLETE;
        } else {
            batch.Status__c = STATUS_COMPLETE;
            batch.Committed_By__c = UserInfo.getUserId();
            batch.Undo_Deadline__c = Datetime.now().addDays(UNDO_WINDOW_DAYS);
        }
        Database.update(batch, AccessLevel.SYSTEM_MODE);
        if (failed != true && dryRun != true) {
            ImportTemplateService.recordImport(batch.Import_Template__c, Date.today());
        }
        return batch;
    }

    /** The org's chunk size, clamped to something the platform will accept. */
    @NamespaceAccessible
    public static Integer chunkSize() {
        Object configured = SettingsService.hasKey('Import_Chunk_Size__c')
            ? SettingsService.getValue('Import_Chunk_Size__c')
            : null;
        if (configured == null) {
            return DEFAULT_CHUNK_SIZE;
        }
        try {
            return scopeSize(Decimal.valueOf(String.valueOf(configured)));
        } catch (Exception ignored) {
            return DEFAULT_CHUNK_SIZE;
        }
    }

    private static Integer scopeSize(Decimal configured) {
        if (configured == null || configured < MIN_CHUNK_SIZE) {
            return DEFAULT_CHUNK_SIZE;
        }
        return (Integer) Math.min(configured.intValue(), MAX_CHUNK_SIZE);
    }

    private static Integer count(Map<String, Integer> counts, String status) {
        Integer found = counts.get(status);
        return found == null ? 0 : found;
    }
}

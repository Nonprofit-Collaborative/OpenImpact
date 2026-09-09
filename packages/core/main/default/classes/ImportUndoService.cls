/**
 * Undoing one import (C-19, canonical model R-IB7 to R-IB9).
 *
 * This is the most dangerous code in the package, and it is written to be boring on purpose.
 * A project this one learned from lost 440 contacts and 225 accounts to a cleanup query that
 * filtered on a flag, so the rules here are not style preferences:
 *
 * 1. **One batch, named by its identifier.** Every query is filtered by
 *    `Created_By_Import_Batch__c = :batchId` where batchId is one bound identifier. There is
 *    no query in this class or in `ImportUndoBatch` filtered by a checkbox, a date, a status,
 *    a name or a user, and no undo of more than one batch at a time. A blank identifier is
 *    refused rather than treated as "everything".
 * 2. **Counted, shown, then confirmed.** `preview` counts what carries the tag and returns
 *    those numbers. `start` refuses unless the caller passes back the number it was shown, so
 *    an undo can only delete a set somebody has actually seen the size of.
 * 3. **Once.** The latch is `Undo_Started_At__c`, written inside a locked read of the batch,
 *    so a second request is refused rather than queued.
 * 4. **Only what the import created.** The tag is written when a record is inserted and never
 *    afterwards, so a record the import matched or merely updated cannot be in scope. Updates
 *    are journaled, not reversed (R-IB9).
 *
 * Records are deleted, not destroyed: nothing here empties the recycle bin.
 */
@NamespaceAccessible
public with sharing class ImportUndoService {
    /** What an undo would do, or why it cannot be done. */
    @NamespaceAccessible
    public class UndoPreview {
        @NamespaceAccessible
        public Boolean allowed = false;
        /** In plain language, why an undo is refused. Empty when it is allowed. */
        @NamespaceAccessible
        public String reason;
        @NamespaceAccessible
        public String batchId;
        @NamespaceAccessible
        public String batchName;
        @NamespaceAccessible
        public String fileName;
        @NamespaceAccessible
        public Integer people = 0;
        @NamespaceAccessible
        public Integer accounts = 0;
        @NamespaceAccessible
        public Integer total = 0;
        @NamespaceAccessible
        public Datetime deadline;
        /** Entities this import staged that Core cannot delete, named for the screen. */
        @NamespaceAccessible
        public String notReversed;
    }

    /**
     * Counts what an undo of this batch would delete, without deleting anything.
     *
     * The counts come from the tag on the records themselves rather than from the batch's
     * own counters, because the counters say what the run did and this has to say what is
     * there now.
     */
    @NamespaceAccessible
    public static UndoPreview preview(Id batchId) {
        UndoPreview view = new UndoPreview();
        if (batchId == null) {
            view.reason = Label.Core_Import_UndoErrorBatchGone;
            return view;
        }
        Import_Batch__c batch = ImportBatchSelector.selectById(batchId);
        if (batch == null) {
            view.reason = Label.Core_Import_UndoErrorBatchGone;
            return view;
        }
        view.batchId = batch.Id;
        view.batchName = batch.Name;
        view.fileName = batch.File_Name__c;
        view.deadline = batch.Undo_Deadline__c;
        view.people = countTagged('Contact', batch.Id);
        view.accounts = countTagged('Account', batch.Id);
        view.total = view.people + view.accounts;
        view.notReversed = deferredEntities(batch);
        view.reason = refusal(batch);
        view.allowed = String.isBlank(view.reason);
        if (view.allowed && view.total == 0) {
            view.allowed = false;
            view.reason = Label.Core_Import_UndoErrorNothingToUndo;
        }
        return view;
    }

    /**
     * Starts the undo of one batch, after checking every guard again. The count the caller
     * passes is the count `preview` gave it: an undo of a set that has changed size since it
     * was shown is refused and counted again rather than run (R-IB8).
     *
     * @return the identifier of the batch job doing the deleting
     */
    @NamespaceAccessible
    public static Id start(Id batchId, Integer confirmedCount) {
        UndoPreview view = preview(batchId);
        if (!view.allowed) {
            throw new ImportException(view.reason);
        }
        if (confirmedCount == null || confirmedCount != view.total) {
            throw new ImportException(
                String.format(
                    Label.Core_Import_UndoErrorCountChanged,
                    new List<String>{
                        String.valueOf(confirmedCount == null ? 0 : confirmedCount),
                        String.valueOf(view.total)
                    }
                )
            );
        }
        Import_Batch__c locked = latch(batchId);
        Integer scope = locked.Chunk_Size__c == null
            ? ImportBatchService.DEFAULT_CHUNK_SIZE
            : Math.max(1, Math.min(locked.Chunk_Size__c.intValue(), 200));
        return Database.executeBatch(new ImportUndoBatch(batchId), scope);
    }

    /**
     * Takes the once-only latch inside a locked read, so two people pressing Undo at the same
     * moment produce one undo and one refusal rather than two undos.
     */
    private static Import_Batch__c latch(Id batchId) {
        Import_Batch__c batch = [
            SELECT Id, Status__c, Is_Dry_Run__c, Undo_Deadline__c, Undo_Started_At__c, Chunk_Size__c
            FROM Import_Batch__c
            WHERE Id = :batchId
            WITH SYSTEM_MODE
            LIMIT 1
            FOR UPDATE
        ];
        String refused = refusal(batch);
        if (String.isNotBlank(refused)) {
            throw new ImportException(refused);
        }
        batch.Undo_Started_At__c = Datetime.now();
        batch.Status__c = ImportBatchService.STATUS_UNDOING;
        Database.update(batch, AccessLevel.SYSTEM_MODE);
        return batch;
    }

    /**
     * Closes an undo: what it deleted, what it kept, and the status it ended in. Called from
     * the batch job's finish, where the running user may be anyone, so the write is in system
     * mode over fields the package owns (ADR-0021).
     */
    @NamespaceAccessible
    public static void finish(Id batchId, Integer deleted, Integer kept, Boolean failed) {
        try {
            Import_Batch__c batch = new Import_Batch__c(
                Id = batchId,
                Records_Deleted__c = deleted == null ? 0 : deleted,
                Records_Kept__c = kept == null ? 0 : kept,
                Undone_At__c = Datetime.now(),
                Undone_By__c = UserInfo.getUserId(),
                Status__c = failed == true
                    ? ImportBatchService.STATUS_UNDO_FAILED
                    : ImportBatchService.STATUS_UNDONE
            );
            Database.update(batch, AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            ErrorLogger.log(e, 'ImportUndoService.finish', batchId);
        }
    }

    /**
     * Why this batch cannot be undone, or blank when it can. Every sentence names what is
     * wrong and what to do about it, because "undo is not available" tells an administrator
     * nothing.
     */
    @NamespaceAccessible
    public static String refusal(Import_Batch__c batch) {
        if (batch == null) {
            return Label.Core_Import_UndoErrorBatchGone;
        }
        if (batch.Is_Dry_Run__c == true) {
            return Label.Core_Import_UndoErrorDryRun;
        }
        if (
            ImportBatchService.STATUS_UNDONE.equals(batch.Status__c) ||
            ImportBatchService.STATUS_UNDOING.equals(batch.Status__c) ||
            batch.Undo_Started_At__c != null
        ) {
            return Label.Core_Import_UndoErrorAlreadyUndone;
        }
        if (
            !ImportBatchService.STATUS_COMPLETE.equals(batch.Status__c) &&
            !ImportBatchService.STATUS_FAILED.equals(batch.Status__c) &&
            !ImportBatchService.STATUS_UNDO_FAILED.equals(batch.Status__c)
        ) {
            return Label.Core_Import_UndoErrorNotCommitted;
        }
        if (batch.Undo_Deadline__c == null) {
            return Label.Core_Import_UndoErrorNoDeadline;
        }
        if (batch.Undo_Deadline__c < Datetime.now()) {
            return String.format(
                Label.Core_Import_UndoErrorWindowClosed,
                new List<String>{ batch.Undo_Deadline__c.format() }
            );
        }
        return null;
    }

    /**
     * The entities this import staged that Core does not create and therefore cannot remove
     * (R-IR6, R-IB9), named so the screen can say what an undo does not cover rather than
     * implying a clean reversal. Blank when the mapping loaded nothing but people,
     * households and organizations, which is every mapping Core ships today.
     */
    private static String deferredEntities(Import_Batch__c batch) {
        try {
            Import_Template__c template = ImportTemplateSelector.selectById(
                batch.Import_Template__c
            );
            if (template == null) {
                return null;
            }
            Set<String> deferred = ImportMapping.parse(
                    template.Column_Mapping_JSON__c,
                    template.Default_Values_JSON__c
                )
                .deferredEntities();
            return deferred.isEmpty() ? null : String.join(new List<String>(deferred), ', ');
        } catch (Exception ignored) {
            // A mapping that cannot be read does not stop an undo of the records it created.
            return null;
        }
    }

    /**
     * How many records of one object carry this batch's tag.
     *
     * The object name is one of two literals chosen here, never a value from a caller, and
     * the filter is the bound batch identifier and nothing else.
     */
    @NamespaceAccessible
    public static Integer countTagged(String objectName, Id batchId) {
        if (batchId == null) {
            return 0;
        }
        String from = 'Contact'.equals(objectName) ? 'Contact' : 'Account';
        List<AggregateResult> counted = Database.queryWithBinds(
            'SELECT COUNT(Id) total FROM ' +
            from +
            ' WHERE Created_By_Import_Batch__c = :batchId',
            new Map<String, Object>{ 'batchId' => batchId },
            AccessLevel.SYSTEM_MODE
        );
        return counted.isEmpty() ? 0 : (Integer) counted[0].get('total');
    }
}

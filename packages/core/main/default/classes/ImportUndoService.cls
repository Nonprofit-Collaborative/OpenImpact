/**
 * Undoing one import (C-19, canonical model R-IB7 to R-IB9).
 *
 * This deletes records, so it is written to be boring. The rules it keeps are not style:
 *
 * 1. **One batch, named by its identifier.** Every count and every delete is filtered by the
 *    Created By Import Batch reference equal to one bound identifier. Nothing is filtered by a
 *    flag, a date, a status, a name or a user, and a blank identifier is refused rather than
 *    read as "everything".
 * 2. **Counted, shown, then confirmed.** `preview` counts what carries the tag. `start`
 *    refuses unless it is handed back the number it would count now, so an undo only ever
 *    deletes a set somebody has seen the size of.
 * 3. **Once.** The status moves to Undoing inside a locked read of the batch, so a second
 *    request is refused rather than queued.
 * 4. **Deleted, not destroyed.** Nothing here empties the recycle bin.
 *
 * The work itself is `ImportUndoBatch`.
 */
@NamespaceAccessible
public with sharing class ImportUndoService {
    /** What an undo would do, or why it cannot be done. */
    @NamespaceAccessible
    public class Preview {
        @AuraEnabled
        public Boolean allowed = false;
        /** Why an undo is refused, in a sentence an administrator can act on. */
        @AuraEnabled
        public String reason;
        @AuraEnabled
        public Integer people = 0;
        @AuraEnabled
        public Integer households = 0;
        @AuraEnabled
        public Integer organizations = 0;
        /** The records an undo would delete: the number the person confirms. */
        @AuraEnabled
        public Integer total = 0;
        /** The updates the journal holds, which an undo puts back where nobody changed them. */
        @AuraEnabled
        public Integer updates = 0;
    }

    /**
     * Counts what an undo of this batch would delete and put back, deleting nothing. The
     * counts come from the tag on the records themselves, not from the batch's row counters,
     * because this has to say what is there now rather than what the run did.
     */
    @NamespaceAccessible
    public static Preview preview(Id batchId) {
        Preview view = new Preview();
        Import_Batch__c batch = ImportBatchSelector.selectById(batchId);
        view.reason = refusal(batch);
        if (batch == null) {
            return view;
        }
        countTagged(batch.Id, view);
        view.updates = ImportJournalService.entryCount(batch.Id, ImportJournalService.PHASE_COMMIT);
        if (String.isBlank(view.reason) && view.total == 0 && view.updates == 0) {
            view.reason = Label.Core_Import_UndoErrorNothingToUndo;
        }
        view.allowed = String.isBlank(view.reason);
        return view;
    }

    /**
     * Starts the undo of one batch after checking every guard again. `confirmedTotal` is the
     * total the person was shown: a set that has changed size since is refused, and counted
     * again, rather than deleted (R-IB8).
     *
     * @return the identifier of the job doing the work
     */
    @NamespaceAccessible
    public static Id start(Id batchId, Integer confirmedTotal) {
        Preview view = preview(batchId);
        if (!view.allowed) {
            throw new ImportException(view.reason);
        }
        if (confirmedTotal != view.total) {
            throw new ImportException(
                String.format(
                    Label.Core_Import_UndoErrorCountChanged,
                    new List<String>{
                        String.valueOf(confirmedTotal == null ? 0 : confirmedTotal),
                        String.valueOf(view.total)
                    }
                )
            );
        }
        latch(batchId);
        return ImportUndoBatch.run(batchId, view.total);
    }

    /**
     * Takes the once-only latch inside a locked read, so two people pressing Undo at the same
     * moment produce one undo and one refusal. The status is the package's own bookkeeping,
     * written in system mode (ADR-0021).
     */
    private static void latch(Id batchId) {
        Import_Batch__c batch = [
            SELECT Id, Status__c, Is_Dry_Run__c, Undo_Deadline__c, Completed_At__c
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
        batch.Status__c = ImportBatchService.STATUS_UNDOING;
        Database.update(batch, AccessLevel.SYSTEM_MODE);
    }

    /**
     * Closes an undo: its status, and one line added to the run log saying who ran it, when,
     * and what it deleted, kept and put back. Called from the job's last finish, in system
     * mode over fields the package owns (ADR-0021).
     */
    @NamespaceAccessible
    public static void finish(
        Id batchId,
        Integer countedAtStart,
        Integer restored,
        Boolean failed
    ) {
        try {
            Preview left = new Preview();
            countTagged(batchId, left);
            Integer counted = countedAtStart == null ? 0 : countedAtStart;
            Import_Batch__c batch = [
                SELECT Id, Run_Log__c
                FROM Import_Batch__c
                WHERE Id = :batchId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            String line = String.format(
                Label.Core_Import_LogUndone,
                new List<String>{
                    UserInfo.getName(),
                    Datetime.now().format(),
                    String.valueOf(Math.max(counted - left.total, 0)),
                    String.valueOf(left.total),
                    String.valueOf(restored == null ? 0 : restored)
                }
            );
            batch.Run_Log__c = (String.isBlank(batch.Run_Log__c)
                    ? line
                    : batch.Run_Log__c + '\n' + line)
                .right(32768);
            batch.Status__c = failed == true
                ? ImportBatchService.STATUS_UNDO_FAILED
                : ImportBatchService.STATUS_UNDONE;
            Database.update(batch, AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            ErrorLogger.log(e, 'ImportUndoService.finish', batchId);
        }
    }

    /**
     * Why this batch cannot be undone, or blank when it can. A commit that failed part way is
     * undoable, because the chunks that ran did write (R-IB7), and so is an undo that stopped
     * on an error, because running it again only finishes it (R-IB8).
     */
    @NamespaceAccessible
    public static String refusal(Import_Batch__c batch) {
        if (batch == null) {
            return Label.Core_Import_ErrorBatchGone;
        }
        if (batch.Is_Dry_Run__c == true) {
            return Label.Core_Import_UndoErrorDryRun;
        }
        if (
            ImportBatchService.STATUS_UNDOING.equals(batch.Status__c) ||
            ImportBatchService.STATUS_UNDONE.equals(batch.Status__c)
        ) {
            return Label.Core_Import_UndoErrorAlreadyUndone;
        }
        if (
            !(ImportBatchService.STATUS_COMPLETE.equals(batch.Status__c) ||
            ImportBatchService.STATUS_FAILED.equals(batch.Status__c) ||
            ImportBatchService.STATUS_UNDO_FAILED.equals(batch.Status__c)) ||
            batch.Undo_Deadline__c == null ||
            batch.Completed_At__c == null
        ) {
            return Label.Core_Import_UndoErrorNotCommitted;
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
     * Counts the records carrying this batch's tag, by kind. People stored as accounts are
     * counted as people. Read in system mode (ADR-0021): the count has to include records the
     * running user cannot see, because an undo that says "nothing to delete" about records it
     * merely cannot see has told the administrator something false.
     */
    private static void countTagged(Id batchId, Preview view) {
        if (batchId == null) {
            return;
        }
        view.people = [
            SELECT COUNT()
            FROM Contact
            WHERE Created_By_Import_Batch__c = :batchId
            WITH SYSTEM_MODE
        ];
        Set<Id> personTypes = OrgShapeDetector.detect().personAccountRecordTypeIds;
        Id householdType = HouseholdService.householdRecordTypeId();
        for (AggregateResult counted : [
            SELECT RecordTypeId recordType, COUNT(Id) total
            FROM Account
            WHERE Created_By_Import_Batch__c = :batchId
            WITH SYSTEM_MODE
            GROUP BY RecordTypeId
        ]) {
            Id recordType = (Id) counted.get('recordType');
            Integer total = (Integer) counted.get('total');
            if (recordType != null && personTypes.contains(recordType)) {
                view.people += total;
            } else if (recordType != null && recordType == householdType) {
                view.households += total;
            } else {
                view.organizations += total;
            }
        }
        view.total = view.people + view.households + view.organizations;
    }
}

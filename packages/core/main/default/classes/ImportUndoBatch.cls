/**
 * Deletes what one import created, in two passes, and journals every record it deletes and
 * every record it deliberately keeps (canonical model R-IB8, R-IB9).
 *
 * People first, then accounts. That order matters: deleting an account takes its contacts
 * with it, so the people this import created are removed on their own terms in pass one, and
 * pass two can then tell the difference between a household that is empty because its only
 * members came from this import and a household somebody has since added a person to. The
 * second is kept, because the import's records are not worth another person's.
 *
 * Every query here is filtered by one bound batch identifier. There is no flag, no date and
 * no status in any filter, and the identifier is checked again on every record before it is
 * deleted, so a query that somehow returned a wider set still deletes nothing outside the
 * batch.
 */
public with sharing class ImportUndoBatch implements Database.Batchable<SObject>, Database.Stateful {
    @TestVisible
    private static final String PASS_PEOPLE = 'Contact';
    @TestVisible
    private static final String PASS_ACCOUNTS = 'Account';

    private final Id batchId;
    private final String pass;
    private Integer deleted;
    private Integer kept;
    private Boolean failed;

    public ImportUndoBatch(Id batchId) {
        this(batchId, PASS_PEOPLE, 0, 0, false);
    }

    private ImportUndoBatch(
        Id batchId,
        String pass,
        Integer deleted,
        Integer kept,
        Boolean failed
    ) {
        this.batchId = batchId;
        this.pass = pass;
        this.deleted = deleted;
        this.kept = kept;
        this.failed = failed;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        Id owner = batchId;
        if (PASS_ACCOUNTS.equals(pass)) {
            return Database.getQueryLocator(
                [
                    SELECT Id, Name, RecordTypeId, Created_By_Import_Batch__c
                    FROM Account
                    WHERE Created_By_Import_Batch__c = :owner
                ]
            );
        }
        return Database.getQueryLocator(
            [
                SELECT Id, Name, Created_By_Import_Batch__c
                FROM Contact
                WHERE Created_By_Import_Batch__c = :owner
            ]
        );
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        try {
            List<ImportJournalService.Entry> journal = new List<ImportJournalService.Entry>();
            List<SObject> toDelete = PASS_ACCOUNTS.equals(pass)
                ? accountsToDelete(scope, journal)
                : peopleToDelete(scope);
            deleteAll(toDelete, journal);
            ImportJournalService.writePage(batchId, ImportJournalService.PHASE_UNDO, journal);
        } catch (Exception e) {
            failed = true;
            ErrorLogger.log(e, 'ImportUndoBatch.execute', batchId);
        }
    }

    public void finish(Database.BatchableContext context) {
        try {
            if (PASS_PEOPLE.equals(pass)) {
                Database.executeBatch(
                    new ImportUndoBatch(batchId, PASS_ACCOUNTS, deleted, kept, failed),
                    scopeSize()
                );
                return;
            }
            ImportUndoService.finish(batchId, deleted, kept, failed);
        } catch (Exception e) {
            ErrorLogger.log(e, 'ImportUndoBatch.finish', batchId);
            ImportUndoService.finish(batchId, deleted, kept, true);
        }
    }

    /**
     * The people to delete. Every one is checked against the batch identifier again before it
     * joins the list: the belt to the query's braces, and the reason no record outside this
     * import can reach the delete.
     */
    private List<SObject> peopleToDelete(List<SObject> scope) {
        List<SObject> toDelete = new List<SObject>();
        for (SObject record : scope) {
            if (!tagged(record)) {
                continue;
            }
            toDelete.add(record);
        }
        return toDelete;
    }

    /**
     * The accounts to delete, and the reasons for the ones kept. A household or organization
     * that still has a person on it, or a membership naming somebody this import did not
     * create, is kept: deleting it would take that person with it.
     *
     * A person stored as an account is judged only by the tag. Its own contact is itself, not
     * somebody else, so the child check that protects a household would keep every person
     * account forever.
     */
    private List<SObject> accountsToDelete(
        List<SObject> scope,
        List<ImportJournalService.Entry> journal
    ) {
        Set<Id> ids = new Set<Id>();
        for (SObject record : scope) {
            if (tagged(record)) {
                ids.add((Id) record.get('Id'));
            }
        }
        List<SObject> toDelete = new List<SObject>();
        if (ids.isEmpty()) {
            return toDelete;
        }
        Set<Id> personRecordTypes = OrgShapeDetector.detect().personAccountRecordTypeIds;
        for (
            Account account : [
                SELECT
                    Id,
                    Name,
                    RecordTypeId,
                    Created_By_Import_Batch__c,
                    (SELECT Id FROM Contacts LIMIT 1),
                    (SELECT Id, Contact__c, Account__c FROM Household_Members__r LIMIT 50)
                FROM Account
                WHERE Id IN :ids
                WITH SYSTEM_MODE
            ]
        ) {
            if (account.Created_By_Import_Batch__c != batchId) {
                continue;
            }
            Boolean isPerson =
                account.RecordTypeId != null && personRecordTypes.contains(account.RecordTypeId);
            String keepReason = isPerson ? null : reasonToKeep(account);
            if (String.isBlank(keepReason)) {
                toDelete.add(account);
                continue;
            }
            kept++;
            journal.add(
                new ImportJournalService.Entry(null, ImportJournalService.ACTION_KEPT)
                    .on('Account', account.Id, account.Name)
                    .because(keepReason)
            );
        }
        return toDelete;
    }

    /** Why this account is not the import's to remove, or blank when it is. */
    private String reasonToKeep(Account account) {
        if (account.Contacts != null && !account.Contacts.isEmpty()) {
            return Label.Core_Import_UndoKeptHasPeople;
        }
        for (Household_Member__c member : account.Household_Members__r) {
            if (member.Contact__c != null || member.Account__c != null) {
                return Label.Core_Import_UndoKeptHasMembers;
            }
        }
        return null;
    }

    /**
     * Deletes with partial success, in the running user's own mode: these are the
     * organization's records, not the package's bookkeeping, so a user who may not delete a
     * contact does not delete one here either (ADR-0021). Nothing empties the recycle bin, so
     * a mistaken undo is recoverable.
     */
    private void deleteAll(List<SObject> records, List<ImportJournalService.Entry> journal) {
        if (records.isEmpty()) {
            return;
        }
        List<Database.DeleteResult> results = Database.delete(
            records,
            false,
            AccessLevel.USER_MODE
        );
        for (Integer i = 0; i < results.size(); i++) {
            SObject record = records[i];
            String label = String.valueOf(record.get('Name'));
            if (results[i].isSuccess()) {
                deleted++;
                journal.add(
                    new ImportJournalService.Entry(null, ImportJournalService.ACTION_DELETED)
                        .on(pass, (Id) record.get('Id'), label)
                );
                continue;
            }
            // A record the platform refuses to delete is kept and said so, never retried in a
            // wider or more forceful form.
            kept++;
            failed = true;
            journal.add(
                new ImportJournalService.Entry(null, ImportJournalService.ACTION_KEPT)
                    .on(pass, (Id) record.get('Id'), label)
                    .because(message(results[i]))
            );
        }
    }

    private Boolean tagged(SObject record) {
        return batchId == record.get('Created_By_Import_Batch__c');
    }

    private Integer scopeSize() {
        Import_Batch__c batch = ImportBatchSelector.selectById(batchId);
        if (batch == null || batch.Chunk_Size__c == null) {
            return ImportBatchService.DEFAULT_CHUNK_SIZE;
        }
        return Math.max(1, Math.min(batch.Chunk_Size__c.intValue(), 200));
    }

    private String message(Database.DeleteResult result) {
        List<String> parts = new List<String>();
        for (Database.Error error : result.getErrors()) {
            parts.add(error.getMessage());
        }
        return parts.isEmpty() ? Label.Core_Import_UndoKeptNotDeletable : String.join(parts, ' ');
    }
}

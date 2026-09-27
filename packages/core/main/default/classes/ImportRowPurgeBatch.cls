/**
 * Deletes a committed import's staged rows, except the rejected ones (canonical model R-IB15,
 * R-IR5; plan Section 4.9, "Staging only where it earns its storage").
 *
 * Started from the commit's finish, once the batch's counts have been read from the rows. A
 * quarter of a million rows are more than one transaction may delete, so this is a batch job of
 * its own rather than part of the finish. The rejected rows stay with the batch for the undo
 * window, so the exceptions file can still be downloaded; undo never reads the rows (R-IB9).
 *
 * Every query and delete is filtered by the one batch identifier and a status other than
 * Rejected, and nothing else. The rows are the package's own bookkeeping, so they are read and
 * deleted in system mode (ADR-0021). A chunk that fails is logged and leaves its rows, which
 * cost only storage; nothing here can change a record the import loaded.
 */
public with sharing class ImportRowPurgeBatch implements Database.Batchable<SObject> {
    /** How many rows one delete takes. */
    public static final Integer SCOPE = 2000;

    private final Id batchId;

    public ImportRowPurgeBatch(Id batchId) {
        this.batchId = batchId;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        Id owner = batchId;
        String rejected = ImportRowProcessor.STATUS_REJECTED;
        // A blank identifier reads nothing, never "every batch".
        return Database.getQueryLocator(
            [
                SELECT Id, Import_Batch__c
                FROM Import_Row__c
                WHERE
                    Import_Batch__c = :owner
                    AND Import_Batch__c != NULL
                    AND Status__c != :rejected
                WITH SYSTEM_MODE
            ]
        );
    }

    public void execute(Database.BatchableContext context, List<Import_Row__c> scope) {
        List<Import_Row__c> rows = new List<Import_Row__c>();
        for (Import_Row__c row : scope) {
            // Checked again on each row: only this batch's, and never a rejected one.
            if (row.Import_Batch__c == batchId) {
                rows.add(new Import_Row__c(Id = row.Id));
            }
        }
        if (rows.isEmpty()) {
            return;
        }
        try {
            Database.delete(rows, false, AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            ErrorLogger.log(e, 'ImportRowPurgeBatch.execute', batchId);
        }
    }

    public void finish(Database.BatchableContext context) {
        return;
    }
}

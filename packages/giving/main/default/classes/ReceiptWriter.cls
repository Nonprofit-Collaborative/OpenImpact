/**
 * Every write the receipting feature makes to package owned receipt data.
 *
 * DOCUMENTED EXCEPTION to the "user mode DML" rule (plan Section 4.13), under ADR-0021.
 *
 * ADR-0016 says issued receipts and their files are read only to everyone, and the packaged
 * permission sets say so: no role, including Nonprofit Admin, holds Create, Edit or Delete on
 * `Receipt__c`, `Receipt_Run__c` or `Receipt_Number_Sequence__c`. A user mode write would
 * therefore fail for every user in every org, including the one issuing the receipt. The package
 * writes these records; a person never does, which is the point.
 *
 * The four ADR-0021 conditions:
 *
 * 1. **Permission enforced before this class is reached.** `ReceiptService` and `ReceiptController`
 *    check `Issue_Receipts` before any call here.
 * 2. **Inputs validated by the caller.** Every field written is computed by package code from
 *    records the running user was already allowed to read: amounts from gifts, numbers from the
 *    sequence, dates from the clock. The only user typed text that reaches a record is a void
 *    reason, which is stored and never used in a query or a dynamic field name.
 * 3. **Only package owned fields.** The gift's receipt number is written by `ReceiptService` in
 *    user mode, not here, because the gift is the running user's record to save.
 * 4. **Reads that reach a user stay in user mode.** `ReceiptSelector` runs `WITH USER_MODE`, so
 *    what a person sees on screen is what their sharing lets them see. The reads in this class are
 *    upkeep: they exist to write the next value, never to display one.
 *
 * `without sharing` rather than `with sharing`: a year end run issues documents for donors the
 * running user may not personally be able to see, and a receipt that quietly did not get issued is
 * worse than one issued by an administrator who cannot open it.
 */
public without sharing class ReceiptWriter {
    public static void insertReceipts(List<Receipt__c> receipts) {
        if (receipts == null || receipts.isEmpty()) {
            return;
        }
        Database.insert(receipts, true, AccessLevel.SYSTEM_MODE);
    }

    public static void updateReceipts(List<Receipt__c> receipts) {
        if (receipts == null || receipts.isEmpty()) {
            return;
        }
        Database.update(receipts, true, AccessLevel.SYSTEM_MODE);
    }

    public static void insertRun(Receipt_Run__c run) {
        Database.insert(new List<Receipt_Run__c>{ run }, true, AccessLevel.SYSTEM_MODE);
    }

    public static void updateRun(Receipt_Run__c run) {
        Database.update(new List<Receipt_Run__c>{ run }, true, AccessLevel.SYSTEM_MODE);
    }

    public static void insertSequence(Receipt_Number_Sequence__c sequence) {
        Database.insert(
            new List<Receipt_Number_Sequence__c>{ sequence },
            true,
            AccessLevel.SYSTEM_MODE
        );
    }

    public static void updateSequence(Receipt_Number_Sequence__c sequence) {
        Database.update(
            new List<Receipt_Number_Sequence__c>{ sequence },
            true,
            AccessLevel.SYSTEM_MODE
        );
    }

    /**
     * Stores one rendered document and links it where ADR-0016 says it belongs: to the receipt
     * always, and to the gift and the donor per receipt type. Returns the ContentDocumentId, which
     * the receipt record keeps so that the record and its file find each other without a query on
     * the link table.
     *
     * The bytes are passed in and dropped on return: nothing here holds a PDF beyond the call,
     * which is what keeps a batch chunk inside the async heap limit.
     */
    public static Id storeDocument(String title, Blob bytes, List<Id> linkTo) {
        ContentVersion version = new ContentVersion(
            Title = title,
            PathOnClient = title + '.pdf',
            VersionData = bytes,
            Origin = 'H'
        );
        Database.insert(new List<ContentVersion>{ version }, true, AccessLevel.SYSTEM_MODE);

        Id documentId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            WITH SYSTEM_MODE
            LIMIT 1
        ]
        .ContentDocumentId;

        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        Set<Id> seen = new Set<Id>();
        for (Id target : linkTo) {
            if (target == null || !seen.add(target)) {
                continue;
            }
            links.add(
                new ContentDocumentLink(
                    ContentDocumentId = documentId,
                    LinkedEntityId = target,
                    ShareType = 'V',
                    Visibility = 'AllUsers'
                )
            );
        }
        if (!links.isEmpty()) {
            Database.insert(links, true, AccessLevel.SYSTEM_MODE);
        }
        return documentId;
    }
}

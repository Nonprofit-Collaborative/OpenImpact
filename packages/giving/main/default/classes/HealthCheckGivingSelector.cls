/**
 * The read behind the Health Check finding for unposted gifts in a closed period (G-20
 * follow-up, ADR-0053, ADR-0021). Gifts the lock already treats as in the books (ADR-0022,
 * `GiftPostingLock.BOOK_STATUSES` and `TYPE_IN_KIND`), dated on or before the close date, that
 * nothing has ever marked posted.
 *
 * `without sharing` and `WITH SYSTEM_MODE`, the same pair `GiftImportIntegritySelector` uses and
 * for the same reason: this is a fact about the org, not about what the viewer may see. Gift__c
 * ships Private (R-G14), and a Health Check finding that silently under-counts for an
 * administrator who does not happen to own or share every gift is a wrong answer, not a
 * narrower one. `WITH SYSTEM_MODE` alone would not have reached every gift here: it lifts field
 * and object security, but sharing is decided by the class keyword, not the query clause, so the
 * class itself has to give up sharing. The access control that actually matters is
 * `HealthCheckService.canManageSettings()`, which gates the finding before this selector is ever
 * called; nothing here is reachable by a viewer who may not manage settings.
 */
public without sharing class HealthCheckGivingSelector {
    /** How many gifts are in the books, dated in a closed period, and not yet posted. Capped. */
    public static Integer countUnpostedInClosedPeriod(Date closed, Integer cap) {
        if (closed == null) {
            return 0;
        }
        return [
            SELECT COUNT()
            FROM Gift__c
            WHERE
                Status__c IN :GiftPostingLock.BOOK_STATUSES
                AND Type__c != :GiftPostingLock.TYPE_IN_KIND
                AND Gift_Date__c <= :closed
                AND Accounting_Posted_At__c = NULL
            WITH SYSTEM_MODE
            LIMIT :cap
        ];
    }

    /** The earliest-dated of those gifts, to link a few examples. */
    public static List<Gift__c> unpostedInClosedPeriod(Date closed, Integer howMany) {
        if (closed == null) {
            return new List<Gift__c>();
        }
        return [
            SELECT Id, Name, Gift_Date__c
            FROM Gift__c
            WHERE
                Status__c IN :GiftPostingLock.BOOK_STATUSES
                AND Type__c != :GiftPostingLock.TYPE_IN_KIND
                AND Gift_Date__c <= :closed
                AND Accounting_Posted_At__c = NULL
            WITH SYSTEM_MODE
            ORDER BY Gift_Date__c ASC, Id ASC
            LIMIT :howMany
        ];
    }
}

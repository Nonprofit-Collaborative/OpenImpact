/**
 * The queries behind the Gift Transaction mirror (feature X-07, canonical model Section 29D).
 * Every one runs in user mode: a run reads and writes with the access of the person who started
 * or scheduled it, so a record they cannot see is a record the mirror does not touch.
 *
 * The Gift Transaction object is never named here. Its queries are built from the object name
 * and field names `GiftTransactionMirrorSchema` resolved through describe, so Connect compiles and
 * installs where Nonprofit Cloud does not exist, and no query is made there (R-GT1).
 */
public with sharing class GiftTransactionMirrorSelector {
    /** The gift attributes R-GT3 and R-GT4 read, plus the link. */
    public static final String GIFT_FIELDS = 'Id, Name, Amount__c, Gift_Date__c, Status__c, Type__c, Donor_Account__c, Household__c, Gift_Transaction_Id__c';

    /**
     * The gifts a Gifts to Gift Transactions run copies (R-GT3, R-GT5), as a query binding
     * `statuses`, `inKind` and `startDate`. Without a range: those with no Gift Transaction, and,
     * when `sinceLastRun`, the linked ones changed since the last completed run started (bind
     * `since`). Given a range (binds `fromDate`, `toDate`): every one dated in it, linked or not.
     */
    public static String giftsToCopyQuery(Boolean inRange, Boolean sinceLastRun) {
        String query =
            'SELECT ' +
            GIFT_FIELDS +
            ' FROM Gift__c WHERE Status__c IN :statuses AND Amount__c > 0' +
            ' AND Type__c != :inKind AND Gift_Date__c >= :startDate';
        if (inRange == true) {
            query += ' AND Gift_Date__c >= :fromDate AND Gift_Date__c <= :toDate';
        } else if (sinceLastRun == true) {
            query += ' AND (Gift_Transaction_Id__c = NULL OR LastModifiedDate >= :since)';
        } else {
            query += ' AND Gift_Transaction_Id__c = NULL';
        }
        return query + ' ORDER BY Gift_Date__c, Id';
    }

    /**
     * The Gift Transactions a Gift Transactions to Gifts run turns into gifts (R-GT6): of the paid
     * status (bind `status`), dated on or after the start date (bind `startDate`), oldest first.
     * Those a gift already names are left out per chunk.
     */
    public static String giftTransactionsToGiftsQuery(String objectName, List<String> fields) {
        return 'SELECT Id, ' +
            String.escapeSingleQuotes(String.join(fields, ', ')) +
            ' FROM ' +
            String.escapeSingleQuotes(objectName) +
            ' WHERE ' +
            GiftTransactionMirrorSchema.STATUS_FIELD +
            ' = :status AND ' +
            GiftTransactionMirrorSchema.DATE_FIELD +
            ' >= :startDate ORDER BY ' +
            GiftTransactionMirrorSchema.DATE_FIELD +
            ', Id';
    }

    /**
     * The Gift Transactions with these identifiers that the running user can see, keyed by Id.
     *
     * @param fields the fields to read besides Id, from the schema, which knows which ones exist
     */
    public static Map<Id, SObject> giftTransactionsById(
        String objectName,
        List<String> fields,
        Set<Id> ids
    ) {
        if (String.isBlank(objectName) || ids == null || ids.isEmpty()) {
            return new Map<Id, SObject>();
        }
        return new Map<Id, SObject>(
            Database.queryWithBinds(
                'SELECT Id, ' +
                    String.escapeSingleQuotes(String.join(fields, ', ')) +
                    ' FROM ' +
                    String.escapeSingleQuotes(objectName) +
                    ' WHERE Id IN :ids',
                new Map<String, Object>{ 'ids' => ids },
                AccessLevel.USER_MODE
            )
        );
    }

    /** The Gift Transaction ID of every gift naming one of these that the running user can see. */
    public static Set<String> linkedGiftTransactionIds(Set<String> giftTransactionIds) {
        Set<String> linked = new Set<String>();
        if (giftTransactionIds == null || giftTransactionIds.isEmpty()) {
            return linked;
        }
        for (Gift__c gift : [
            SELECT Gift_Transaction_Id__c
            FROM Gift__c
            WHERE Gift_Transaction_Id__c IN :giftTransactionIds
            WITH USER_MODE
        ]) {
            linked.add(gift.Gift_Transaction_Id__c);
        }
        return linked;
    }

    /**
     * The same, counting only gifts R-GT3 copies (whatever their date), for the reconciliation:
     * a Gift Transaction named only by a refunded or pending gift is listed (R-GT10).
     */
    public static Set<String> linkedByMirroredGifts(
        Set<String> giftTransactionIds,
        Set<String> statuses,
        String inKind
    ) {
        Set<String> linked = new Set<String>();
        if (giftTransactionIds == null || giftTransactionIds.isEmpty()) {
            return linked;
        }
        for (Gift__c gift : [
            SELECT Gift_Transaction_Id__c
            FROM Gift__c
            WHERE
                Gift_Transaction_Id__c IN :giftTransactionIds
                AND Status__c IN :statuses
                AND Amount__c > 0
                AND Type__c != :inKind
            WITH USER_MODE
        ]) {
            linked.add(gift.Gift_Transaction_Id__c);
        }
        return linked;
    }

    /**
     * The gifts R-GT3 copies dated in the range that the running user can see, oldest first, for a
     * SOQL for loop through `Database.query`, which reads them 200 at a time, no more than `cap`.
     * Binds `statuses`, `inKind`, `fromDate`, `toDate` and `cap` from the caller's scope.
     */
    public static final String GIFTS_IN_RANGE_QUERY =
        'SELECT Id, Name, Amount__c, Gift_Date__c, Gift_Transaction_Id__c FROM Gift__c' +
        ' WHERE Status__c IN :statuses AND Amount__c > 0 AND Type__c != :inKind' +
        ' AND Gift_Date__c >= :fromDate AND Gift_Date__c <= :toDate' +
        ' WITH USER_MODE ORDER BY Gift_Date__c, Id LIMIT :cap';

    /**
     * The Gift Transactions of the paid status dated in the range that the running user can see,
     * oldest first, no more than `cap` (R-GT10).
     */
    public static List<SObject> giftTransactionsInRange(
        String objectName,
        String status,
        Date fromDate,
        Date toDate,
        Integer cap
    ) {
        String dateField = GiftTransactionMirrorSchema.DATE_FIELD;
        return Database.queryWithBinds(
            'SELECT Id, ' +
                String.join(GiftTransactionMirrorSchema.READ, ', ') +
                ' FROM ' +
                String.escapeSingleQuotes(objectName) +
                ' WHERE ' +
                GiftTransactionMirrorSchema.STATUS_FIELD +
                ' = :status AND ' +
                dateField +
                ' >= :fromDate AND ' +
                dateField +
                ' <= :toDate ORDER BY ' +
                dateField +
                ', Id LIMIT :cap',
            new Map<String, Object>{
                'status' => status,
                'fromDate' => fromDate,
                'toDate' => toDate,
                'cap' => cap
            },
            AccessLevel.USER_MODE
        );
    }
}

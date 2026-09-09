/**
 * The permanent record of what an import did, and of what an undo of it deleted or kept
 * (canonical model Section 17A).
 *
 * A page holds one entry per row of one chunk, so a hundred thousand row import leaves a few
 * hundred journal records rather than a hundred thousand, and it holds no copy of the
 * uploaded values, so keeping it forever costs a fraction of what keeping the staged rows
 * costs (R-IJ1). That is what lets the rows be cleaned up without losing the answer to
 * "what did this import actually do".
 *
 * Nothing here is allowed to fail an import. Losing the record of what happened is bad;
 * losing what happened is worse, so a journal write that fails is logged and swallowed
 * (R-IJ4).
 */
@NamespaceAccessible
public with sharing class ImportJournalService {
    @NamespaceAccessible
    public static final String PHASE_COMMIT = 'Commit';
    @NamespaceAccessible
    public static final String PHASE_UNDO = 'Undo';

    @NamespaceAccessible
    public static final String ACTION_CREATED = 'Created';
    @NamespaceAccessible
    public static final String ACTION_UPDATED = 'Updated';
    @NamespaceAccessible
    public static final String ACTION_MATCHED = 'Matched';
    @NamespaceAccessible
    public static final String ACTION_REJECTED = 'Rejected';
    @NamespaceAccessible
    public static final String ACTION_DELETED = 'Deleted';
    @NamespaceAccessible
    public static final String ACTION_KEPT = 'Kept';

    /** The document version written into every page, so a reader can tell the shape. */
    private static final Integer DOCUMENT_VERSION = 1;

    /** How long a single remembered value may be before it is shortened (R-IJ3). */
    private static final Integer MAX_VALUE_LENGTH = 120;

    /** The most a page may hold, so a page always fits its long text attribute. */
    private static final Integer MAX_DOCUMENT_LENGTH = 131072;

    /** One thing that happened to one row. */
    @NamespaceAccessible
    public class Entry {
        @NamespaceAccessible
        public Integer row;
        @NamespaceAccessible
        public String action;
        @NamespaceAccessible
        public String objectName;
        @NamespaceAccessible
        public String recordId;
        @NamespaceAccessible
        public String label;
        /** For an update, the attributes that changed and what was there before (R-IJ3). */
        @NamespaceAccessible
        public String was;
        /** For a rejection or a kept record, why. */
        @NamespaceAccessible
        public String reason;

        @NamespaceAccessible
        public Entry(Integer row, String action) {
            this.row = row;
            this.action = action;
        }

        @NamespaceAccessible
        public Entry on(String objectName, Id recordId, String label) {
            this.objectName = objectName;
            this.recordId = recordId == null ? null : String.valueOf(recordId);
            this.label = shorten(label);
            return this;
        }

        @NamespaceAccessible
        public Entry because(String reason) {
            this.reason = shorten(reason);
            return this;
        }

        @NamespaceAccessible
        public Entry previously(String was) {
            this.was = shorten(was);
            return this;
        }
    }

    /**
     * Writes one page. The page number continues the numbering of this batch and phase, read
     * from what is already stored rather than carried in memory, so a run that was resumed
     * does not start numbering again.
     *
     * @return the page written, or null when there was nothing to write or the write failed
     */
    @NamespaceAccessible
    public static Import_Journal__c writePage(Id batchId, String phase, List<Entry> entries) {
        if (batchId == null || entries == null || entries.isEmpty()) {
            return null;
        }
        try {
            Import_Journal__c page = new Import_Journal__c(
                Import_Batch__c = batchId,
                Phase__c = PHASE_UNDO.equals(phase) ? PHASE_UNDO : PHASE_COMMIT,
                Page_Number__c = nextPageNumber(batchId, phase),
                Entry_Count__c = entries.size(),
                Entries_JSON__c = document(entries)
            );
            // The journal is the package's own bookkeeping and is written even where the
            // running user cannot edit it, for the reason ADR-0021 gives.
            Database.insert(page, AccessLevel.SYSTEM_MODE);
            return page;
        } catch (Exception e) {
            ErrorLogger.log(e, 'ImportJournalService.writePage', batchId);
            return null;
        }
    }

    /** The pages of one batch in the order they were written, for the results screen. */
    @NamespaceAccessible
    public static List<Import_Journal__c> pages(Id batchId, Integer offsetPages) {
        if (batchId == null) {
            return new List<Import_Journal__c>();
        }
        Integer skip = offsetPages == null || offsetPages < 0 ? 0 : Math.min(offsetPages, 2000);
        return Database.queryWithBinds(
            'SELECT Id, Name, Phase__c, Page_Number__c, Entry_Count__c, Entries_JSON__c, ' +
            'CreatedDate, CreatedById FROM Import_Journal__c WHERE Import_Batch__c = :batchId ' +
            'ORDER BY CreatedDate ASC, Page_Number__c ASC LIMIT 20 OFFSET :skip',
            new Map<String, Object>{ 'batchId' => batchId, 'skip' => skip },
            AccessLevel.USER_MODE
        );
    }

    /** How many entries a batch has journaled, so a total is a sum rather than a parse. */
    @NamespaceAccessible
    public static Integer entryCount(Id batchId, String phase) {
        if (batchId == null) {
            return 0;
        }
        List<AggregateResult> totals = Database.queryWithBinds(
            'SELECT SUM(Entry_Count__c) total FROM Import_Journal__c ' +
            'WHERE Import_Batch__c = :batchId AND Phase__c = :phase',
            new Map<String, Object>{ 'batchId' => batchId, 'phase' => phase },
            AccessLevel.SYSTEM_MODE
        );
        if (totals.isEmpty() || totals[0].get('total') == null) {
            return 0;
        }
        return ((Decimal) totals[0].get('total')).intValue();
    }

    private static Integer nextPageNumber(Id batchId, String phase) {
        List<AggregateResult> counted = Database.queryWithBinds(
            'SELECT COUNT(Id) total FROM Import_Journal__c ' +
            'WHERE Import_Batch__c = :batchId AND Phase__c = :phase',
            new Map<String, Object>{ 'batchId' => batchId, 'phase' => phase },
            AccessLevel.SYSTEM_MODE
        );
        Integer already = counted.isEmpty() ? 0 : (Integer) counted[0].get('total');
        return already + 1;
    }

    /**
     * The entries as one document. A page that would overflow its attribute drops entries
     * from the end and says so, rather than throwing away the whole page.
     */
    private static String document(List<Entry> entries) {
        String body = JSON.serialize(
            new Map<String, Object>{ 'version' => DOCUMENT_VERSION, 'entries' => entries },
            true
        );
        if (body.length() <= MAX_DOCUMENT_LENGTH) {
            return body;
        }
        List<Entry> kept = new List<Entry>();
        for (Integer i = 0; i < entries.size() / 2; i++) {
            kept.add(entries[i]);
        }
        Entry note = new Entry(null, ACTION_KEPT);
        note.reason = String.format(
            Label.Core_Import_JournalPageTruncated,
            new List<String>{ String.valueOf(entries.size() - kept.size()) }
        );
        kept.add(note);
        return JSON.serialize(
                new Map<String, Object>{ 'version' => DOCUMENT_VERSION, 'entries' => kept },
                true
            )
            .abbreviate(MAX_DOCUMENT_LENGTH);
    }

    private static String shorten(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        return value.length() <= MAX_VALUE_LENGTH ? value : value.abbreviate(MAX_VALUE_LENGTH);
    }
}

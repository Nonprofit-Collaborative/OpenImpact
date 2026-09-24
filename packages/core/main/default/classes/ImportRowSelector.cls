/**
 * Every query against staged import rows.
 *
 * Rows are read in pages, never all at once: an import of hundreds of thousands of rows must
 * not be able to make a screen ask for all of them.
 */
@NamespaceAccessible
public with sharing class ImportRowSelector {
    /** How many rows a screen may ask for in one call. */
    @NamespaceAccessible
    public static final Integer PAGE_SIZE = 200;

    private static final String FIELDS =
        'Id, Name, Import_Batch__c, Row_Number__c, ' +
        'Raw_Values_JSON__c, Status__c, Error_Message__c, Household__c, Contact_1__c, ' +
        'Person_1_Account__c, Contact_2__c, Person_2_Account__c, Organization__c, Gift_Id__c, ' +
        'Soft_Credit_Id__c';

    /** One page of a batch's rows in file order. */
    @NamespaceAccessible
    public static List<Import_Row__c> selectByBatch(Id batchId, Integer offsetRows) {
        return page(batchId, null, offsetRows);
    }

    /**
     * One page of a batch's rows in the given status, in file order. This is what the
     * exceptions file is built from, with status Rejected.
     */
    @NamespaceAccessible
    public static List<Import_Row__c> selectByBatchAndStatus(
        Id batchId,
        String status,
        Integer offsetRows
    ) {
        return page(batchId, status, offsetRows);
    }

    private static List<Import_Row__c> page(Id batchId, String status, Integer offsetRows) {
        if (batchId == null) {
            return new List<Import_Row__c>();
        }
        Integer skip = offsetRows == null || offsetRows < 0 ? 0 : Math.min(offsetRows, 2000);
        String query = 'SELECT ' + FIELDS + ' FROM Import_Row__c WHERE Import_Batch__c = :batchId';
        Map<String, Object> binds = new Map<String, Object>{
            'batchId' => batchId,
            'skip' => skip,
            'pageSize' => PAGE_SIZE
        };
        if (String.isNotBlank(status)) {
            query += ' AND Status__c = :status';
            binds.put('status', status);
        }
        query += ' ORDER BY Row_Number__c ASC LIMIT :pageSize OFFSET :skip';
        return Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);
    }

    /** How many digests one query takes; a chunk with more is asked in slices. */
    private static final Integer DIGESTS_PER_QUERY = 1000;

    /**
     * The batch's current pass (R-IB13), or null for a batch read without it, as a test that
     * never started a pass reads it.
     */
    @NamespaceAccessible
    public static Decimal passOf(Import_Batch__c batch) {
        return batch != null && batch.isSet(Import_Batch__c.Pass_Number__c)
            ? batch.Pass_Number__c
            : null;
    }

    /**
     * Which of these digests an earlier chunk of the current pass wrote as a person or an
     * organization it would create (R-IB12). Only rows stamped with this pass are read (R-IB13),
     * and only for the chunk's own digests, so what this costs never depends on how many rows
     * came before. In system mode (ADR-0021): the staged rows are the package's own bookkeeping.
     */
    @NamespaceAccessible
    public static Set<String> createdDigestsWrittenEarlier(
        Import_Batch__c batch,
        Set<String> digests
    ) {
        return createdDigestCounts(batch, digests).keySet();
    }

    /**
     * The same, with how many times each was written: a shared key two people created would
     * hold is written twice, so a later chunk knows it can no longer find one of them by it
     * alone (R-IB12).
     */
    @NamespaceAccessible
    public static Map<String, Integer> createdDigestCounts(
        Import_Batch__c batch,
        Set<String> digests
    ) {
        return digestsWrittenEarlier(
            batch,
            digests,
            new List<String>{
                'Person_1_Key__c',
                'Person_2_Key__c',
                'Person_1_Name_Key__c',
                'Person_2_Name_Key__c',
                'Organization_Key__c'
            }
        );
    }

    /**
     * Which of these digests an earlier chunk of the current pass wrote as the entity
     * processor's key (R-IR6): for Giving, the external IDs of the gifts a dry run would load.
     */
    @NamespaceAccessible
    public static Set<String> processorDigestsWrittenEarlier(
        Import_Batch__c batch,
        Set<String> digests
    ) {
        return digestsWrittenEarlier(batch, digests, new List<String>{ 'Processor_Key__c' })
            .keySet();
    }

    private static Map<String, Integer> digestsWrittenEarlier(
        Import_Batch__c batch,
        Set<String> digests,
        List<String> fields
    ) {
        Map<String, Integer> found = new Map<String, Integer>();
        if (batch == null || batch.Id == null || digests == null || digests.isEmpty()) {
            return found;
        }
        List<String> all = new List<String>(digests);
        for (Integer start = 0; start < all.size(); start += DIGESTS_PER_QUERY) {
            List<String> slice = new List<String>();
            for (Integer i = start; i < Math.min(start + DIGESTS_PER_QUERY, all.size()); i++) {
                slice.add(all[i]);
            }
            found.putAll(digestSlice(batch, slice, fields));
        }
        return found;
    }

    /** One slice, kept out of the caller's loop so no query sits lexically inside one. */
    private static Map<String, Integer> digestSlice(
        Import_Batch__c batch,
        List<String> slice,
        List<String> fields
    ) {
        Set<String> wanted = new Set<String>(slice);
        List<String> matches = new List<String>();
        for (String field : fields) {
            matches.add(field + ' IN :slice');
        }
        List<Import_Row__c> rows = Database.queryWithBinds(
            'SELECT ' +
                String.join(fields, ', ') +
                ' FROM Import_Row__c WHERE Import_Batch__c = :batchId' +
                ' AND Pass_Number__c = :pass AND (' +
                String.join(matches, ' OR ') +
                ')',
            new Map<String, Object>{
                'batchId' => batch.Id,
                'slice' => slice,
                'pass' => passOf(batch)
            },
            AccessLevel.SYSTEM_MODE
        );
        Map<String, Integer> found = new Map<String, Integer>();
        for (Import_Row__c row : rows) {
            for (String field : fields) {
                String value = (String) row.get(field);
                if (value != null && wanted.contains(value)) {
                    found.put(value, found.containsKey(value) ? found.get(value) + 1 : 1);
                }
            }
        }
        return found;
    }
}

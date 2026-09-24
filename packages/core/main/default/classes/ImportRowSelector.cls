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
     * Which of these digests an earlier chunk of the current pass wrote as a person or an
     * organization it would create (R-IB12). Only rows already processed in this pass carry
     * one, since a pass starts from rows reset to Pending with no digests, so what this costs
     * depends on the chunk's own digests and never on how many rows came before. In system
     * mode (ADR-0021): the staged rows are the package's own bookkeeping.
     */
    @NamespaceAccessible
    public static Set<String> createdDigestsWrittenEarlier(Id batchId, Set<String> digests) {
        return digestsWrittenEarlier(
            batchId,
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
    public static Set<String> processorDigestsWrittenEarlier(Id batchId, Set<String> digests) {
        return digestsWrittenEarlier(batchId, digests, new List<String>{ 'Processor_Key__c' });
    }

    private static Set<String> digestsWrittenEarlier(
        Id batchId,
        Set<String> digests,
        List<String> fields
    ) {
        Set<String> found = new Set<String>();
        if (batchId == null || digests == null || digests.isEmpty()) {
            return found;
        }
        List<String> all = new List<String>(digests);
        for (Integer start = 0; start < all.size(); start += DIGESTS_PER_QUERY) {
            List<String> slice = new List<String>();
            for (Integer i = start; i < Math.min(start + DIGESTS_PER_QUERY, all.size()); i++) {
                slice.add(all[i]);
            }
            found.addAll(digestSlice(batchId, slice, fields, digests));
        }
        return found;
    }

    /** One slice, kept out of the caller's loop so no query sits lexically inside one. */
    private static Set<String> digestSlice(
        Id batchId,
        List<String> slice,
        List<String> fields,
        Set<String> wanted
    ) {
        List<String> matches = new List<String>();
        for (String field : fields) {
            matches.add(field + ' IN :slice');
        }
        List<Import_Row__c> rows = Database.queryWithBinds(
            'SELECT ' +
                String.join(fields, ', ') +
                ' FROM Import_Row__c WHERE Import_Batch__c = :batchId' +
                ' AND Status__c != :pending AND (' +
                String.join(matches, ' OR ') +
                ')',
            new Map<String, Object>{
                'batchId' => batchId,
                'slice' => slice,
                'pending' => ImportRowProcessor.STATUS_PENDING
            },
            AccessLevel.SYSTEM_MODE
        );
        Set<String> found = new Set<String>();
        for (Import_Row__c row : rows) {
            for (String field : fields) {
                String value = (String) row.get(field);
                if (value != null && wanted.contains(value)) {
                    found.add(value);
                }
            }
        }
        return found;
    }
}

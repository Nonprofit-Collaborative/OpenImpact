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
}

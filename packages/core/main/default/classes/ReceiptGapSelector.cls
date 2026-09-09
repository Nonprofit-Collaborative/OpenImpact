/**
 * How many receipt numbers were consumed by a run that failed (feature C-11, ADR-0016).
 *
 * Rule R-RC3: a number whose document never generated is reconciled into a receipt with
 * Status `Void` and Void Reason `Generation failed`, so an auditor asking what happened to
 * number 47 gets a record rather than silence. One of those is ordinary. A growing number of
 * them means receipt generation is failing over and over and nobody has looked.
 *
 * `Receipt__c` belongs to the Giving package and this class belongs to Core, which must
 * deploy and run on a Platform-only org with no Giving in it at all (ADR-0009, ADR-0013). So
 * the object and its two fields are named as Strings, resolved through the global describe,
 * and counted with dynamic SOQL, which is the mechanism ADR-0017 settled for reaching a
 * package Core cannot compile against. An org without Giving does not resolve the object and
 * gets `available = false`, which Health Check reports as no finding rather than as a zero.
 *
 * The names are qualified through NamespaceUtil, because a packaged object and its fields
 * carry the namespace prefix once one is registered (ADR-0001), and the two values matched on
 * are data rather than API names and are therefore never qualified. They are passed as bind
 * variables, so no value this class does not own is ever concatenated into the query.
 */
public with sharing class ReceiptGapSelector {
    /** The Giving API names this class knows, as Strings and only as Strings. */
    private static final String RECEIPT_OBJECT = 'Receipt__c';
    private static final String STATUS_FIELD = 'Status__c';
    private static final String VOID_REASON_FIELD = 'Void_Reason__c';

    /** The two values the reconciliation record carries, quoted in ADR-0016 and R-RC3. */
    private static final String STATUS_VOID = 'Void';
    private static final String REASON_GENERATION_FAILED = 'Generation failed';

    /** Injected by the tests, which have no Giving package to count receipts in. */
    @TestVisible
    private static Result resultOverride;

    /**
     * The count, and whether it could be taken at all. `available` is false for an org
     * without Giving, for a Giving too old to have the fields, and for a person who cannot
     * read receipts: in all three cases Core knows nothing, which is not the same as knowing
     * that nothing failed.
     */
    public class Result {
        public Boolean available;
        public Integer count;

        public Result() {
            this.available = false;
            this.count = 0;
        }
    }

    /**
     * How many receipts stand as the record of a number a failed run consumed.
     */
    public static Result generationFailures() {
        if (resultOverride != null) {
            return resultOverride;
        }

        Result result = new Result();

        String objectName = NamespaceUtil.qualify(RECEIPT_OBJECT);
        SObjectType receiptType = Schema.getGlobalDescribe().get(objectName.toLowerCase());
        if (receiptType == null) {
            return result;
        }

        DescribeSObjectResult receipt = receiptType.getDescribe(SObjectDescribeOptions.DEFERRED);
        if (!receipt.isAccessible()) {
            return result;
        }

        String statusField = NamespaceUtil.qualify(STATUS_FIELD);
        String reasonField = NamespaceUtil.qualify(VOID_REASON_FIELD);
        Map<String, SObjectField> fields = receipt.fields.getMap();
        if (!isReadable(fields, statusField) || !isReadable(fields, reasonField)) {
            return result;
        }

        String soql = countQuery(receipt.getName(), statusField, reasonField);

        try {
            result.count = Database.countQueryWithBinds(
                soql,
                new Map<String, Object>{
                    'status' => STATUS_VOID,
                    'reason' => REASON_GENERATION_FAILED
                },
                AccessLevel.USER_MODE
            );
            result.available = true;
        } catch (QueryException cannotCount) {
            result.available = false;
            result.count = 0;
        }

        return result;
    }

    /**
     * The count query, built from names the platform gave back rather than from anything a
     * user typed. Kept apart from the query itself so that a test with no Giving package to
     * query can still assert what Core would ask for, which is the part a registered
     * namespace would break.
     */
    @TestVisible
    private static String countQuery(String objectName, String statusField, String reasonField) {
        return 'SELECT COUNT() FROM ' +
            objectName +
            ' WHERE ' +
            statusField +
            ' = :status AND ' +
            reasonField +
            ' = :reason';
    }

    /** Whether one field is on the object and readable by the person asking. */
    private static Boolean isReadable(Map<String, SObjectField> fields, String fieldName) {
        SObjectField field = fields.get(fieldName.toLowerCase());
        return field != null && field.getDescribe().isAccessible();
    }
}

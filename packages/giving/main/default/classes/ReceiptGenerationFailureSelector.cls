/**
 * How many receipt numbers were consumed by a run that failed (feature C-11, ADR-0016), for
 * the Health Check finding Giving adds to Core's report (ADR-NEXT).
 *
 * Rule R-RC3: a number whose document never generated is reconciled into a receipt with
 * Status `Void` and Void Reason `Generation failed`, so an auditor asking what happened to
 * number 47 gets a record rather than silence. One of those is ordinary. A growing number of
 * them means receipt generation is failing over and over and nobody has looked.
 *
 * Until C-29 Core took this count as `ReceiptGapSelector`, with dynamic SOQL. `Receipt__c` is
 * Giving's own object, so the count is an ordinary query in user mode: a person who cannot
 * read receipts gets `available = false`, which Health Check reports as no finding rather
 * than as a zero.
 */
public with sharing class ReceiptGenerationFailureSelector {
    /** Injected by the tests, which choose the count rather than creating failed runs. */
    @TestVisible
    private static Result resultOverride;

    /** The count, and whether the running person could take it at all. */
    public class Result {
        public Boolean available;
        public Integer count;

        public Result() {
            this.available = false;
            this.count = 0;
        }
    }

    /** How many receipts stand as the record of a number a failed run consumed. */
    public static Result generationFailures() {
        if (resultOverride != null) {
            return resultOverride;
        }
        Result result = new Result();
        try {
            result.count = [
                SELECT COUNT()
                FROM Receipt__c
                WHERE
                    Status__c = :ReceiptService.STATUS_VOID
                    AND Void_Reason__c = :ReceiptNumberSequence.VOID_REASON_GENERATION_FAILED
                WITH USER_MODE
            ];
            result.available = true;
        } catch (QueryException cannotRead) {
            result.available = false;
            result.count = 0;
        }
        return result;
    }
}

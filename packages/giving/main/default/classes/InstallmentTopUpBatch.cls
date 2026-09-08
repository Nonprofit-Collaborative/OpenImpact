/**
 * The batch behind the nightly top up: it walks every active recurring commitment and
 * extends each one's schedule up to the org's generation horizon (R-CM2).
 *
 * It is a batch rather than one query and one save because the work scales with the org.
 * A thousand weekly commitments imply tens of thousands of expected payments, which is
 * more rows than a single transaction may insert, and a capped query would quietly extend
 * the same oldest commitments every night and never reach the rest. A small chunk keeps
 * every run inside the row limits and gives every commitment its turn.
 */
public with sharing class InstallmentTopUpBatch implements Database.Batchable<SObject>, Database.Stateful {
    /**
     * Commitments per chunk. Deliberately small: one weekly commitment can imply more than
     * fifty expected payments over a twelve month horizon, so twenty five commitments stay
     * an order of magnitude inside the rows one transaction may insert.
     */
    public static final Integer CHUNK_SIZE = 25;

    private Integer processed = 0;

    public Database.QueryLocator start(Database.BatchableContext context) {
        return new CommitmentSelector().activeRecurringLocator();
    }

    public void execute(Database.BatchableContext context, List<Commitment__c> scope) {
        try {
            processed += CommitmentService.topUpRecurringSchedules(scope);
        } catch (Exception chunkFailure) {
            // One bad commitment must not stop the rest of the org being extended.
            ErrorLogger.log(chunkFailure, 'InstallmentTopUpBatch');
        }
    }

    public void finish(Database.BatchableContext context) {
        try {
            CommitmentService.recordTopUpRun(System.now());
        } catch (Exception finishFailure) {
            ErrorLogger.log(finishFailure, 'InstallmentTopUpBatch.finish');
        }
    }

    /** How many commitments this run extended, for a test or a caller that wants to know. */
    public Integer commitmentsProcessed() {
        return processed;
    }
}

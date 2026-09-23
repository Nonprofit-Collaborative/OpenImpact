/**
 * The scan that finds the duplicates that were already there (C-20, canonical model R-DP3).
 *
 * A duplicate rule runs only when somebody saves a record, so the day Open Impact is installed
 * the platform has never compared last year's imported spreadsheet with itself. The platform's
 * answer, a duplicate job, exists only in the two largest editions. This batch asks the
 * platform to evaluate the org's own active rules against records that already exist, fifty at
 * a time, which is the most one call accepts: people first, then households.
 *
 * It writes nothing but the platform's own duplicate record sets, changes nothing about the
 * records it examines, and merges nothing (R-DP4). It runs as the person who started it, so it
 * sees and records only what they can.
 */
public with sharing class DuplicateScanBatch implements Database.Batchable<SObject>, Database.Stateful {
    private static final String LOG_CONTEXT = 'Duplicate scan';

    private final String objectName;
    private final List<String> remaining;
    private final Map<String, Id> ruleIdsByName;
    private Integer written = 0;

    public DuplicateScanBatch(String objectName, List<String> remaining) {
        this.objectName = objectName;
        this.remaining = remaining == null ? new List<String>() : remaining;
        this.ruleIdsByName = DuplicateSelector.activeRuleIdsByName(new Set<String>{ objectName });
    }

    /**
     * Starts a scan of every reviewed object that has an active duplicate rule, and answers
     * with the job started, or null when no rule is active for any of them: with nothing to
     * evaluate, a clean result would be a lie rather than an answer.
     */
    public static Id start() {
        Set<String> active = DuplicateSelector.objectsWithActiveRules(
            new Set<String>(DuplicateSelector.REVIEWED_OBJECTS)
        );
        List<String> toScan = new List<String>();
        for (String objectName : DuplicateSelector.REVIEWED_OBJECTS) {
            if (active.contains(objectName)) {
                toScan.add(objectName);
            }
        }
        if (toScan.isEmpty()) {
            return null;
        }
        String first = toScan.remove(0);
        return Database.executeBatch(
            new DuplicateScanBatch(first, toScan),
            DuplicateService.MAX_RECORDS_PER_CALL
        );
    }

    /**
     * Identifiers only: the matcher reads the records itself. Accounts are households only
     * (R-DP2), which also keeps a person stored as an account out of the call, because the
     * platform refuses a call that includes one when no person account rule is active.
     */
    public Database.QueryLocator start(Database.BatchableContext context) {
        Map<String, Object> binds = new Map<String, Object>{
            'householdType' => HouseholdService.householdRecordTypeId()
        };
        String query = objectName == 'Account'
            ? 'SELECT Id FROM Account WHERE RecordTypeId = :householdType'
            : 'SELECT Id FROM Contact';
        return Database.getQueryLocatorWithBinds(query, binds, AccessLevel.USER_MODE);
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        written += scanChunk(scope, ruleIdsByName);
    }

    /** One chunk: ask, keep what is new and actionable, write it down. */
    public static Integer scanChunk(List<SObject> scope, Map<String, Id> ruleIdsByName) {
        List<Id> recordIds = new List<Id>();
        for (SObject record : scope) {
            recordIds.add(record.Id);
        }
        List<DuplicateService.Pair> candidates = DuplicateService.pairsToRecord(
            DuplicateService.matchesFor(recordIds),
            DuplicateService.pairsAlreadySuggested(new Set<Id>(recordIds))
        );
        return DuplicateService.recordPairs(
            DuplicateService.withoutDismissed(DuplicateService.actionablePairs(candidates)),
            ruleIdsByName
        );
    }

    /**
     * Records what this pass found, then starts the next object. A scan that found nothing
     * says so: "ran and found nothing" and "never ran" are different facts.
     */
    public void finish(Database.BatchableContext context) {
        ErrorLogger.logMessage(
            String.format(
                Label.Core_Duplicates_ScanFinished,
                new List<String>{ objectName, String.valueOf(written) }
            ),
            LOG_CONTEXT,
            ErrorLogger.SEVERITY_INFO
        );
        if (!remaining.isEmpty()) {
            List<String> next = remaining.clone();
            String objectToScan = next.remove(0);
            Database.executeBatch(
                new DuplicateScanBatch(objectToScan, next),
                DuplicateService.MAX_RECORDS_PER_CALL
            );
        }
    }
}

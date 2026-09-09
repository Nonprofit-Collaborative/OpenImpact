/**
 * The scan that finds the duplicates that were already there (C-20, canonical model R-DP3).
 *
 * A duplicate rule only ever runs when somebody saves a record, so on the day the rules are
 * switched on the platform knows nothing about the thousand records that came in from a
 * spreadsheet last year. The standard answer to that is a duplicate job, which is available
 * only in the two largest editions, and no nonprofit that Open Impact is built for has one.
 * So this batch asks the platform to evaluate its own active rules against records that
 * already exist, fifty at a time, which is the most one call takes.
 *
 * It creates no records other than the platform's own duplicate record sets, changes nothing
 * about the records it examines, and merges nothing. A merge is a person's decision, one pair
 * at a time (R-DP4).
 */
public with sharing class DuplicateScanBatch implements Database.Batchable<SObject>, Database.Stateful {
    private static final String LOG_CONTEXT = 'Duplicate scan';

    /** The objects a scan covers, in the order it covers them. */
    public static final List<String> SCANNED_OBJECTS = new List<String>{ 'Contact', 'Account' };

    private final String objectName;
    private final List<String> remaining;
    private final Map<String, DuplicateRule> rulesByName;
    private Integer written = 0;

    public DuplicateScanBatch(String objectName, List<String> remaining) {
        this.objectName = objectName;
        this.remaining = remaining == null ? new List<String>() : remaining;
        this.rulesByName = DuplicateSelector.activeRulesByName(new Set<String>{ objectName });
    }

    /**
     * Starts a scan of every object that has an active duplicate rule, and answers with the
     * job that was started, or null when no rule is active anywhere. Nothing is scanned
     * without an active rule: there would be nothing to evaluate, and a clean result would be
     * a lie rather than an answer.
     */
    public static Id start() {
        List<String> toScan = new List<String>();
        Map<String, DuplicateRule> active = DuplicateSelector.activeRulesByName(
            new Set<String>(SCANNED_OBJECTS)
        );
        for (String objectName : SCANNED_OBJECTS) {
            for (DuplicateRule rule : active.values()) {
                if (rule.SobjectType == objectName && !toScan.contains(objectName)) {
                    toScan.add(objectName);
                }
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

    public Database.QueryLocator start(Database.BatchableContext context) {
        // The identifier is all the platform's matcher is given: it reads the record itself.
        return Database.getQueryLocator('SELECT Id FROM ' + String.escapeSingleQuotes(objectName));
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        List<Id> recordIds = new List<Id>();
        Set<Id> asSet = new Set<Id>();
        for (SObject record : scope) {
            recordIds.add(record.Id);
            asSet.add(record.Id);
        }
        List<DuplicateService.Pair> candidates = DuplicateService.pairsToRecord(
            DuplicateService.matchesFor(recordIds),
            DuplicateService.pairsAlreadySuggested(asSet)
        );
        written += DuplicateService.recordPairs(
            DuplicateService.withoutDismissed(candidates),
            rulesByName
        );
    }

    /**
     * Records what this pass found, then starts the next object. A scan that found nothing
     * still says so: "ran and found nothing" and "never ran" are different facts, and the
     * page shows the difference.
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

/**
 * A run of the Opportunity mirror (feature X-01, R-OM8), as the person who started or scheduled
 * it, in chunks. What it does follows the chosen direction:
 *
 * - Gifts to Opportunities: copies every gift in the totals that has no Opportunity yet, or, from
 *   the reconciliation page, every gift in the totals dated in a range (R-OM11).
 * - Opportunities to Gifts: makes a gift from every won Opportunity closed on or after the start
 *   date that no gift names (R-OM7).
 *
 * Refusals are gathered across the chunks and written when the run ends, one Warning per distinct
 * reason, with a summary at Info (R-OM6), so a nightly run over a refused rule writes one entry
 * rather than one per gift, and none per chunk.
 */
public with sharing class OpportunityMirrorBatch implements Database.Batchable<SObject>, Database.Stateful {
    public static final String CLASS_NAME = 'OpportunityMirrorBatch';
    /** Smaller than Campaign sync's: the org's own Opportunity automation runs on each chunk. */
    @TestVisible
    private static final Integer CHUNK_SIZE = 100;
    private static final String LOG_CONTEXT = 'Opportunity mirror: run';
    // Core's constant for this severity is not namespace accessible, so its value is repeated.
    private static final String SEVERITY_INFO = 'Info';

    private final String direction;
    private final Date fromDate;
    private final Date toDate;
    private final OpportunityMirrorService.Result totals = new OpportunityMirrorService.Result();

    @TestVisible
    private OpportunityMirrorBatch(String direction, Date fromDate, Date toDate) {
        this.direction = direction;
        this.fromDate = fromDate;
        this.toDate = toDate;
    }

    /** Starts a run in the chosen direction and returns its job id, or null when it is off. */
    public static Id run() {
        String direction = OpportunityMirrorService.direction();
        if (direction == OpportunityMirrorService.OFF || !OpportunityMirrorService.isAvailable()) {
            return null;
        }
        return Database.executeBatch(new OpportunityMirrorBatch(direction, null, null), CHUNK_SIZE);
    }

    /** Copies again every gift in the totals dated in the range (Gifts to Opportunities only). */
    public static Id runRange(Date fromDate, Date toDate) {
        return Database.executeBatch(
            new OpportunityMirrorBatch(
                OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES,
                fromDate,
                toDate
            ),
            CHUNK_SIZE
        );
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        if (direction == OpportunityMirrorService.OPPORTUNITIES_TO_GIFTS) {
            Date startDate = OpportunityGiftService.startDate();
            return Database.getQueryLocatorWithBinds(
                OpportunityMirrorSelector.wonOpportunitiesQuery(
                    OpportunityMirrorService.opportunityType().getDescribe().getName(),
                    OpportunityGiftService.opportunityFields()
                ),
                // No start date, no Opportunity: a date no Opportunity closes on or after.
                new Map<String, Object>{
                    'startDate' => startDate == null ? Date.newInstance(4000, 12, 31) : startDate
                },
                AccessLevel.USER_MODE
            );
        }
        return Database.getQueryLocatorWithBinds(
            OpportunityMirrorSelector.giftsToCopyQuery(fromDate != null),
            new Map<String, Object>{
                'statuses' => OpportunityMirrorService.IN_TOTALS,
                'fromDate' => fromDate,
                'toDate' => toDate
            },
            AccessLevel.USER_MODE
        );
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        // The direction may have changed since the run started; a run never works against it.
        if (OpportunityMirrorService.direction() != direction) {
            totals.skipped += scope.size();
            return;
        }
        totals.add(
            direction == OpportunityMirrorService.OPPORTUNITIES_TO_GIFTS
                ? OpportunityGiftService.makeGifts(scope)
                : OpportunityMirrorService.syncSaved((List<Gift__c>) scope)
        );
    }

    public void finish(Database.BatchableContext context) {
        if (direction == OpportunityMirrorService.OPPORTUNITIES_TO_GIFTS) {
            totals.writeOpportunityRefusals();
        } else {
            totals.writeRefusals();
        }
        ErrorLogger.logMessage(
            String.format(
                direction == OpportunityMirrorService.OPPORTUNITIES_TO_GIFTS
                    ? Label.Connect_OpportunityMirror_LogRunGifts
                    : Label.Connect_OpportunityMirror_LogRunOpportunities,
                new List<Object>{
                    totals.created,
                    totals.updated,
                    totals.unchanged,
                    totals.failed,
                    totals.skipped
                }
            ),
            LOG_CONTEXT,
            SEVERITY_INFO
        );
    }
}

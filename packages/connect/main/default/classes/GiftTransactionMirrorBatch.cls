/**
 * A run of the Gift Transaction mirror (feature X-07, R-GT5), as the person who started or
 * scheduled it, in chunks. What it does follows the chosen direction:
 *
 * - Gifts to Gift Transactions: copies every gift of R-GT3 that has no Gift Transaction yet, and
 *   every linked one changed since the last completed run started, or, from the reconciliation
 *   page, every gift of R-GT3 dated in a range.
 * - Gift Transactions to Gifts: makes a gift from every Gift Transaction of the paid status dated
 *   on or after the start date that no gift names (R-GT6).
 *
 * Refusals are gathered across the chunks and written when the run ends, one Warning per distinct
 * reason, with a summary at Info (R-GT7).
 *
 * A run does nothing, and says so in one entry, while the mirror is unavailable (R-GT1), while its
 * paid status or start date is missing or unknown (R-GT2), or while automation is paused or the
 * Gift Transaction mirror is switched off on the Automation page. The pause and the switch are
 * checked again for each chunk, and so is the headroom a chunk needs. A run that is not a range
 * records when it started and its summary on Connect Settings, for the page, for Health Check, and
 * as the point from which the next run rechecks linked gifts changed since.
 */
public with sharing class GiftTransactionMirrorBatch implements Database.Batchable<SObject>, Database.Stateful {
    public static final String CLASS_NAME = 'GiftTransactionMirrorBatch';
    /** Nonprofit Cloud's own fundraising automation runs on each chunk, as NPSP's does in X-01. */
    @TestVisible
    private static final Integer CHUNK_SIZE = 100;
    public static final String LOG_CONTEXT = 'Gift Transaction mirror: run';
    // Core's constant for this severity is not namespace accessible, so its value is repeated.
    private static final String SEVERITY_INFO = 'Info';

    /**
     * What one chunk costs at most: two reads (the linked records, the time zone) and four writes
     * (insert, update, links, clean-up), with the shares of the limits ADR-0058 decision 3 leaves
     * for the org's own automation.
     */
    private static final Integer QUERIES_NEEDED = 2;
    private static final Integer DML_STATEMENTS_NEEDED = 4;
    private static final Decimal CPU_SHARE_NEEDED = 0.4;
    private static final Decimal LIMIT_SHARE_NEEDED = 0.5;

    private final String direction;
    private final Date fromDate;
    private final Date toDate;
    private final GiftTransactionMirrorService.Result totals = new GiftTransactionMirrorService.Result();
    private Datetime startedAt;
    /** Why chunks were left, when automation was paused or switched off during the run. */
    private String skipReason;
    private Boolean skippedAtStart = false;
    private String skipSeverity = SEVERITY_INFO;
    private Boolean noHeadroom = false;

    @TestVisible
    private GiftTransactionMirrorBatch(String direction, Date fromDate, Date toDate) {
        this.direction = direction;
        this.fromDate = fromDate;
        this.toDate = toDate;
    }

    /** Starts a run in the chosen direction and returns its job id, or null when it is off. */
    public static Id run() {
        String direction = GiftTransactionMirrorService.direction();
        if (
            direction == GiftTransactionMirrorService.OFF ||
            !GiftTransactionMirrorService.isAvailable()
        ) {
            return null;
        }
        return Database.executeBatch(
            new GiftTransactionMirrorBatch(direction, null, null),
            CHUNK_SIZE
        );
    }

    /** Copies again every gift of R-GT3 dated in the range (Gifts to Gift Transactions only). */
    public static Id runRange(Date fromDate, Date toDate) {
        return Database.executeBatch(
            new GiftTransactionMirrorBatch(
                GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS,
                fromDate,
                toDate
            ),
            CHUNK_SIZE
        );
    }

    /** Why a chunk must not work now, or null when it may. */
    private static String pauseReason() {
        if (AutomationControl.isPaused()) {
            return Label.Connect_GiftTransactionMirror_RunPaused;
        }
        if (!AutomationControl.isEnabled(GiftTransactionMirrorService.AUTOMATION_NAME)) {
            return Label.Connect_GiftTransactionMirror_RunSwitchedOff;
        }
        return null;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        startedAt = System.now();
        skipReason = pauseReason();
        if (skipReason == null && !GiftTransactionMirrorService.isAvailable()) {
            skipReason = Label.Connect_GiftTransactionMirror_Unavailable;
        }
        if (skipReason == null) {
            String notReady = GiftTransactionMirrorService.notReadyReason();
            if (notReady != null) {
                // Scheduled while set, then cleared or mistyped: worth a Warning, not an Info.
                skipReason = String.format(
                    Label.Connect_GiftTransactionMirror_RunNotReady,
                    new List<Object>{ notReady }
                );
                skipSeverity = ErrorLogger.SEVERITY_WARNING;
            } else if (!GiftTransactionMirrorService.canRun(direction)) {
                // The person who scheduled it lost access: say so rather than fail on a query.
                skipReason = String.format(
                    Label.Connect_GiftTransactionMirror_RunNotReady,
                    new List<Object>{ Label.Connect_GiftTransactionMirror_NoAccess }
                );
                skipSeverity = ErrorLogger.SEVERITY_WARNING;
            }
        }
        if (skipReason != null) {
            skippedAtStart = true;
            return nothing();
        }
        Date startDate = GiftTransactionMirrorService.startDate();
        if (direction == GiftTransactionMirrorService.GIFT_TRANSACTIONS_TO_GIFTS) {
            return Database.getQueryLocatorWithBinds(
                GiftTransactionMirrorSelector.giftTransactionsToGiftsQuery(
                    GiftTransactionMirrorSchema.objectName(),
                    GiftTransactionMirrorSchema.READ
                ),
                new Map<String, Object>{
                    'status' => GiftTransactionMirrorService.paidStatus(),
                    'startDate' => startDate
                },
                AccessLevel.USER_MODE
            );
        }
        Datetime lastRun = Connect_Settings__c.getOrgDefaults()
            ?.Gift_Transaction_Mirror_Last_Run__c;
        return Database.getQueryLocatorWithBinds(
            GiftTransactionMirrorSelector.giftsToCopyQuery(fromDate != null, lastRun != null),
            new Map<String, Object>{
                'statuses' => GiftTransactionMirrorService.MIRRORED_STATUSES,
                'inKind' => GiftTransactionMirrorService.TYPE_IN_KIND,
                'startDate' => startDate,
                'fromDate' => fromDate,
                'toDate' => toDate,
                'since' => lastRun
            },
            AccessLevel.USER_MODE
        );
    }

    private static Database.QueryLocator nothing() {
        return Database.getQueryLocator([SELECT Id FROM Gift__c WHERE Id = NULL WITH USER_MODE]);
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        // The direction may have changed since the run started; a run never works against it.
        String reason = pauseReason();
        if (reason != null || GiftTransactionMirrorService.direction() != direction) {
            totals.skipped += scope.size();
            skipReason = skipReason == null ? reason : skipReason;
            return;
        }
        if (!hasHeadroom(scope.size())) {
            // Left for the next run rather than failed halfway through (R-GT5).
            totals.skipped += scope.size();
            noHeadroom = true;
            return;
        }
        totals.add(
            direction == GiftTransactionMirrorService.GIFT_TRANSACTIONS_TO_GIFTS
                ? GiftTransactionGiftService.makeGifts(scope)
                : GiftTransactionMirrorService.copyGifts((List<Gift__c>) scope)
        );
    }

    /** Whether this chunk still has room: a gift can cost a write, its link, and a clean-up. */
    @TestVisible
    private static Boolean hasHeadroom(Integer records) {
        return ConnectSync.hasHeadroom(
            QUERIES_NEEDED,
            DML_STATEMENTS_NEEDED,
            3 * records,
            CPU_SHARE_NEEDED,
            LIMIT_SHARE_NEEDED
        );
    }

    public void finish(Database.BatchableContext context) {
        if (skippedAtStart) {
            ErrorLogger.logMessage(skipReason, LOG_CONTEXT, skipSeverity);
            return;
        }
        if (direction == GiftTransactionMirrorService.GIFT_TRANSACTIONS_TO_GIFTS) {
            totals.writeGiftTransactionRefusals();
        } else {
            totals.writeRefusals();
        }
        if (noHeadroom) {
            ErrorLogger.logMessage(
                Label.Connect_GiftTransactionMirror_LogNoHeadroom,
                LOG_CONTEXT,
                ErrorLogger.SEVERITY_WARNING
            );
        }
        String summary = String.format(
            direction == GiftTransactionMirrorService.GIFT_TRANSACTIONS_TO_GIFTS
                ? Label.Connect_GiftTransactionMirror_LogRunGifts
                : Label.Connect_GiftTransactionMirror_LogRunGiftTransactions,
            new List<Object>{
                totals.created,
                totals.updated,
                totals.unchanged,
                totals.failed,
                totals.skipped
            }
        );
        ErrorLogger.logMessage(
            skipReason == null ? summary : summary + ' ' + skipReason,
            LOG_CONTEXT,
            SEVERITY_INFO
        );
        // A run that left chunks is not complete: the next one rechecks from the last that was.
        if (fromDate == null && skipReason == null && totals.skipped == 0) {
            ConnectSettingsWriter.recordGiftTransactionMirrorRun(startedAt, summary);
        }
    }
}

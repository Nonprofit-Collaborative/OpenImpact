/**
 * The class Core finds by name (in `HealthCheckExtensions.EXTENSION_CLASSES`) and calls to add
 * Connect's findings to the one Health Check report (ADR-0057, as the ADR on the Opportunity
 * mirror amends it; X-01, R-OM8; X-07, R-GT5).
 *
 * One finding per mirror: its nightly run is scheduled, a direction is chosen and the automation
 * is switched on, yet no run has completed for more than two days. A run executes as the person
 * who scheduled it, so when that person is deactivated or loses access every run fails before it
 * starts and nothing else says so. Asked only of a viewer who may manage settings, as Core's own
 * settings checks are. The Gift Transaction mirror's finding reads its direction before anything
 * else, so an org without Nonprofit Cloud, where it is off, makes no describe for it.
 *
 * `@NamespaceAccessible` for the reason `GivingHealthCheckExtension` is: Core resolves it with
 * `Type.forName` under ADR-0017.
 */
@NamespaceAccessible
public with sharing class ConnectHealthCheckExtension implements HealthCheckExtension {
    public static final String MIRROR_STALE_KEY = 'opportunity_mirror_not_run';
    public static final String GIFT_TRANSACTION_STALE_KEY = 'gift_transaction_mirror_not_run';
    private static final Integer STALE_DAYS = 2;

    /** Test seam: the moment the report is read. */
    @TestVisible
    private static Datetime nowForTest;

    public List<HealthCheckService.Finding> findings() {
        List<HealthCheckService.Finding> found = new List<HealthCheckService.Finding>();
        if (!HealthCheckService.canManageSettings()) {
            return found;
        }
        HealthCheckService.Finding stale = staleMirrorRun();
        if (stale != null) {
            found.add(stale);
        }
        HealthCheckService.Finding staleGiftTransactions = staleGiftTransactionRun();
        if (staleGiftTransactions != null) {
            found.add(staleGiftTransactions);
        }
        return found;
    }

    private static HealthCheckService.Finding staleMirrorRun() {
        if (
            !OpportunityMirrorService.isAvailable() ||
            OpportunityMirrorService.direction() == OpportunityMirrorService.OFF ||
            !AutomationControl.isEnabled(OpportunityMirrorService.AUTOMATION_NAME)
        ) {
            return null;
        }
        Datetime since = staleSince(
            OpportunityMirrorSchedulable.scheduledAt(),
            Connect_Settings__c.getOrgDefaults()?.Opportunity_Mirror_Last_Run__c
        );
        if (since == null) {
            return null;
        }
        return new HealthCheckService.Finding(
            MIRROR_STALE_KEY,
            Label.Connect_HealthCheck_MirrorNotRunTitle,
            String.format(
                Label.Connect_HealthCheck_MirrorNotRunDetail,
                new List<Object>{ since.format() }
            ),
            HealthCheckService.SEVERITY_WARNING,
            HealthCheckService.CATEGORY_SETTINGS
        );
    }

    private static HealthCheckService.Finding staleGiftTransactionRun() {
        if (
            GiftTransactionMirrorService.direction() == GiftTransactionMirrorService.OFF ||
            !GiftTransactionMirrorService.isAvailable() ||
            !AutomationControl.isEnabled(GiftTransactionMirrorService.AUTOMATION_NAME)
        ) {
            return null;
        }
        Datetime since = staleSince(
            GiftTransactionMirrorSchedulable.scheduledAt(),
            Connect_Settings__c.getOrgDefaults()?.Gift_Transaction_Mirror_Last_Run__c
        );
        if (since == null) {
            return null;
        }
        return new HealthCheckService.Finding(
            GIFT_TRANSACTION_STALE_KEY,
            Label.Connect_HealthCheck_GiftTransactionMirrorNotRunTitle,
            String.format(
                Label.Connect_HealthCheck_GiftTransactionMirrorNotRunDetail,
                new List<Object>{ since.format() }
            ),
            HealthCheckService.SEVERITY_WARNING,
            HealthCheckService.CATEGORY_SETTINGS
        );
    }

    /**
     * Since when a scheduled run has not completed, when that is more than two days ago; null when
     * the run is not scheduled or has completed since.
     */
    private static Datetime staleSince(Datetime scheduledAt, Datetime lastRun) {
        if (scheduledAt == null) {
            return null;
        }
        // A run recorded before the job was scheduled says nothing about this schedule.
        Datetime since = lastRun == null || lastRun < scheduledAt ? scheduledAt : lastRun;
        Datetime now = nowForTest != null ? nowForTest : System.now();
        return since.addDays(STALE_DAYS) > now ? null : since;
    }
}

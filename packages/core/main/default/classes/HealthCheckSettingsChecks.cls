/**
 * The Health Check questions about how Open Impact is set up and what it has been doing:
 * whether automation is paused (and whether anything will end the pause), whether the two
 * fiscal years agree, whether receipt generation has been failing, and whether anything is
 * waiting in the Error Log
 * (plan Section 4.8, feature C-11). Since C-21 it also asks whether the package defaults
 * materialized from shipped metadata are all here, and whether the nightly rollup run is
 * scheduled when a rollup needs it; those four findings carry a fix button (ADR-0048).
 *
 * Two of these reach data that belongs to the Giving package. Neither reaches it at compile
 * time: ReceiptGapSelector and FiscalYearSelector answer dynamically, so a Platform-only org
 * without Giving is told nothing rather than told zero (ADR-0009, ADR-0013).
 *
 * Every finding is created exactly as HealthCheckService created it before ADR-0039 moved
 * it here: same keys, same severities, same categories, same labels, same fix targets.
 */
public with sharing class HealthCheckSettingsChecks {
    /**
     * How many reconciled receipt numbers are ordinary. One number consumed by a failed run
     * is the mechanism working (R-RC3); more than one is generation failing repeatedly with
     * nobody watching.
     */
    private static final Integer RECEIPT_FAILURES_EXPECTED = 1;

    /** Whether automation is running or paused, said out loud either way. */
    public class AutomationCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return automationFinding();
        }
    }

    /** Whether the fiscal year in Setup and the one in Nonprofit Settings agree. */
    public class FiscalYearCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return fiscalYearFinding();
        }
    }

    /** Receipt numbers consumed by runs that failed. */
    public class ReceiptGenerationCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return receiptGenerationFinding();
        }
    }

    /** How many Error Log rows nobody has read yet. */
    public class ErrorLogCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return errorLogFinding();
        }
    }

    /**
     * Shipped rollups this org does not have (ADR-0006, ADR-0048). A shipped total that one of
     * the administrator's own active totals already writes is not restored, and the finding
     * says so rather than hiding it.
     */
    public class ShippedRollupsCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            HealthCheckService.Finding finding = missingDefaultsFinding(
                'shipped_rollups_missing',
                HealthCheckService.FIX_KEY_RESTORE_ROLLUPS,
                System.Label.Core_HealthCheck_RollupsMissingTitle,
                System.Label.Core_HealthCheck_RollupsMissingDetail,
                HealthCheckService.SEVERITY_WARNING
            );
            if (finding == null) {
                return null;
            }
            List<String> skipped = RollupService.skippedDefaultNames();
            if (!skipped.isEmpty()) {
                finding.detail +=
                    ' ' +
                    String.format(
                        System.Label.Core_HealthCheck_RollupsSkippedDetail,
                        new List<Object>{ String.join(skipped, ', ') }
                    );
            }
            return finding.withFix(
                System.Label.Core_HealthCheck_RollupsMissingFix,
                HealthCheckService.FIX_ACTION_PREFIX + HealthCheckService.FIX_KEY_RESTORE_ROLLUPS
            );
        }
    }

    /** Shipped automations with no switch on the Automation page. */
    public class AutomationSwitchesCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return missingDefaultsFinding(
                    'automation_switches_missing',
                    HealthCheckService.FIX_KEY_RESTORE_AUTOMATION_SWITCHES,
                    System.Label.Core_HealthCheck_SwitchesMissingTitle,
                    System.Label.Core_HealthCheck_SwitchesMissingDetail,
                    HealthCheckService.SEVERITY_INFO
                )
                ?.withFix(
                    System.Label.Core_HealthCheck_SwitchesMissingFix,
                    HealthCheckService.FIX_ACTION_PREFIX +
                    HealthCheckService.FIX_KEY_RESTORE_AUTOMATION_SWITCHES
                );
        }
    }

    /** Shipped import templates this org does not have. */
    public class ImportTemplatesCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return missingDefaultsFinding(
                    'import_templates_missing',
                    HealthCheckService.FIX_KEY_RESTORE_IMPORT_TEMPLATES,
                    System.Label.Core_HealthCheck_TemplatesMissingTitle,
                    System.Label.Core_HealthCheck_TemplatesMissingDetail,
                    HealthCheckService.SEVERITY_INFO
                )
                ?.withFix(
                    System.Label.Core_HealthCheck_TemplatesMissingFix,
                    HealthCheckService.FIX_ACTION_PREFIX +
                    HealthCheckService.FIX_KEY_RESTORE_IMPORT_TEMPLATES
                );
        }
    }

    /** Active rollups waiting on a nightly run nobody has scheduled. */
    public class NightlyRollupsCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return nightlyRollupsFinding();
        }
    }

    /**
     * One finding naming the package defaults that are missing, or null when none is. The
     * title and detail take the count as {0} and the names as {1}, so the finding says what
     * its fix will create, counted from this org, and it carries the same names as its fix
     * scope, so the fix creates exactly those (ADR-0048 condition 5).
     */
    private static HealthCheckService.Finding missingDefaultsFinding(
        String key,
        String fixKey,
        String title,
        String detail,
        String severity
    ) {
        List<String> missingNames = HealthCheckService.fixScope(fixKey);
        if (missingNames == null || missingNames.isEmpty()) {
            return null;
        }
        List<Object> values = new List<Object>{
            String.valueOf(missingNames.size()),
            String.join(missingNames, ', ')
        };
        return new HealthCheckService.Finding(
                key,
                String.format(title, values),
                String.format(detail, values),
                severity,
                HealthCheckService.CATEGORY_SETTINGS
            )
            .withScope(missingNames);
    }

    /**
     * Rollups set to recalculate in the nightly run while the run is not scheduled. A rollup
     * set to Scheduled alone is then never recalculated, which is a warning; one set to Both
     * still updates as records change and only misses the nightly correction, which is
     * information.
     */
    private static HealthCheckService.Finding nightlyRollupsFinding() {
        if (RollupScheduler.isScheduled()) {
            return null;
        }
        List<Rollup_Definition__c> waiting = RollupSelector.selectActiveForModes(
            RollupService.scheduledModes()
        );
        if (waiting.isEmpty()) {
            return null;
        }
        Integer nightlyOnly = 0;
        for (Rollup_Definition__c definition : waiting) {
            if (RollupService.MODE_SCHEDULED.equals(definition.Mode__c)) {
                nightlyOnly++;
            }
        }
        List<Object> values = new List<Object>{
            String.valueOf(waiting.size()),
            String.valueOf(nightlyOnly)
        };
        return new HealthCheckService.Finding(
                'nightly_rollups_not_scheduled',
                System.Label.Core_HealthCheck_NightlyOffTitle,
                String.format(System.Label.Core_HealthCheck_NightlyOffDetail, values),
                nightlyOnly > 0
                    ? HealthCheckService.SEVERITY_WARNING
                    : HealthCheckService.SEVERITY_INFO,
                HealthCheckService.CATEGORY_SETTINGS
            )
            .withFix(
                System.Label.Core_HealthCheck_NightlyOffFix,
                HealthCheckService.FIX_ACTION_PREFIX +
                HealthCheckService.FIX_KEY_SCHEDULE_NIGHTLY_ROLLUPS
            )
            .withScope(
                HealthCheckService.fixScope(HealthCheckService.FIX_KEY_SCHEDULE_NIGHTLY_ROLLUPS)
            );
    }

    private static HealthCheckService.Finding automationFinding() {
        Nonprofit_Settings__c settings = SettingsService.getSettings();
        Datetime pausedUntil = settings == null ? null : settings.Automation_Paused_Until__c;
        if (pausedUntil == null || pausedUntil <= System.now()) {
            return new HealthCheckService.Finding(
                'automation_running',
                System.Label.Core_HealthCheck_AutomationRunningTitle,
                System.Label.Core_HealthCheck_AutomationRunningDetail,
                HealthCheckService.SEVERITY_INFO,
                HealthCheckService.CATEGORY_SETTINGS
            );
        }

        // A pause nothing will end on time is a warning rather than information: it was set
        // before automatic resume existed, or somewhere other than the Automation page (R-A5).
        Boolean withoutResume = AutomationControl.isPauseWithoutResume();
        String detail = String.format(
            withoutResume
                ? System.Label.Core_HealthCheck_PausedNoResumeDetail
                : System.Label.Core_HealthCheck_AutomationPausedDetail,
            new List<Object>{ pausedUntil.format() }
        );
        return new HealthCheckService.Finding(
                withoutResume ? 'automation_paused_no_resume' : 'automation_paused',
                withoutResume
                    ? System.Label.Core_HealthCheck_PausedNoResumeTitle
                    : System.Label.Core_HealthCheck_AutomationPausedTitle,
                detail,
                withoutResume
                    ? HealthCheckService.SEVERITY_WARNING
                    : HealthCheckService.SEVERITY_INFO,
                HealthCheckService.CATEGORY_SETTINGS
            )
            .withFix(
                System.Label.Core_HealthCheck_AutomationFix,
                HealthCheckService.SECTION_AUTOMATION
            );
    }

    /**
     * Whether the fiscal year in Setup and the one in Nonprofit Settings start in the same
     * month (ADR-0025). They have to: the rollups are computed from the setting and the
     * packaged retention reports are filtered on Setup's fiscal year date literals, so a
     * disagreement makes every year based number quietly measure a different window.
     */
    private static HealthCheckService.Finding fiscalYearFinding() {
        Integer orgMonth = FiscalYearSelector.orgFiscalYearStartMonth();
        Integer settingsMonth = FiscalYearSelector.settingsFiscalYearStartMonth();
        if (orgMonth == null || settingsMonth == null || orgMonth == settingsMonth) {
            return null;
        }

        String detail = String.format(
            System.Label.Core_HealthCheck_FiscalYearMismatchDetail,
            new List<Object>{
                FiscalYearSelector.monthName(settingsMonth),
                FiscalYearSelector.monthName(orgMonth)
            }
        );
        return new HealthCheckService.Finding(
                'fiscal_year_mismatch',
                System.Label.Core_HealthCheck_FiscalYearMismatchTitle,
                detail,
                HealthCheckService.SEVERITY_WARNING,
                HealthCheckService.CATEGORY_SETTINGS
            )
            .withFix(
                System.Label.Core_HealthCheck_FiscalYearFix,
                HealthCheckService.SECTION_GENERAL
            );
    }

    /**
     * Receipt numbers consumed by a run that failed (R-RC3). One is the reconciliation
     * mechanism doing its job and is reported as information; more than one is receipt
     * generation failing repeatedly, which is a warning because the donors are waiting.
     *
     * An org without the Giving package cannot answer the question at all, and is told
     * nothing rather than told zero.
     */
    private static HealthCheckService.Finding receiptGenerationFinding() {
        ReceiptGapSelector.Result failures = ReceiptGapSelector.generationFailures();
        if (failures == null || failures.available != true || failures.count <= 0) {
            return null;
        }

        if (failures.count <= RECEIPT_FAILURES_EXPECTED) {
            return new HealthCheckService.Finding(
                    'receipt_generation_failed_once',
                    System.Label.Core_HealthCheck_ReceiptFailedOneTitle,
                    System.Label.Core_HealthCheck_ReceiptFailedOneDetail,
                    HealthCheckService.SEVERITY_INFO,
                    HealthCheckService.CATEGORY_SETTINGS
                )
                .withFix(
                    System.Label.Core_HealthCheck_ErrorLogFix,
                    ErrorLogCountSelector.listViewUrl()
                );
        }

        List<Object> count = new List<Object>{ String.valueOf(failures.count) };
        return new HealthCheckService.Finding(
                'receipt_generation_failed',
                String.format(System.Label.Core_HealthCheck_ReceiptFailedManyTitle, count),
                String.format(System.Label.Core_HealthCheck_ReceiptFailedManyDetail, count),
                HealthCheckService.SEVERITY_WARNING,
                HealthCheckService.CATEGORY_SETTINGS
            )
            .withFix(
                System.Label.Core_HealthCheck_ErrorLogFix,
                ErrorLogCountSelector.listViewUrl()
            );
    }

    private static HealthCheckService.Finding errorLogFinding() {
        Integer newErrors = ErrorLogCountSelector.countNew();
        if (newErrors <= 0) {
            return null;
        }

        List<Object> count = new List<Object>{ String.valueOf(newErrors) };
        return new HealthCheckService.Finding(
                'error_log_new',
                String.format(System.Label.Core_HealthCheck_ErrorLogTitle, count),
                String.format(System.Label.Core_HealthCheck_ErrorLogDetail, count),
                HealthCheckService.SEVERITY_WARNING,
                HealthCheckService.CATEGORY_SETTINGS
            )
            .withFix(
                System.Label.Core_HealthCheck_ErrorLogFix,
                ErrorLogCountSelector.listViewUrl()
            );
    }
}

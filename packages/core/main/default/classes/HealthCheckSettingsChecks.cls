/**
 * The Health Check questions about how Open Impact is set up and what it has been doing:
 * whether automation is paused, whether the two fiscal years agree, whether receipt
 * generation has been failing, and whether anything is waiting in the Error Log
 * (plan Section 4.8, feature C-11).
 *
 * Two of these reach data that belongs to the Giving package. Neither reaches it at compile
 * time: ReceiptGapSelector and FiscalYearSelector answer dynamically, so a Platform-only org
 * without Giving is told nothing rather than told zero (ADR-0009, ADR-0013).
 *
 * Every finding is created exactly as HealthCheckService created it before ADR-0031 moved
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

        String detail = String.format(
            System.Label.Core_HealthCheck_AutomationPausedDetail,
            new List<Object>{ pausedUntil.format() }
        );
        return new HealthCheckService.Finding(
                'automation_paused',
                System.Label.Core_HealthCheck_AutomationPausedTitle,
                detail,
                HealthCheckService.SEVERITY_INFO,
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

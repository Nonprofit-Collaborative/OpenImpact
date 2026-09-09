/**
 * Health Check: what this org looks like, whether Open Impact is set up to match, who can
 * get in, and what is currently in the way (plan Section 4.8, feature C-11).
 *
 * This class holds the vocabulary every check shares (the Finding, the severities, the
 * categories, the fix targets), the order the checks are read in, and the report the panel
 * receives. What each check actually says lives in one of three classes grouped by the
 * question it asks, so adding a check means reading one of them rather than all of them
 * (ADR-0031):
 *
 * - HealthCheckOrgShapeChecks: what is installed, and whether the mode matches it.
 * - HealthCheckAccessChecks: who administers the app, who cannot see it, who holds the
 *   receipt lock override. Only asked of a viewer who may manage settings.
 * - HealthCheckSettingsChecks: automation, fiscal year, receipt generation, Error Log.
 *
 * Every check is isolated. A check that throws becomes a finding of its own and is written
 * to the Error Log; the other checks still run, because a report that hides eight answers
 * because the ninth failed is worse than no report.
 *
 * Every string an administrator reads comes from a Custom Label.
 */
public with sharing class HealthCheckService {
    public static final String SEVERITY_INFO = 'Info';
    public static final String SEVERITY_WARNING = 'Warning';
    public static final String SEVERITY_ERROR = 'Error';

    public static final String CATEGORY_ORG_SHAPE = 'OrgShape';
    public static final String CATEGORY_LICENSES = 'Licenses';
    public static final String CATEGORY_ACCESS = 'Access';
    public static final String CATEGORY_SETTINGS = 'Settings';

    /**
     * A fix target is one of three things, and the component tells them apart by shape:
     * a value starting with "action:" is a method on the controller, a value starting with
     * "/" is a relative URL to navigate to, and anything else names a section of the
     * settings console. Null means there is nothing to click.
     */
    public static final String FIX_ACTION_PREFIX = 'action:';
    public static final String FIX_APPLY_RECOMMENDED_MODE = 'action:applyRecommendedMode';
    public static final String FIX_APPLY_JUNCTION_MEMBERSHIP = 'action:applyJunctionMembership';

    /** The settings console tab that hosts every section a fix can point at. */
    public static final String SETTINGS_TAB = 'Nonprofit_Settings';

    /** The page state parameter that tells the console which section to open. */
    public static final String SECTION_STATE_PARAMETER = 'section';

    public static final String SECTION_GENERAL = 'General';
    public static final String SECTION_HOUSEHOLDS = 'Households';
    public static final String SECTION_ACCESS = 'Access';
    public static final String SECTION_AUTOMATION = 'Automation';

    /**
     * The developer names of the packaged permission set groups (the roles the Access page
     * assigns) that mean "this person uses Open Impact", and the permission set that means
     * "this person administers it". See packages/core/integration/c-07-c-11.permissions.md.
     */
    public static final String GROUP_ADMIN = 'Nonprofit_Admin_Group';
    public static final String PERMISSION_SET_ADMIN = 'Nonprofit_Admin';
    public static final Set<String> NONPROFIT_GROUPS = new Set<String>{
        GROUP_ADMIN,
        'Fundraising_Staff',
        'Program_Staff',
        'Volunteer_Coordinator',
        'Read_Only'
    };

    /**
     * The packaged permission sets themselves. An administrator who assigned one of these
     * directly, rather than through a role, has still given that person the app.
     */
    public static final Set<String> NONPROFIT_PERMISSION_SETS = new Set<String>{
        PERMISSION_SET_ADMIN,
        'Nonprofit_Staff',
        'Nonprofit_Read_Only'
    };

    /**
     * The custom permission that lifts the receipt lock (ADR-0024). It ships in the Giving
     * package, assigned to nobody, and is meant to be granted in Setup for one correction and
     * removed again. Core never compiles against Giving: this is a String handed to
     * CustomPermissionSelector, which asks the platform's own setup objects who holds it, so
     * an org without Giving answers "nobody" rather than failing.
     */
    public static final String OVERRIDE_RECEIPT_LOCK = 'Override_Receipt_Lock';

    /**
     * Where Setup lists custom permissions. The fix for a standing override assignment is
     * deliberately in Setup and not in the settings console, because ADR-0024 keeps lifting
     * the receipt lock out of the console on purpose.
     */
    public static final String FIX_CUSTOM_PERMISSIONS_URL = '/lightning/setup/CustomPermissions/home';

    /**
     * The custom permission that gates changing settings and reading who else is in the org.
     * Declared once, next to the setting it protects.
     */
    public static final String MANAGE_SETTINGS = CoexistenceService.MANAGE_SETTINGS;

    /**
     * Test injection points, null in every real transaction: a check that always throws, and
     * an exception for the Error Log call to throw. Between them they prove that one failing
     * check, and a logger that is itself broken, still leave the rest of the report standing.
     */
    @TestVisible
    private static Check faultInjection;

    @TestVisible
    private static Exception loggerFault;

    /**
     * Where the two access counts come from. Injected in tests so that the findings are
     * asserted against numbers the test chose, not against whichever people and permission
     * sets happen to exist in the org the tests run in.
     */
    @TestVisible
    private static AccessCounts accessCountsOverride;

    /** One thing Health Check has to say about this org. */
    public class Finding {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public String title;
        @AuraEnabled
        public String detail;
        @AuraEnabled
        public String severity;
        @AuraEnabled
        public String fixLabel;
        @AuraEnabled
        public String fixTarget;
        @AuraEnabled
        public String category;

        public Finding(String key, String title, String detail, String severity, String category) {
            this.key = key;
            this.title = title;
            this.detail = detail;
            this.severity = severity;
            this.category = category;
        }

        public Finding withFix(String fixLabel, String fixTarget) {
            this.fixLabel = fixLabel;
            this.fixTarget = fixTarget;
            return this;
        }
    }

    /** Everything the panel needs in one round trip. */
    public class Report {
        @AuraEnabled
        public List<Finding> findings;
        @AuraEnabled
        public OrgShapeDetector.OrgShape orgShape;
        @AuraEnabled
        public String orgShapeSummary;
        @AuraEnabled
        public String currentMode;
        @AuraEnabled
        public String currentModeLabel;
        @AuraEnabled
        public String recommendedMode;
        @AuraEnabled
        public String recommendedModeLabel;
        @AuraEnabled
        public Boolean modeNeedsAttention;
        @AuraEnabled
        public Boolean canManageSettings;

        /**
         * The API name of the settings console tab, and the page state key a section fix has
         * to use, both carrying whatever namespace this org runs under. The component never
         * builds these itself (see docs/contributor-guide/environment.md, "Namespace
         * registration").
         */
        @AuraEnabled
        public String settingsTabApiName;
        @AuraEnabled
        public String sectionStateKey;

        public Report() {
            this.findings = new List<Finding>();
            this.modeNeedsAttention = false;
            this.canManageSettings = false;
            this.settingsTabApiName = NamespaceUtil.qualify(SETTINGS_TAB);
            this.sectionStateKey = NamespaceUtil.stateKey(SECTION_STATE_PARAMETER);
        }
    }

    /**
     * One check. Returning null means there is nothing to report, which is the normal case
     * for most of them.
     */
    public interface Check {
        Finding run();
    }

    /**
     * How many people administer Open Impact, and how many active people cannot see it at
     * all. Both are questions about the whole org, which is why only an administrator is
     * allowed to ask them.
     */
    public interface AccessCounts {
        Integer administrators();
        Integer usersWithoutAccess();
    }

    /** The real counts, read from the org. */
    private class OrgAccessCounts implements AccessCounts {
        public Integer administrators() {
            return UserAccessSelector.countActiveAssignees(new Set<String>{ GROUP_ADMIN }) +
                UserAccessSelector.countActiveDirectAssignees(
                    new Set<String>{ PERMISSION_SET_ADMIN }
                );
        }

        public Integer usersWithoutAccess() {
            Set<Id> assigned = UserAccessSelector.getAssignedUserIds(NONPROFIT_GROUPS);
            assigned.addAll(
                UserAccessSelector.getPermissionSetAssigneeIds(NONPROFIT_PERMISSION_SETS)
            );
            return UserAccessSelector.countActiveStandardUsersExcluding(assigned);
        }
    }

    private static AccessCounts accessCounts() {
        return accessCountsOverride == null ? new OrgAccessCounts() : accessCountsOverride;
    }

    /** A check and the key its failure is reported under. */
    private class CheckStep {
        private final String key;
        private final Check check;

        private CheckStep(String key, Check check) {
            this.key = key;
            this.check = check;
        }
    }

    /**
     * Every finding, in the order an administrator should read them.
     *
     * A check that throws becomes one finding of its own; the rest still run, because a
     * report that hides eight answers because the ninth failed is worse than no report.
     */
    public static List<Finding> run() {
        List<Finding> findings = new List<Finding>();

        for (CheckStep step : steps()) {
            try {
                Finding finding = step.check.run();
                if (finding != null) {
                    findings.add(finding);
                }
            } catch (Exception e) {
                findings.add(checkFailed(step.key, e));
            }
        }

        return findings;
    }

    /**
     * The checks to run, in reading order. The access and Error Log counts are only asked
     * for when the viewer can actually see the answer: a person without the administrator
     * permission sees their own permission set assignments and nothing else, and a count
     * taken from that is confidently wrong, which is worse than no count at all.
     */
    private static List<CheckStep> steps() {
        List<CheckStep> steps = new List<CheckStep>();
        if (faultInjection != null) {
            steps.add(new CheckStep('injected', faultInjection));
        }

        steps.add(new CheckStep('org_shape', new HealthCheckOrgShapeChecks.OrgShapeCheck()));
        steps.add(
            new CheckStep('coexistence_mode', new HealthCheckOrgShapeChecks.CoexistenceModeCheck())
        );
        steps.add(
            new CheckStep('membership_mode', new HealthCheckOrgShapeChecks.MembershipModeCheck())
        );
        steps.add(
            new CheckStep('connect_module', new HealthCheckOrgShapeChecks.ConnectModuleCheck())
        );
        steps.add(
            new CheckStep('multi_currency', new HealthCheckOrgShapeChecks.MultiCurrencyCheck())
        );

        if (canManageSettings()) {
            steps.add(
                new CheckStep(
                    'nonprofit_admin',
                    new HealthCheckAccessChecks.NoAdminCheck(accessCounts())
                )
            );
            steps.add(
                new CheckStep(
                    'users_without_access',
                    new HealthCheckAccessChecks.UsersWithoutAccessCheck(accessCounts())
                )
            );
            steps.add(
                new CheckStep(
                    'override_receipt_lock',
                    new HealthCheckAccessChecks.OverrideReceiptLockCheck()
                )
            );
        } else {
            steps.add(
                new CheckStep(
                    'access_checks_need_admin',
                    new HealthCheckAccessChecks.NeedsAdminCheck()
                )
            );
        }

        steps.add(new CheckStep('automation', new HealthCheckSettingsChecks.AutomationCheck()));
        steps.add(new CheckStep('fiscal_year', new HealthCheckSettingsChecks.FiscalYearCheck()));
        steps.add(
            new CheckStep(
                'receipt_generation',
                new HealthCheckSettingsChecks.ReceiptGenerationCheck()
            )
        );

        if (canManageSettings()) {
            steps.add(new CheckStep('error_log', new HealthCheckSettingsChecks.ErrorLogCheck()));
        }

        return steps;
    }

    /**
     * Whether the viewer may change settings, which is also the permission that lets them
     * see who else is in the org.
     */
    public static Boolean canManageSettings() {
        return FeatureManagement.checkPermission(MANAGE_SETTINGS);
    }

    /**
     * The findings plus the context the panel shows above them.
     */
    public static Report buildReport() {
        Report report = new Report();
        report.findings = run();
        report.canManageSettings = canManageSettings();

        try {
            report.orgShape = OrgShapeDetector.detect();
            report.orgShapeSummary = detectedSummary(report.orgShape);
            report.recommendedMode = OrgShapeDetector.recommendedCoexistenceMode();
            report.recommendedModeLabel = modeLabel(report.recommendedMode);
        } catch (Exception e) {
            logQuietly(e);
        }

        try {
            report.currentMode = CoexistenceService.getCurrentMode();
            report.currentModeLabel = modeLabel(report.currentMode);
            report.modeNeedsAttention =
                String.isBlank(report.currentMode) ||
                (report.recommendedMode != null &&
                !report.recommendedMode.equals(report.currentMode));
        } catch (Exception e) {
            logQuietly(e);
        }

        return report;
    }

    /**
     * What was found, as a sentence an administrator can read out loud. The sentence itself
     * is built next to the org shape checks that also use it.
     */
    public static String detectedSummary(OrgShapeDetector.OrgShape shape) {
        return HealthCheckOrgShapeChecks.detectedSummary(shape);
    }

    private static Finding checkFailed(String checkKey, Exception e) {
        logQuietly(e);
        String detail = String.format(
            System.Label.Core_HealthCheck_CheckFailedDetail,
            new List<Object>{ checkKey }
        );
        return new Finding(
            'check_failed_' + checkKey,
            System.Label.Core_HealthCheck_CheckFailedTitle,
            detail,
            SEVERITY_WARNING,
            CATEGORY_SETTINGS
        );
    }

    /**
     * A mode's name as an administrator sees it.
     */
    public static String modeLabel(String mode) {
        if (CoexistenceService.MODE_AGENTFORCE_NONPROFIT.equals(mode)) {
            return System.Label.Core_CoexistenceMode_AgentforceNonprofit;
        }
        if (CoexistenceService.MODE_NPSP.equals(mode)) {
            return System.Label.Core_CoexistenceMode_Npsp;
        }
        if (CoexistenceService.MODE_STANDALONE.equals(mode)) {
            return System.Label.Core_CoexistenceMode_Standalone;
        }
        return System.Label.Core_CoexistenceMode_Unset;
    }

    /**
     * Write one failure to the Error Log without ever letting the writing of it become a
     * second failure. Canonical model R-E2: a failure to log is swallowed rather than masking
     * the original error.
     */
    private static void logQuietly(Exception e) {
        try {
            if (loggerFault != null) {
                throw loggerFault;
            }
            ErrorLogger.log(e, System.Label.Core_HealthCheck_ErrorContext);
        } catch (Exception loggingFailed) {
            System.debug(LoggingLevel.ERROR, loggingFailed);
        }
    }
}

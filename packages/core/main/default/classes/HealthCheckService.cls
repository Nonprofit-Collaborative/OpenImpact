/**
 * Health Check: what this org looks like, whether Open Impact is set up to match, who can
 * get in, and what is currently in the way (plan Section 4.8, feature C-11).
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
        'Nonprofit_Admin_Group',
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
        'Nonprofit_Admin',
        'Nonprofit_Staff',
        'Nonprofit_Read_Only'
    };

    /**
     * An Apex class the Connect package ships, used to tell whether Connect is installed
     * without referencing it at compile time.
     */
    private static final String CONNECT_MARKER_CLASS = 'ConnectService';

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

        public Report() {
            this.findings = new List<Finding>();
            this.modeNeedsAttention = false;
            this.canManageSettings = false;
        }
    }

    /**
     * Every finding, in the order an administrator should read them.
     */
    public static List<Finding> run() {
        List<Finding> findings = new List<Finding>();
        OrgShapeDetector.OrgShape shape = null;

        try {
            shape = OrgShapeDetector.detect();
            findings.add(orgShapeFinding(shape));
        } catch (Exception e) {
            findings.add(checkFailed('org_shape', e));
        }

        try {
            findings.add(coexistenceModeFinding(shape));
        } catch (Exception e) {
            findings.add(checkFailed('coexistence_mode', e));
        }

        try {
            Finding membership = membershipModeFinding(shape);
            if (membership != null) {
                findings.add(membership);
            }
        } catch (Exception e) {
            findings.add(checkFailed('membership_mode', e));
        }

        try {
            Finding connect = connectModuleFinding(shape);
            if (connect != null) {
                findings.add(connect);
            }
        } catch (Exception e) {
            findings.add(checkFailed('connect_module', e));
        }

        try {
            Finding currencyFinding = multiCurrencyFinding(shape);
            if (currencyFinding != null) {
                findings.add(currencyFinding);
            }
        } catch (Exception e) {
            findings.add(checkFailed('multi_currency', e));
        }

        try {
            Finding noAdmin = noAdminFinding();
            if (noAdmin != null) {
                findings.add(noAdmin);
            }
        } catch (Exception e) {
            findings.add(checkFailed('nonprofit_admin', e));
        }

        try {
            Finding withoutAccess = usersWithoutAccessFinding();
            if (withoutAccess != null) {
                findings.add(withoutAccess);
            }
        } catch (Exception e) {
            findings.add(checkFailed('users_without_access', e));
        }

        try {
            Finding paused = automationPausedFinding();
            if (paused != null) {
                findings.add(paused);
            }
        } catch (Exception e) {
            findings.add(checkFailed('automation_paused', e));
        }

        try {
            Finding errors = errorLogFinding();
            if (errors != null) {
                findings.add(errors);
            }
        } catch (Exception e) {
            findings.add(checkFailed('error_log', e));
        }

        return findings;
    }

    /**
     * The findings plus the context the panel shows above them.
     */
    public static Report buildReport() {
        Report report = new Report();
        report.findings = run();
        report.canManageSettings = FeatureManagement.checkPermission('Manage_Nonprofit_Settings');

        try {
            report.orgShape = OrgShapeDetector.detect();
            report.orgShapeSummary = detectedSummary(report.orgShape);
            report.recommendedMode = OrgShapeDetector.recommendedCoexistenceMode();
            report.recommendedModeLabel = modeLabel(report.recommendedMode);
        } catch (Exception e) {
            ErrorLogger.log(e, System.Label.Core_HealthCheck_ErrorContext);
        }

        try {
            report.currentMode = CoexistenceService.getCurrentMode();
            report.currentModeLabel = modeLabel(report.currentMode);
            report.modeNeedsAttention =
                String.isBlank(report.currentMode) ||
                (report.recommendedMode != null &&
                !report.recommendedMode.equals(report.currentMode));
        } catch (Exception e) {
            ErrorLogger.log(e, System.Label.Core_HealthCheck_ErrorContext);
        }

        return report;
    }

    private static Finding orgShapeFinding(OrgShapeDetector.OrgShape shape) {
        String recommended = OrgShapeDetector.recommendedCoexistenceMode();
        String detail = String.format(
            System.Label.Core_HealthCheck_OrgShapeDetail,
            new List<Object>{ detectedSummary(shape), modeLabel(recommended) }
        );
        return new Finding(
            'org_shape',
            System.Label.Core_HealthCheck_OrgShapeTitle,
            detail,
            SEVERITY_INFO,
            CATEGORY_ORG_SHAPE
        );
    }

    /**
     * What was found, as a sentence an administrator can read out loud.
     */
    public static String detectedSummary(OrgShapeDetector.OrgShape shape) {
        if (shape == null) {
            return System.Label.Core_HealthCheck_NothingDetected;
        }

        List<String> detected = new List<String>();
        if (shape.hasPersonAccounts == true) {
            detected.add(System.Label.Core_HealthCheck_PersonAccountsDetected);
        }
        if (shape.hasIndustriesNonprofit == true) {
            detected.add(System.Label.Core_HealthCheck_IndustriesDetected);
        }
        if (shape.hasNpsp == true) {
            detected.add(System.Label.Core_HealthCheck_NpspDetected);
        }
        if (shape.hasSalesCloudObjects == true) {
            detected.add(System.Label.Core_HealthCheck_SalesObjectsDetected);
        }
        if (detected.isEmpty()) {
            return System.Label.Core_HealthCheck_NothingDetected;
        }
        return String.join(detected, '. ') + '.';
    }

    private static Finding coexistenceModeFinding(OrgShapeDetector.OrgShape shape) {
        String recommended = OrgShapeDetector.recommendedCoexistenceMode();
        String current = CoexistenceService.getCurrentMode();

        if (String.isBlank(current)) {
            String detail = String.format(
                System.Label.Core_HealthCheck_ModeUnsetDetail,
                new List<Object>{
                    modeLabel(CoexistenceService.MODE_STANDALONE),
                    modeLabel(recommended)
                }
            );
            return new Finding(
                    'coexistence_mode_unset',
                    System.Label.Core_HealthCheck_ModeUnsetTitle,
                    detail,
                    SEVERITY_WARNING,
                    CATEGORY_ORG_SHAPE
                )
                .withFix(
                    System.Label.Core_HealthCheck_UseRecommendedFix,
                    FIX_APPLY_RECOMMENDED_MODE
                );
        }

        if (!current.equals(recommended)) {
            String detail = String.format(
                System.Label.Core_HealthCheck_ModeMismatchDetail,
                new List<Object>{ modeLabel(current), modeLabel(recommended) }
            );
            return new Finding(
                    'coexistence_mode_mismatch',
                    System.Label.Core_HealthCheck_ModeMismatchTitle,
                    detail,
                    SEVERITY_WARNING,
                    CATEGORY_ORG_SHAPE
                )
                .withFix(
                    System.Label.Core_HealthCheck_UseRecommendedFix,
                    FIX_APPLY_RECOMMENDED_MODE
                );
        }

        String matchDetail = String.format(
            System.Label.Core_HealthCheck_ModeMatchDetail,
            new List<Object>{ modeLabel(current) }
        );
        return new Finding(
            'coexistence_mode_match',
            System.Label.Core_HealthCheck_ModeMatchTitle,
            matchDetail,
            SEVERITY_INFO,
            CATEGORY_ORG_SHAPE
        );
    }

    private static Finding membershipModeFinding(OrgShapeDetector.OrgShape shape) {
        if (shape == null || shape.hasPersonAccounts != true) {
            return null;
        }
        if (CoexistenceService.MEMBERSHIP_JUNCTION.equals(CoexistenceService.getMembershipMode())) {
            return null;
        }

        return new Finding(
                'membership_mode_person_accounts',
                System.Label.Core_HealthCheck_MembershipTitle,
                System.Label.Core_HealthCheck_MembershipDetail,
                SEVERITY_ERROR,
                CATEGORY_ORG_SHAPE
            )
            .withFix(System.Label.Core_HealthCheck_MembershipFix, FIX_APPLY_JUNCTION_MEMBERSHIP);
    }

    private static Finding connectModuleFinding(OrgShapeDetector.OrgShape shape) {
        if (shape == null || shape.hasIndustriesNonprofit != true) {
            return null;
        }
        if (Type.forName(CONNECT_MARKER_CLASS) != null) {
            return null;
        }

        return new Finding(
            'connect_module_absent',
            System.Label.Core_HealthCheck_ConnectMissingTitle,
            System.Label.Core_HealthCheck_ConnectMissingDetail,
            SEVERITY_INFO,
            CATEGORY_ORG_SHAPE
        );
    }

    private static Finding multiCurrencyFinding(OrgShapeDetector.OrgShape shape) {
        if (shape == null || shape.isMultiCurrency != true) {
            return null;
        }

        return new Finding(
            'multi_currency',
            System.Label.Core_HealthCheck_MultiCurrencyTitle,
            System.Label.Core_HealthCheck_MultiCurrencyDetail,
            SEVERITY_WARNING,
            CATEGORY_LICENSES
        );
    }

    private static Finding noAdminFinding() {
        Integer admins =
            UserAccessSelector.countActiveAssignees(new Set<String>{ GROUP_ADMIN }) +
            UserAccessSelector.countActiveDirectAssignees(new Set<String>{ PERMISSION_SET_ADMIN });
        if (admins > 0) {
            return null;
        }

        return new Finding(
                'no_nonprofit_admin',
                System.Label.Core_HealthCheck_NoAdminTitle,
                System.Label.Core_HealthCheck_NoAdminDetail,
                SEVERITY_ERROR,
                CATEGORY_ACCESS
            )
            .withFix(System.Label.Core_HealthCheck_AccessFix, SECTION_ACCESS);
    }

    private static Finding usersWithoutAccessFinding() {
        Set<Id> assigned = UserAccessSelector.getAssignedUserIds(NONPROFIT_GROUPS);
        assigned.addAll(UserAccessSelector.getPermissionSetAssigneeIds(NONPROFIT_PERMISSION_SETS));
        Integer without = UserAccessSelector.countActiveStandardUsersExcluding(assigned);
        if (without <= 0) {
            return null;
        }

        List<Object> count = new List<Object>{ String.valueOf(without) };
        return new Finding(
                'users_without_access',
                String.format(System.Label.Core_HealthCheck_UsersWithoutAccessTitle, count),
                String.format(System.Label.Core_HealthCheck_UsersWithoutAccessDetail, count),
                SEVERITY_WARNING,
                CATEGORY_ACCESS
            )
            .withFix(System.Label.Core_HealthCheck_AccessFix, SECTION_ACCESS);
    }

    private static Finding automationPausedFinding() {
        Nonprofit_Settings__c settings = SettingsService.getSettings();
        Datetime pausedUntil = settings == null ? null : settings.Automation_Paused_Until__c;
        if (pausedUntil == null || pausedUntil <= System.now()) {
            return null;
        }

        String detail = String.format(
            System.Label.Core_HealthCheck_AutomationPausedDetail,
            new List<Object>{ pausedUntil.format() }
        );
        return new Finding(
                'automation_paused',
                System.Label.Core_HealthCheck_AutomationPausedTitle,
                detail,
                SEVERITY_INFO,
                CATEGORY_SETTINGS
            )
            .withFix(System.Label.Core_HealthCheck_AutomationFix, SECTION_AUTOMATION);
    }

    private static Finding errorLogFinding() {
        Integer newErrors = ErrorLogCountSelector.countNew();
        if (newErrors <= 0) {
            return null;
        }

        List<Object> count = new List<Object>{ String.valueOf(newErrors) };
        return new Finding(
                'error_log_new',
                String.format(System.Label.Core_HealthCheck_ErrorLogTitle, count),
                String.format(System.Label.Core_HealthCheck_ErrorLogDetail, count),
                SEVERITY_WARNING,
                CATEGORY_SETTINGS
            )
            .withFix(
                System.Label.Core_HealthCheck_ErrorLogFix,
                ErrorLogCountSelector.listViewUrl()
            );
    }

    private static Finding checkFailed(String checkKey, Exception e) {
        ErrorLogger.log(e, System.Label.Core_HealthCheck_ErrorContext);
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
}

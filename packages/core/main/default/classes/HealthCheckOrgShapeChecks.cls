/**
 * The Health Check questions about what this org is: what is installed alongside Open
 * Impact, which coexistence mode that implies, and whether the settings match it
 * (plan Section 4.8, feature C-11).
 *
 * These checks are the ones that run for everybody, because none of them asks a question
 * about other people. HealthCheckService.steps() decides the order they are read in; this
 * class decides what each of them says.
 *
 * Every finding is created exactly as HealthCheckService created it before ADR-0031 moved
 * it here: same keys, same severities, same categories, same labels, same fix targets.
 */
public with sharing class HealthCheckOrgShapeChecks {
    /**
     * An Apex class the Connect package ships, used to tell whether Connect is installed
     * without referencing it at compile time.
     */
    private static final String CONNECT_MARKER_CLASS = 'ConnectService';

    /** What this org has installed, and the mode that shape recommends. */
    public class OrgShapeCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return orgShapeFinding(OrgShapeDetector.detect());
        }
    }

    /** Whether the coexistence mode in settings is the one the org shape recommends. */
    public class CoexistenceModeCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return coexistenceModeFinding();
        }
    }

    /** Whether household membership can work at all in a Person Accounts org. */
    public class MembershipModeCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return membershipModeFinding(OrgShapeDetector.detect());
        }
    }

    /** Whether an org with Industries objects has the Connect module that mirrors to them. */
    public class ConnectModuleCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return connectModuleFinding(OrgShapeDetector.detect());
        }
    }

    /** Whether this org runs multi-currency, which v1 does not support. */
    public class MultiCurrencyCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return multiCurrencyFinding(OrgShapeDetector.detect());
        }
    }

    /**
     * What was found, as a sentence an administrator can read out loud.
     *
     * @param shape the detected org shape, or null when it could not be read
     * @return the sentence, never blank
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

    private static HealthCheckService.Finding orgShapeFinding(OrgShapeDetector.OrgShape shape) {
        String recommended = OrgShapeDetector.recommendedCoexistenceMode();
        String detail = String.format(
            System.Label.Core_HealthCheck_OrgShapeDetail,
            new List<Object>{ detectedSummary(shape), HealthCheckService.modeLabel(recommended) }
        );
        return new HealthCheckService.Finding(
            'org_shape',
            System.Label.Core_HealthCheck_OrgShapeTitle,
            detail,
            HealthCheckService.SEVERITY_INFO,
            HealthCheckService.CATEGORY_ORG_SHAPE
        );
    }

    private static HealthCheckService.Finding coexistenceModeFinding() {
        String recommended = OrgShapeDetector.recommendedCoexistenceMode();
        String current = CoexistenceService.getCurrentMode();

        if (String.isBlank(current)) {
            String detail = String.format(
                System.Label.Core_HealthCheck_ModeUnsetDetail,
                new List<Object>{
                    HealthCheckService.modeLabel(CoexistenceService.MODE_STANDALONE),
                    HealthCheckService.modeLabel(recommended)
                }
            );
            return new HealthCheckService.Finding(
                    'coexistence_mode_unset',
                    System.Label.Core_HealthCheck_ModeUnsetTitle,
                    detail,
                    HealthCheckService.SEVERITY_WARNING,
                    HealthCheckService.CATEGORY_ORG_SHAPE
                )
                .withFix(
                    System.Label.Core_HealthCheck_UseRecommendedFix,
                    HealthCheckService.FIX_APPLY_RECOMMENDED_MODE
                );
        }

        if (!current.equals(recommended)) {
            String detail = String.format(
                System.Label.Core_HealthCheck_ModeMismatchDetail,
                new List<Object>{
                    HealthCheckService.modeLabel(current),
                    HealthCheckService.modeLabel(recommended)
                }
            );
            return new HealthCheckService.Finding(
                    'coexistence_mode_mismatch',
                    System.Label.Core_HealthCheck_ModeMismatchTitle,
                    detail,
                    HealthCheckService.SEVERITY_WARNING,
                    HealthCheckService.CATEGORY_ORG_SHAPE
                )
                .withFix(
                    System.Label.Core_HealthCheck_UseRecommendedFix,
                    HealthCheckService.FIX_APPLY_RECOMMENDED_MODE
                );
        }

        String matchDetail = String.format(
            System.Label.Core_HealthCheck_ModeMatchDetail,
            new List<Object>{ HealthCheckService.modeLabel(current) }
        );
        return new HealthCheckService.Finding(
            'coexistence_mode_match',
            System.Label.Core_HealthCheck_ModeMatchTitle,
            matchDetail,
            HealthCheckService.SEVERITY_INFO,
            HealthCheckService.CATEGORY_ORG_SHAPE
        );
    }

    private static HealthCheckService.Finding membershipModeFinding(
        OrgShapeDetector.OrgShape shape
    ) {
        if (shape == null || shape.hasPersonAccounts != true) {
            return null;
        }
        if (CoexistenceService.MEMBERSHIP_JUNCTION.equals(CoexistenceService.getMembershipMode())) {
            return null;
        }

        return new HealthCheckService.Finding(
                'membership_mode_person_accounts',
                System.Label.Core_HealthCheck_MembershipTitle,
                System.Label.Core_HealthCheck_MembershipDetail,
                HealthCheckService.SEVERITY_ERROR,
                HealthCheckService.CATEGORY_ORG_SHAPE
            )
            .withFix(
                System.Label.Core_HealthCheck_MembershipFix,
                HealthCheckService.FIX_APPLY_JUNCTION_MEMBERSHIP
            );
    }

    private static HealthCheckService.Finding connectModuleFinding(
        OrgShapeDetector.OrgShape shape
    ) {
        if (shape == null || shape.hasIndustriesNonprofit != true) {
            return null;
        }
        if (Type.forName(CONNECT_MARKER_CLASS) != null) {
            return null;
        }

        return new HealthCheckService.Finding(
            'connect_module_absent',
            System.Label.Core_HealthCheck_ConnectMissingTitle,
            System.Label.Core_HealthCheck_ConnectMissingDetail,
            HealthCheckService.SEVERITY_INFO,
            HealthCheckService.CATEGORY_ORG_SHAPE
        );
    }

    private static HealthCheckService.Finding multiCurrencyFinding(
        OrgShapeDetector.OrgShape shape
    ) {
        if (shape == null || shape.isMultiCurrency != true) {
            return null;
        }

        return new HealthCheckService.Finding(
            'multi_currency',
            System.Label.Core_HealthCheck_MultiCurrencyTitle,
            System.Label.Core_HealthCheck_MultiCurrencyDetail,
            HealthCheckService.SEVERITY_WARNING,
            HealthCheckService.CATEGORY_LICENSES
        );
    }
}

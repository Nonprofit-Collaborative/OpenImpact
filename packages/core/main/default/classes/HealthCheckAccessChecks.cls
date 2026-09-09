/**
 * The Health Check questions about people: who administers Open Impact, who cannot see it
 * at all, and who holds the permission that lifts the receipt lock (plan Section 4.8,
 * feature C-11).
 *
 * Every question here is a question about the whole org, and Salesforce shows an ordinary
 * user only their own access, so a count taken without the administrator permission is
 * confidently wrong. HealthCheckService.steps() therefore runs these only for a viewer who
 * may manage settings, and runs NeedsAdminCheck for everyone else. The counts arrive as an
 * AccessCounts so a test can choose them.
 *
 * Every finding is created exactly as HealthCheckService created it before ADR-0031 moved
 * it here: same keys, same severities, same categories, same labels, same fix targets.
 */
public with sharing class HealthCheckAccessChecks {
    /** Whether anybody at all can administer Open Impact. */
    public class NoAdminCheck implements HealthCheckService.Check {
        private final HealthCheckService.AccessCounts counts;

        public NoAdminCheck(HealthCheckService.AccessCounts counts) {
            this.counts = counts;
        }

        public HealthCheckService.Finding run() {
            return noAdminFinding(counts);
        }
    }

    /** How many active people hold no packaged role and so cannot see the app. */
    public class UsersWithoutAccessCheck implements HealthCheckService.Check {
        private final HealthCheckService.AccessCounts counts;

        public UsersWithoutAccessCheck(HealthCheckService.AccessCounts counts) {
            this.counts = counts;
        }

        public HealthCheckService.Finding run() {
            return usersWithoutAccessFinding(counts);
        }
    }

    /** Who is holding the receipt lock override (ADR-0024). */
    public class OverrideReceiptLockCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return overrideReceiptLockFinding();
        }
    }

    /**
     * What a viewer without the administrator permission is told in place of the three
     * checks above, so that silence is never read as a pass.
     */
    public class NeedsAdminCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return new HealthCheckService.Finding(
                'access_checks_need_admin',
                System.Label.Core_HealthCheck_AccessNeedsAdminTitle,
                System.Label.Core_HealthCheck_AccessNeedsAdminDetail,
                HealthCheckService.SEVERITY_INFO,
                HealthCheckService.CATEGORY_ACCESS
            );
        }
    }

    private static HealthCheckService.Finding noAdminFinding(
        HealthCheckService.AccessCounts counts
    ) {
        Integer admins = counts.administrators();
        if (admins > 0) {
            return null;
        }

        return new HealthCheckService.Finding(
                'no_nonprofit_admin',
                System.Label.Core_HealthCheck_NoAdminTitle,
                System.Label.Core_HealthCheck_NoAdminDetail,
                HealthCheckService.SEVERITY_ERROR,
                HealthCheckService.CATEGORY_ACCESS
            )
            .withFix(System.Label.Core_HealthCheck_AccessFix, HealthCheckService.SECTION_ACCESS);
    }

    private static HealthCheckService.Finding usersWithoutAccessFinding(
        HealthCheckService.AccessCounts counts
    ) {
        Integer without = counts.usersWithoutAccess();
        if (without <= 0) {
            return null;
        }

        List<Object> count = new List<Object>{ String.valueOf(without) };
        return new HealthCheckService.Finding(
                'users_without_access',
                String.format(System.Label.Core_HealthCheck_UsersWithoutAccessTitle, count),
                String.format(System.Label.Core_HealthCheck_UsersWithoutAccessDetail, count),
                HealthCheckService.SEVERITY_WARNING,
                HealthCheckService.CATEGORY_ACCESS
            )
            .withFix(System.Label.Core_HealthCheck_AccessFix, HealthCheckService.SECTION_ACCESS);
    }

    /**
     * Anyone holding the receipt lock override, by name (ADR-0024). Naming them is the point:
     * an administrator cannot take a permission away from "somebody".
     *
     * Core never compiles against Giving: the permission is a String handed to
     * CustomPermissionSelector, which asks the platform's own setup objects who holds it, so
     * an org without Giving answers "nobody" rather than failing.
     */
    private static HealthCheckService.Finding overrideReceiptLockFinding() {
        CustomPermissionSelector.Holders holders = CustomPermissionSelector.holders(
            HealthCheckService.OVERRIDE_RECEIPT_LOCK
        );
        if (holders == null || holders.readable != true || holders.total <= 0) {
            return null;
        }

        String detail = String.format(
            System.Label.Core_HealthCheck_OverrideLockDetail,
            new List<Object>{ holderList(holders) }
        );
        return new HealthCheckService.Finding(
                'override_receipt_lock',
                System.Label.Core_HealthCheck_OverrideLockTitle,
                detail,
                HealthCheckService.SEVERITY_WARNING,
                HealthCheckService.CATEGORY_ACCESS
            )
            .withFix(
                System.Label.Core_HealthCheck_OverrideLockFix,
                HealthCheckService.FIX_CUSTOM_PERMISSIONS_URL
            );
    }

    /**
     * The holders as a sentence: the first few by name, then a count of the rest, so a org
     * that has granted the permission to a whole profile still produces a readable line.
     */
    private static String holderList(CustomPermissionSelector.Holders holders) {
        List<String> parts = new List<String>(holders.names);
        Integer unnamed = holders.total - holders.names.size();
        if (unnamed > 0) {
            parts.add(
                String.format(
                    System.Label.Core_HealthCheck_OverrideLockMoreNames,
                    new List<Object>{ String.valueOf(unnamed) }
                )
            );
        }
        return String.join(parts, ', ');
    }
}

/**
 * The Giving questions Health Check asks, added to Core's one report through
 * `GivingHealthCheckExtension` (G-20 follow-up, ADR-0053, ADR-NEXT). Grouped the way
 * ADR-0039 groups Core's own checks, in its own class, so a second Giving check reads next to
 * this one rather than inside Core.
 *
 * Whether a gift is in the books, and what "locked" means, is `GiftPostingLock`'s rule
 * (ADR-0022, ADR-0053): a gift with a counting status (Received, Refunded or Written off) and
 * a type other than In-kind. This class asks nothing about that rule Core does not already
 * enforce; it only reports what the rule finds, capped and linked the way
 * `HealthCheckHouseholdChecks` reports orphan records in Core.
 *
 * Only asked of a viewer who may manage settings (`HealthCheckService.canManageSettings()`):
 * posting and the close date are an administrator's business. `HealthCheckGivingSelector` reads
 * `without sharing`, unlike `HouseholdOrphanSelector`'s shared orphan reads in Core: Gift__c
 * ships with Private sharing (R-G14), so a viewer's own record sharing narrows which gifts they
 * own or share, not which gifts are actually locked and unposted, and a Health Check finding
 * that silently under-counts because the administrator does not happen to share every gift is a
 * wrong answer, not a narrower one. The permission check above is the access control that
 * matters here, the same as it is for every other Settings-category check that reads org-wide
 * state.
 */
public with sharing class HealthCheckGivingChecks {
    /** Counts stop here, and the finding says "more than" this many. A test lowers it. */
    @TestVisible
    private static Integer countCap = 1000;

    /** How many example gifts a finding links to. */
    private static final Integer LINKS_SHOWN = 5;

    /** Every finding Giving adds to the Health Check report, for this viewer. */
    public static List<HealthCheckService.Finding> findings() {
        List<HealthCheckService.Finding> findings = new List<HealthCheckService.Finding>();
        if (!HealthCheckService.canManageSettings()) {
            return findings;
        }
        HealthCheckService.Finding finding = unpostedClosedPeriodFinding();
        if (finding != null) {
            findings.add(finding);
        }
        return findings;
    }

    /**
     * Gifts in the books, dated on or before Books Closed Through, that nothing has marked
     * posted (G-20 follow-up). They are already locked by the period, so nothing about them
     * can change until they are posted or the period is reopened; a bookkeeper who closed the
     * month without exporting and marking every gift is the ordinary way this happens.
     */
    private static HealthCheckService.Finding unpostedClosedPeriodFinding() {
        Date closed = GiftPostingLock.closedThrough();
        if (closed == null) {
            return null;
        }
        Integer count = HealthCheckGivingSelector.countUnpostedInClosedPeriod(closed, countCap + 1);
        if (count == null || count <= 0) {
            return null;
        }
        List<Gift__c> first = HealthCheckGivingSelector.unpostedInClosedPeriod(closed, LINKS_SHOWN);

        String counted = count > countCap
            ? String.format(
                  Label.Giving_HealthCheck_UnpostedClosedPeriodMoreThan,
                  new List<Object>{ countCap.format() }
              )
            : count.format();

        String text = Label.Giving_HealthCheck_UnpostedClosedPeriodDetail;
        if (!first.isEmpty()) {
            text +=
                ' ' +
                String.format(
                    Label.Giving_HealthCheck_UnpostedClosedPeriodFirstListed,
                    new List<Object>{ String.valueOf(first.size()) }
                );
        }

        List<HealthCheckService.Link> links = new List<HealthCheckService.Link>();
        for (Gift__c gift : first) {
            links.add(new HealthCheckService.Link(gift));
        }

        return new HealthCheckService.Finding(
                'unposted_gifts_closed_period',
                String.format(
                    Label.Giving_HealthCheck_UnpostedClosedPeriodTitle,
                    new List<Object>{ counted }
                ),
                text,
                HealthCheckService.SEVERITY_WARNING,
                HealthCheckService.CATEGORY_SETTINGS
            )
            .withFix(Label.Giving_HealthCheck_UnpostedClosedPeriodFix, SettingSections.GIVING)
            .withLinks(links);
    }
}

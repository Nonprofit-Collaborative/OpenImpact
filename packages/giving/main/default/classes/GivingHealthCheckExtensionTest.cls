/**
 * Proves the whole path, end to end, in an org where both packages are installed (G-20
 * follow-up, ADR-0053, ADR-NEXT): Core's `HealthCheckService.run()` finds
 * `GivingHealthCheckExtension` by name, calls it, and folds its finding into the one report
 * Health Check shows. `HealthCheckGivingChecksTest` covers what the finding says; this class
 * covers only that Core actually reaches it.
 */
@IsTest
private class GivingHealthCheckExtensionTest {
    private static User jen() {
        return TestDataFactory.createUser(
            'Jen',
            new List<String>{ 'Nonprofit_Admin', 'Giving_Admin' }
        );
    }

    @TestSetup
    static void makeData() {
        GivingTestDataFactory.insertDefaultFund();
        Contact ana = GivingTestDataFactory.insertHouseholdContact(
            'The Nolan Family',
            'Ana',
            'Nolan'
        );
        Gift__c gift = GivingTestDataFactory.buildGift(ana.Id, 250);
        gift.Gift_Date__c = Date.today().toStartOfMonth().addDays(-1);
        insert gift;
    }

    @IsTest
    static void delegatesStraightToTheGivingChecks() {
        User jen = jen();
        System.runAs(jen) {
            GivingTestDataFactory.closeBooksThrough(Date.today().toStartOfMonth().addDays(-1));

            List<HealthCheckService.Finding> findings = new GivingHealthCheckExtension().findings();

            System.assertEquals(1, findings.size());
            System.assertEquals('unposted_gifts_closed_period', findings[0].key);
        }
    }

    @IsTest
    static void coresOneReportCarriesTheGivingFindingWhenBothPackagesAreInstalled() {
        User jen = jen();
        System.runAs(jen) {
            GivingTestDataFactory.closeBooksThrough(Date.today().toStartOfMonth().addDays(-1));

            List<HealthCheckService.Finding> findings = HealthCheckService.run();

            HealthCheckService.Finding giving = null;
            for (HealthCheckService.Finding finding : findings) {
                if ('unposted_gifts_closed_period'.equals(finding.key)) {
                    giving = finding;
                }
            }
            System.assertNotEquals(
                null,
                giving,
                'Core resolves the installed extension by name and reports what it finds, ' +
                'without Core ever naming a gift or a closed period itself.'
            );
        }
    }
}

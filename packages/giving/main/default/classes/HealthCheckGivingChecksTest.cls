/**
 * Tests for HealthCheckGivingChecks (G-20 follow-up, ADR-0053): the Health Check finding for
 * gifts already locked by a closed period that nothing has marked posted.
 */
@IsTest
private class HealthCheckGivingChecksTest {
    private static User jen() {
        return TestDataFactory.createUser(
            'Jen',
            new List<String>{ 'Nonprofit_Admin', 'Giving_Admin' }
        );
    }

    private static User david() {
        return TestDataFactory.createUser(
            'David',
            new List<String>{ 'Nonprofit_Staff', 'Giving_Staff' }
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
        List<Gift__c> gifts = GivingTestDataFactory.buildGifts(ana.Id, 3, 100);
        for (Integer i = 0; i < gifts.size(); i++) {
            gifts[i].Gift_Date__c = Date.today().toStartOfMonth().addDays(-1 - i);
        }
        insert gifts;
    }

    private static Date lastClosedDay() {
        return Date.today().toStartOfMonth().addDays(-1);
    }

    @IsTest
    static void noClosedPeriodFindsNothing() {
        User jen = jen();
        System.runAs(jen) {
            List<HealthCheckService.Finding> findings = HealthCheckGivingChecks.findings();

            System.assertEquals(
                0,
                findings.size(),
                'With no period closed, nothing in the org is locked yet, so there is nothing ' +
                'to report.'
            );
        }
    }

    @IsTest
    static void viewerWithoutManageSettingsSeesNoFinding() {
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());
        User david = david();
        System.runAs(david) {
            List<HealthCheckService.Finding> findings = HealthCheckGivingChecks.findings();

            System.assertEquals(
                0,
                findings.size(),
                'Posting and the close date are an administrator question; a viewer without ' +
                'Manage Nonprofit Settings is skipped rather than answered wrongly.'
            );
        }
    }

    @IsTest
    static void noUnpostedGiftsInClosedPeriodFindsNothing() {
        User jen = jen();
        System.runAs(jen) {
            GiftPostingService.markPosted(postedGiftIds());
        }
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());

        System.runAs(jen) {
            List<HealthCheckService.Finding> findings = HealthCheckGivingChecks.findings();

            System.assertEquals(
                0,
                findings.size(),
                'Every gift in the closed period is already posted, so there is nothing to ' +
                'flag.'
            );
        }
    }

    @IsTest
    static void someUnpostedGiftsAreReportedWithLinksAndAFix() {
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());
        User jen = jen();
        System.runAs(jen) {
            List<HealthCheckService.Finding> findings = HealthCheckGivingChecks.findings();

            System.assertEquals(1, findings.size(), 'One finding for the three unposted gifts.');
            HealthCheckService.Finding finding = findings[0];
            System.assertEquals('unposted_gifts_closed_period', finding.key);
            System.assertEquals(HealthCheckService.SEVERITY_WARNING, finding.severity);
            System.assertEquals(HealthCheckService.CATEGORY_SETTINGS, finding.category);
            System.assert(
                finding.title.contains('3'),
                'The title names the count: ' + finding.title
            );
            System.assertEquals(
                3,
                finding.links.size(),
                'All three unposted gifts are linked, well under the cap.'
            );
            System.assertEquals(
                SettingSections.GIVING,
                finding.fixTarget,
                'The fix opens the Accounting Periods page, in the Giving settings section.'
            );
            System.assertNotEquals(null, finding.fixLabel);
        }
    }

    @IsTest
    static void capExceededReportsMoreThan() {
        Contact ben = GivingTestDataFactory.insertHouseholdContact(
            'The Okafor Family',
            'Ben',
            'Okafor'
        );
        List<Gift__c> more = GivingTestDataFactory.buildGifts(ben.Id, 4, 50);
        for (Integer i = 0; i < more.size(); i++) {
            more[i].Gift_Date__c = lastClosedDay().addDays(-10 - i);
        }
        insert more;
        // Seven gifts total (three from setup, four here): the count cap and the five-link
        // cap are independent, so this proves both without conflating them.
        HealthCheckGivingChecks.countCap = 2;
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());
        User jen = jen();
        System.runAs(jen) {
            List<HealthCheckService.Finding> findings = HealthCheckGivingChecks.findings();

            System.assertEquals(1, findings.size());
            HealthCheckService.Finding finding = findings[0];
            System.assert(
                finding.title.contains('More than 2'),
                'The count stops at the cap of 2 and says so rather than counting every row: ' +
                finding.title
            );
            System.assertEquals(
                5,
                finding.links.size(),
                'Links stop at the five shown, independent of the (lower) count cap.'
            );
        }
    }

    private static Set<Id> postedGiftIds() {
        Set<Id> ids = new Set<Id>();
        for (Gift__c gift : [SELECT Id FROM Gift__c]) {
            ids.add(gift.Id);
        }
        return ids;
    }
}

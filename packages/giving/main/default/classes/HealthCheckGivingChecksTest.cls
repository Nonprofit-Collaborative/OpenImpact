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

    /**
     * `HealthCheckService.Finding`'s fields are `@AuraEnabled` only, not
     * `@NamespaceAccessible`, so under a future namespace prefix this package cannot read them
     * directly. Reading through a JSON round trip is how the real Lightning wire path reaches
     * them too, so it proves the same thing the direct field reads used to.
     */
    private static Map<String, Object> asMap(HealthCheckService.Finding finding) {
        return (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(finding));
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
        // Jen must own a gift to mark it posted (ADR-0053: `GiftPostingService.markPosted`
        // reads in user mode, so a gift she cannot see is never touched), but the finding
        // itself reads the whole org without sharing (`HealthCheckGivingSelector`), so every
        // gift anywhere has to actually be posted for this test to see no finding, not only the
        // ones a narrower setup would have given her. Reassigning them to her first is simpler
        // than building a second owner-scoped dataset just to post it.
        Set<Id> giftIds = new Map<Id, Gift__c>([SELECT Id FROM Gift__c]).keySet();
        List<Gift__c> reowned = new List<Gift__c>();
        for (Id giftId : giftIds) {
            reowned.add(new Gift__c(Id = giftId, OwnerId = jen.Id));
        }
        update reowned;
        System.runAs(jen) {
            GiftPostingService.markPosted(giftIds);
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
            Map<String, Object> finding = asMap(findings[0]);
            System.assertEquals('unposted_gifts_closed_period', finding.get('key'));
            System.assertEquals(HealthCheckService.SEVERITY_WARNING, finding.get('severity'));
            System.assertEquals(HealthCheckService.CATEGORY_SETTINGS, finding.get('category'));
            String title = (String) finding.get('title');
            System.assert(title.contains('3'), 'The title names the count: ' + title);
            System.assertEquals(
                3,
                ((List<Object>) finding.get('links')).size(),
                'All three unposted gifts are linked, well under the cap.'
            );
            System.assertEquals(
                SettingSections.GIVING,
                finding.get('fixTarget'),
                'The fix opens the Accounting Periods page, in the Giving settings section.'
            );
            System.assertNotEquals(null, finding.get('fixLabel'));
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
            Map<String, Object> finding = asMap(findings[0]);
            String title = (String) finding.get('title');
            System.assert(
                title.contains('More than 2'),
                'The count stops at the cap of 2 and says so rather than counting every row: ' +
                title
            );
            System.assertEquals(
                5,
                ((List<Object>) finding.get('links')).size(),
                'Links stop at the five shown, independent of the (lower) count cap.'
            );
        }
    }
}

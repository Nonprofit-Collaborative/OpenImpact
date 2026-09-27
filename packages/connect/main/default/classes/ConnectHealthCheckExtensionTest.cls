/**
 * Connect's Health Check findings (X-01, R-OM8; X-07, R-GT5): a scheduled mirror run that has not
 * completed for more than two days is reported to Maria, in Core's one report, and only when the
 * mirror is scheduled, on, and she may manage settings.
 */
@IsTest
private class ConnectHealthCheckExtensionTest {
    private static void choose(String direction) {
        Connect_Settings__c settings = Connect_Settings__c.getOrgDefaults();
        settings.Opportunity_Mirror_Direction__c = direction;
        upsert settings;
    }

    private static User maria() {
        return TestDataFactory.createUserOnTheRunningUsersProfile(
            'Maria',
            new List<String>{ 'Barn_Admin', 'Giving_Admin', 'Opportunity_Mirror' }
        );
    }

    private static Boolean reported(List<HealthCheckService.Finding> findings) {
        for (HealthCheckService.Finding finding : findings) {
            if (finding.key == ConnectHealthCheckExtension.MIRROR_STALE_KEY) {
                return true;
            }
        }
        return false;
    }

    @IsTest
    static void aScheduledRunThatHasNotRunForTwoDaysIsReportedInCoresReport() {
        if (!OpportunityMirrorService.isAvailable()) {
            return;
        }
        choose(OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES);
        User admin = maria();
        Test.startTest();
        System.runAs(admin) {
            OpportunityMirrorSchedulable.schedule();
            Assert.isFalse(
                reported(new ConnectHealthCheckExtension().findings()),
                'Just scheduled: nothing to say yet.'
            );
            ConnectHealthCheckExtension.nowForTest = System.now().addDays(3);
            Assert.isTrue(reported(HealthCheckService.run()), 'Core finds Connect by name.');
            ConnectSettingsWriter.recordOpportunityMirrorRun(System.now().addDays(2), 'Ran');
            Assert.isFalse(
                reported(new ConnectHealthCheckExtension().findings()),
                'A run completed a day ago.'
            );
        }
        Test.stopTest();
    }

    private static void chooseGiftTransactions(String direction) {
        Connect_Settings__c settings = Connect_Settings__c.getOrgDefaults();
        settings.Gift_Transaction_Mirror_Direction__c = direction;
        upsert settings;
    }

    private static Boolean reportedGiftTransactions(List<HealthCheckService.Finding> findings) {
        for (HealthCheckService.Finding finding : findings) {
            if (finding.key == ConnectHealthCheckExtension.GIFT_TRANSACTION_STALE_KEY) {
                return true;
            }
        }
        return false;
    }

    @IsTest
    static void aStaleGiftTransactionRunIsReportedOnlyWhereTheMirrorCanWork() {
        chooseGiftTransactions(GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS);
        User admin = maria();
        Boolean available = GiftTransactionMirrorService.isAvailable();
        Test.startTest();
        System.runAs(admin) {
            GiftTransactionMirrorSchedulable.schedule();
            ConnectHealthCheckExtension.nowForTest = System.now().addDays(3);
            Assert.areEqual(
                available,
                reportedGiftTransactions(new ConnectHealthCheckExtension().findings()),
                'Scheduled, chosen and three days without a completed run (R-GT5).'
            );
            GiftTransactionMirrorSchema.absentForTest = true;
            Assert.isFalse(
                reportedGiftTransactions(new ConnectHealthCheckExtension().findings()),
                'Never where there are no Gift Transactions (R-GT1).'
            );
            GiftTransactionMirrorSchema.absentForTest = false;
            ConnectSettingsWriter.recordGiftTransactionMirrorRun(System.now().addDays(2), 'Ran');
            Assert.isFalse(
                reportedGiftTransactions(new ConnectHealthCheckExtension().findings()),
                'A run completed a day ago.'
            );
        }
        Test.stopTest();
        chooseGiftTransactions(GiftTransactionMirrorService.OFF);
        ConnectHealthCheckExtension.nowForTest = System.now().addDays(30);
        System.runAs(admin) {
            Assert.isFalse(
                reportedGiftTransactions(new ConnectHealthCheckExtension().findings()),
                'Off.'
            );
        }
    }

    @IsTest
    static void nothingIsReportedWhenTheRunIsNotExpected() {
        if (!OpportunityMirrorService.isAvailable()) {
            return;
        }
        ConnectHealthCheckExtension.nowForTest = System.now().addDays(3);
        User admin = maria();
        User viewer = TestDataFactory.createUserOnTheRunningUsersProfile(
            'Ana',
            new List<String>{ 'Giving_Admin' }
        );
        choose(OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES);
        Test.startTest();
        System.runAs(admin) {
            Assert.isFalse(
                reported(new ConnectHealthCheckExtension().findings()),
                'Not scheduled.'
            );
            OpportunityMirrorSchedulable.schedule();
        }
        System.runAs(viewer) {
            Assert.isFalse(
                reported(new ConnectHealthCheckExtension().findings()),
                'Only a viewer who may manage settings is told.'
            );
        }
        choose(OpportunityMirrorService.OFF);
        System.runAs(admin) {
            Assert.isFalse(reported(new ConnectHealthCheckExtension().findings()), 'Off.');
        }
        Test.stopTest();
    }
}

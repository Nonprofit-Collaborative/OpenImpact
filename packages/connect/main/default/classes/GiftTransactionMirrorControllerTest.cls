/**
 * The Gift Transaction mirror page (X-07, R-GT5, R-GT10): who may open it, what it tells Maria,
 * the refusals given before anything starts, the reconciliation's refusals and, where the org has
 * Gift Transactions, what the reconciliation lists and the nightly schedule.
 */
@IsTest
private class GiftTransactionMirrorControllerTest {
    private static final Date FROM_DATE = Date.newInstance(2026, 9, 1);
    private static final Date TO_DATE = Date.newInstance(2026, 9, 30);

    @TestSetup
    static void setup() {
        GivingTestDataFactory.ensureDefaultFund();
        GivingTestDataFactory.insertHouseholdContact('The Garcia Household', 'Luis', 'Garcia');
    }

    private static void choose(String direction, String status) {
        Connect_Settings__c settings = Connect_Settings__c.getOrgDefaults();
        settings.Gift_Transaction_Mirror_Direction__c = direction;
        settings.Gift_Transaction_Mirror_Status__c = status;
        settings.Gift_Transaction_Mirror_Start__c = Datetime.newInstance(
            FROM_DATE,
            Time.newInstance(12, 0, 0, 0)
        );
        upsert settings;
    }

    /** Maria: BarnCRM Admin, so she can manage settings, and the Gift Transaction Mirror set. */
    private static User maria() {
        return TestDataFactory.createUserOnTheRunningUsersProfile(
            'Maria',
            new List<String>{ 'Barn_Admin', 'Giving_Admin', 'Gift_Transaction_Mirror' }
        );
    }

    private static String refusalOf(Callable action) {
        try {
            action.call(null, null);
        } catch (AuraHandledException refused) {
            return refused.getMessage();
        }
        return null;
    }

    /** The page actions, so each refusal test reads as one line. */
    private class Action implements Callable {
        private final String name;
        Action(String name) {
            this.name = name;
        }
        public Object call(String unused, Map<String, Object> args) {
            switch on name {
                when 'runNow' {
                    return GiftTransactionMirrorController.runNow();
                }
                when 'copyAgain' {
                    return GiftTransactionMirrorController.copyRangeAgain(FROM_DATE, TO_DATE);
                }
                when 'compareEmpty' {
                    return GiftTransactionMirrorController.compare(null, TO_DATE);
                }
                when 'compareReversed' {
                    return GiftTransactionMirrorController.compare(TO_DATE, FROM_DATE);
                }
                when 'schedule' {
                    return GiftTransactionMirrorController.schedule();
                }
                when 'stop' {
                    return GiftTransactionMirrorController.stop();
                }
                when 'status' {
                    return GiftTransactionMirrorController.getStatus();
                }
                when else {
                    return GiftTransactionMirrorController.compare(FROM_DATE, TO_DATE);
                }
            }
        }
    }

    private static GiftTransactionMirrorController.Status ready() {
        GiftTransactionMirrorController.Status status = new GiftTransactionMirrorController.Status();
        status.available = true;
        status.direction = GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS;
        status.notReady = null;
        status.canRun = true;
        status.canManage = true;
        status.running = false;
        return status;
    }

    @IsTest
    static void thePageNeedsTheGiftTransactionMirrorPermissionSet() {
        User david = TestDataFactory.createUser('David', new List<String>{ 'Giving_Admin' });
        Test.startTest();
        System.runAs(david) {
            for (String action : new List<String>{ 'status', 'compare', 'runNow', 'stop' }) {
                Assert.areEqual(
                    Label.Connect_GiftTransactionMirror_NoUsePermission,
                    refusalOf(new Action(action)),
                    action + ' says what he needs (ADR-0038 point 3).'
                );
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void mariaSeesWhatTheMirrorNeedsAndTheLastCompletedRun() {
        choose(GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS, null);
        Datetime ranAt = Datetime.newInstanceGmt(2026, 9, 24, 8, 30, 0);
        ConnectSettingsWriter.recordOpportunityMirrorRun(ranAt.addDays(-1), 'Opportunities.');
        ConnectSettingsWriter.recordGiftTransactionMirrorRun(ranAt, '3 Gift Transactions created.');
        GiftTransactionMirrorController.Status status;
        Test.startTest();
        System.runAs(maria()) {
            status = GiftTransactionMirrorController.getStatus();
        }
        Test.stopTest();
        Assert.areEqual(GiftTransactionMirrorService.isAvailable(), status.available);
        Assert.areEqual(GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS, status.direction);
        Assert.areEqual(FROM_DATE, status.startDate, 'The start date, as a date.');
        Assert.areEqual(
            status.available ? Label.Connect_GiftTransactionMirror_NoStatus : null,
            status.notReady,
            'What is missing, where it can be said.'
        );
        Assert.isTrue(status.canManage, 'She may manage settings.');
        Assert.areEqual(ranAt, status.lastRunAt, 'When the last run started.');
        Assert.areEqual('3 Gift Transactions created.', status.lastSummary, 'What it did.');
        Connect_Settings__c stored = Connect_Settings__c.getOrgDefaults();
        Assert.areEqual(
            'Opportunities.',
            stored.Opportunity_Mirror_Last_Summary__c,
            'Each mirror records only its own run.'
        );
        Assert.areEqual(
            GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS,
            stored.Gift_Transaction_Mirror_Direction__c,
            'And never undoes a setting.'
        );
    }

    @IsTest
    static void runNowIsRefusedInWordsUntilTheMirrorCanWork() {
        User admin = maria();
        choose(GiftTransactionMirrorService.OFF, null);
        Test.startTest();
        System.runAs(admin) {
            if (!GiftTransactionMirrorService.isAvailable()) {
                for (String action : new List<String>{ 'runNow', 'schedule', 'copyAgain' }) {
                    Assert.areEqual(
                        Label.Connect_GiftTransactionMirror_Unavailable,
                        refusalOf(new Action(action)),
                        action + ': nothing starts, and the page says why.'
                    );
                }
            } else {
                Assert.areEqual(
                    Label.Connect_GiftTransactionMirror_SwitchedOff,
                    refusalOf(new Action('runNow'))
                );
                choose(GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS, null);
                Assert.areEqual(
                    Label.Connect_GiftTransactionMirror_NoStatus,
                    refusalOf(new Action('runNow')),
                    'Not until the paid status is set (R-GT2).'
                );
            }
        }
        Test.stopTest();
        Assert.isNull(GiftTransactionMirrorSchedulable.nextRunAt(), 'Nothing was scheduled.');
    }

    @IsTest
    static void eachRefusalNamesItsOwnReason() {
        GiftTransactionMirrorController.Status status = ready();
        Assert.isNull(GiftTransactionMirrorController.refusal(status, false), 'All allow it.');
        status.running = true;
        Assert.isNull(GiftTransactionMirrorController.refusal(status, true), 'Scheduling may.');
        Assert.areEqual(
            Label.Connect_GiftTransactionMirror_Running,
            GiftTransactionMirrorController.refusal(status, false)
        );
        status.canRun = false;
        Assert.areEqual(
            Label.Connect_GiftTransactionMirror_NoAccess,
            GiftTransactionMirrorController.refusal(status, false)
        );
        status.canManage = false;
        Assert.areEqual(
            Label.Connect_GiftTransactionMirror_NoManagePermission,
            GiftTransactionMirrorController.refusal(status, false)
        );
        status.notReady = Label.Connect_GiftTransactionMirror_NoStartDate;
        Assert.areEqual(
            Label.Connect_GiftTransactionMirror_NoStartDate,
            GiftTransactionMirrorController.refusal(status, false)
        );
        status.direction = GiftTransactionMirrorService.OFF;
        Assert.areEqual(
            Label.Connect_GiftTransactionMirror_SwitchedOff,
            GiftTransactionMirrorController.refusal(status, false)
        );
        status.available = false;
        Assert.areEqual(
            Label.Connect_GiftTransactionMirror_Unavailable,
            GiftTransactionMirrorController.refusal(status, false)
        );
    }

    @IsTest
    static void aRangeMalformedTooLargeOrWithoutGiftTransactionsIsRefusedInWords() {
        choose(GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS, null);
        GiftTransactionMirrorReconciliation.maxRecords = 0;
        Boolean available = GiftTransactionMirrorService.isAvailable();
        String paid = available ? GiftTransactionMirrorTestData.anActiveStatus() : null;
        Test.startTest();
        System.runAs(maria()) {
            Assert.areEqual(
                Label.Connect_GiftTransactionMirror_ErrorDatesRequired,
                refusalOf(new Action('compareEmpty'))
            );
            Assert.areEqual(
                Label.Connect_GiftTransactionMirror_ErrorDateOrder,
                refusalOf(new Action('compareReversed'))
            );
            if (!available) {
                Assert.areEqual(
                    Label.Connect_GiftTransactionMirror_Unavailable,
                    refusalOf(new Action('compare')),
                    'Nothing to compare with, and no query is made.'
                );
            } else {
                Assert.areEqual(
                    Label.Connect_GiftTransactionMirror_NoStatus,
                    refusalOf(new Action('compare')),
                    'The paid status says which Gift Transactions to compare.'
                );
            }
        }
        Test.stopTest();
        if (available && paid != null) {
            choose(GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS, paid);
            Gift__c given = GivingTestDataFactory.buildGift(
                [SELECT Id FROM Contact WHERE LastName = 'Garcia' LIMIT 1].Id,
                40
            );
            given.Gift_Date__c = FROM_DATE.addDays(4);
            insert given;
            System.runAs(GiftTransactionMirrorTestData.runner()) {
                Assert.areEqual(
                    Label.Connect_GiftTransactionMirror_ErrorTooMany,
                    refusalOf(new Action('compare')),
                    'Refused rather than shown in part (ADR-0051).'
                );
            }
        }
    }

    @IsTest
    static void anUnavailableMirrorComparesNothing() {
        choose(GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS, 'Paid');
        GiftTransactionMirrorSchema.absentForTest = true;
        Test.startTest();
        System.runAs(maria()) {
            Assert.areEqual(
                Label.Connect_GiftTransactionMirror_Unavailable,
                refusalOf(new Action('compare')),
                'Whatever the org has, an unavailable mirror compares nothing (R-GT1).'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void theReconciliationListsAGiftWithoutAGiftTransaction() {
        if (!GiftTransactionMirrorService.isAvailable()) {
            Assert.isFalse(
                GiftTransactionMirrorService.canRun(
                    GiftTransactionMirrorService.GIFT_TRANSACTIONS_TO_GIFTS
                ),
                'Nothing to read.'
            );
            return;
        }
        choose(
            GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS,
            GiftTransactionMirrorTestData.anActiveStatus()
        );
        Gift__c unlinked = GivingTestDataFactory.buildGift(
            [SELECT Id FROM Contact WHERE LastName = 'Garcia' LIMIT 1].Id,
            25
        );
        unlinked.Gift_Date__c = FROM_DATE.addDays(6);
        insert unlinked;
        GiftTransactionMirrorReconciliation.Comparison result;
        Test.startTest();
        System.runAs(GiftTransactionMirrorTestData.runner()) {
            result = GiftTransactionMirrorController.compare(FROM_DATE, TO_DATE);
        }
        Test.stopTest();
        Assert.areEqual(1, result.giftCount, 'The received gift dated in the range.');
        Assert.areEqual(25, result.giftTotal, 'Its total.');
        Boolean listed = false;
        for (GiftTransactionMirrorReconciliation.Difference row : result.differences) {
            listed |=
                row.giftId == unlinked.Id &&
                row.reason == Label.Connect_GiftTransactionMirror_DiffNoGiftTransaction;
        }
        Assert.isTrue(listed, 'Saved before any run, so it has no Gift Transaction yet.');
    }

    @IsTest
    static void mariaSchedulesAndStopsTheNightlyRun() {
        if (!GiftTransactionMirrorService.isAvailable()) {
            Assert.isNull(GiftTransactionMirrorSchedulable.nextRunAt(), 'Never scheduled.');
            return;
        }
        choose(
            GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS,
            GiftTransactionMirrorTestData.anActiveStatus()
        );
        Test.startTest();
        System.runAs(GiftTransactionMirrorTestData.runner()) {
            Assert.isNotNull(GiftTransactionMirrorController.schedule().nextRunAt, 'Scheduled.');
            Assert.isNull(GiftTransactionMirrorController.stop().nextRunAt, 'Stopped.');
        }
        Test.stopTest();
    }
}

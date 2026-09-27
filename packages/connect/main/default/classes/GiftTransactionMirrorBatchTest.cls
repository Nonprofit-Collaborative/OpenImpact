/**
 * Runs of the Gift Transaction mirror (X-07, R-GT5, R-GT6, R-GT7): what stops a run (no Gift
 * Transactions, a pause, the Automation page switch, a direction changed partway, a chunk without
 * room), what a run records, and, where the org has Gift Transactions, two hundred gifts copied in
 * one run and a Gift Transaction made into a gift once and only once.
 *
 * The stopping tests hold in every org, because a run checks the pause, the switch and the
 * headroom without reading a Nonprofit Cloud record. Gift Transactions are written and read only
 * through describe, so this class compiles where they do not exist.
 */
@IsTest
private class GiftTransactionMirrorBatchTest {
    private static final Date START = Date.newInstance(2026, 9, 1);

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
            START,
            Time.newInstance(12, 0, 0, 0)
        );
        upsert settings;
    }

    /** Maria runs the mirror and manages the settings, pause included. */
    private static User maria() {
        return TestDataFactory.createUserOnTheRunningUsersProfile(
            'Maria',
            new List<String>{ 'Barn_Admin', 'Giving_Admin', 'Gift_Transaction_Mirror' }
        );
    }

    private static Id luisId() {
        return [SELECT Id FROM Contact WHERE LastName = 'Garcia' LIMIT 1].Id;
    }

    private static List<Gift__c> savedGifts(Integer howMany) {
        List<Gift__c> gifts = GivingTestDataFactory.buildGifts(luisId(), howMany, 20);
        for (Gift__c gift : gifts) {
            gift.Gift_Date__c = START.addDays(10);
        }
        insert gifts;
        return (List<Gift__c>) Database.query(
            'SELECT ' + GiftTransactionMirrorSelector.GIFT_FIELDS + ' FROM Gift__c',
            AccessLevel.SYSTEM_MODE
        );
    }

    private static List<Error_Log__c> runLogs(String severity) {
        return [
            SELECT Message__c
            FROM Error_Log__c
            WHERE Context__c = :GiftTransactionMirrorBatch.LOG_CONTEXT AND Severity__c = :severity
            WITH SYSTEM_MODE
        ];
    }

    private static Datetime lastRun() {
        Connect_Settings__c stored = Connect_Settings__c.getOrgDefaults();
        return stored == null ? null : stored.Gift_Transaction_Mirror_Last_Run__c;
    }

    private static Integer linkedGifts() {
        return [SELECT COUNT() FROM Gift__c WHERE Gift_Transaction_Id__c != NULL WITH SYSTEM_MODE];
    }

    /** A run driven by hand, start to finish, as the platform would in one chunk. */
    private static void runOnce(String direction, List<SObject> chunk) {
        GiftTransactionMirrorBatch run = new GiftTransactionMirrorBatch(direction, null, null);
        run.start(null);
        run.execute(null, chunk);
        run.finish(null);
    }

    @IsTest
    static void whereThereAreNoGiftTransactionsARunDoesNothingAndSaysSoOnce() {
        GiftTransactionMirrorSchema.absentForTest = true;
        choose(GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS, 'Paid');
        savedGifts(3);
        Test.startTest();
        System.runAs(maria()) {
            Assert.isNull(GiftTransactionMirrorBatch.run(), 'Run now starts nothing (R-GT1).');
            runOnce(GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS, new List<SObject>());
        }
        Test.stopTest();
        List<Error_Log__c> logged = runLogs('Info');
        Assert.areEqual(1, logged.size(), 'One Info entry.');
        Assert.areEqual(Label.Connect_GiftTransactionMirror_Unavailable, logged[0].Message__c);
        Assert.areEqual(0, runLogs('Warning').size(), 'Nothing to warn about.');
        Assert.isNull(lastRun(), 'A run that did nothing is not recorded.');
        Assert.areEqual(0, linkedGifts(), 'No gift was touched.');
    }

    @IsTest
    static void aRunWhileAutomationIsPausedDoesNothingAndSaysSoOnce() {
        choose(GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS, 'Paid');
        List<Gift__c> gifts = savedGifts(3);
        Test.startTest();
        System.runAs(maria()) {
            AutomationControl.pauseAll(1);
            runOnce(GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS, gifts);
        }
        Test.stopTest();
        List<Error_Log__c> logged = runLogs('Info');
        Assert.areEqual(1, logged.size(), 'One Info entry.');
        Assert.areEqual(Label.Connect_GiftTransactionMirror_RunPaused, logged[0].Message__c);
        Assert.areEqual(0, linkedGifts(), 'Paused is paused.');
        Assert.isNull(lastRun(), 'A skipped run is not recorded.');
    }

    @IsTest
    static void aRunSwitchedOffOnTheAutomationPageDoesNothing() {
        choose(GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS, 'Paid');
        List<Gift__c> gifts = savedGifts(3);
        TestDataFactory.insertAutomationSettings(
            new Map<String, Boolean>{ GiftTransactionMirrorService.AUTOMATION_NAME => false }
        );
        Test.startTest();
        System.runAs(maria()) {
            runOnce(GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS, gifts);
        }
        Test.stopTest();
        List<Error_Log__c> logged = runLogs('Info');
        Assert.areEqual(1, logged.size(), 'One Info entry.');
        Assert.areEqual(Label.Connect_GiftTransactionMirror_RunSwitchedOff, logged[0].Message__c);
        Assert.areEqual(0, linkedGifts(), 'Off is off.');
    }

    @IsTest
    static void aChunkWithoutRoomIsLeftForTheNextRunWithOneWarning() {
        Assert.isTrue(GiftTransactionMirrorBatch.hasHeadroom(100), 'A fresh chunk has room.');
        choose(GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS, 'Paid');
        List<Gift__c> gifts = savedGifts(3);
        Test.startTest();
        System.runAs(maria()) {
            ConnectSync.simulatedCpuTimeUsed = Limits.getLimitCpuTime();
            GiftTransactionMirrorBatch run = new GiftTransactionMirrorBatch(
                GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS,
                null,
                null
            );
            run.execute(null, new List<Gift__c>{ gifts[0], gifts[1] });
            run.execute(null, new List<Gift__c>{ gifts[2] });
            ConnectSync.simulatedCpuTimeUsed = null;
            run.finish(null);
        }
        Test.stopTest();
        List<Error_Log__c> warned = runLogs('Warning');
        Assert.areEqual(1, warned.size(), 'One Warning for the run, not one per chunk.');
        Assert.areEqual(Label.Connect_GiftTransactionMirror_LogNoHeadroom, warned[0].Message__c);
        List<Error_Log__c> summary = runLogs('Info');
        Assert.areEqual(1, summary.size(), 'And the summary.');
        Assert.isTrue(
            summary[0].Message__c.contains('3 left for the next run'),
            summary[0].Message__c
        );
        Assert.isNull(lastRun(), 'A run that left chunks is not complete, so not recorded.');
        Assert.areEqual(0, linkedGifts(), 'Nothing was written.');
    }

    @IsTest
    static void chunksAfterTheDirectionChangesAreLeftAlone() {
        choose(GiftTransactionMirrorService.GIFT_TRANSACTIONS_TO_GIFTS, 'Paid');
        List<Gift__c> gifts = savedGifts(2);
        Test.startTest();
        System.runAs(maria()) {
            GiftTransactionMirrorBatch run = new GiftTransactionMirrorBatch(
                GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS,
                null,
                null
            );
            run.execute(null, gifts);
            run.finish(null);
        }
        Test.stopTest();
        List<Error_Log__c> summary = runLogs('Info');
        Assert.areEqual(1, summary.size(), 'The summary.');
        Assert.isTrue(
            summary[0].Message__c.contains('2 left for the next run'),
            summary[0].Message__c
        );
        Assert.areEqual(0, linkedGifts(), 'A run never works against the chosen direction.');
        Assert.isNull(lastRun(), 'A run that left chunks is not recorded as complete.');
    }

    @IsTest
    static void aRunWithoutAKnownPaidStatusDoesNothingAndWarns() {
        choose(GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS, 'Not a status (typo)');
        Test.startTest();
        System.runAs(maria()) {
            runOnce(GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS, new List<SObject>());
        }
        Test.stopTest();
        if (!GiftTransactionMirrorService.isAvailable()) {
            Assert.areEqual(0, runLogs('Warning').size(), 'Unavailable comes first, at Info.');
            Assert.areEqual(1, runLogs('Info').size(), 'One entry either way.');
            return;
        }
        List<Error_Log__c> warned = runLogs('Warning');
        Assert.areEqual(1, warned.size(), 'One Warning (R-GT5).');
        Assert.isTrue(warned[0].Message__c.contains('Not a status (typo)'), warned[0].Message__c);
        Assert.isNull(lastRun(), 'Not recorded.');
    }

    @IsTest
    static void aRunCopiesTwoHundredGiftsAndIsRecorded() {
        if (!GiftTransactionMirrorService.isAvailable()) {
            Assert.isFalse(GiftTransactionMirrorSchema.canRead(GiftTransactionMirrorSchema.READ));
            return;
        }
        choose(
            GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS,
            GiftTransactionMirrorTestData.anActiveStatus()
        );
        savedGifts(200);
        User runner = GiftTransactionMirrorTestData.runner();
        Id job;
        Test.startTest();
        System.runAs(runner) {
            job = GiftTransactionMirrorBatch.run();
        }
        Test.stopTest();
        Assert.isNotNull(job, 'Started.');
        Assert.areEqual(
            200,
            linkedGifts(),
            'Every gift has its Gift Transaction. If not, the Warnings say why: ' +
            runLogs('Warning')
        );
        Assert.areEqual(
            200,
            Database.countQuery(
                'SELECT COUNT() FROM ' + GiftTransactionMirrorSchema.objectName(),
                AccessLevel.SYSTEM_MODE
            ),
            'One each.'
        );
        Assert.isNotNull(lastRun(), 'The completed run is recorded (R-GT5).');
    }

    @IsTest
    static void aPaidGiftTransactionBecomesAGiftOnceAndOnlyOnce() {
        GiftTransactionMirrorService.Result nothing = GiftTransactionGiftService.makeGifts(
            new List<SObject>()
        );
        Assert.areEqual(0, nothing.created + nothing.failed, 'An empty chunk does nothing.');
        if (!GiftTransactionMirrorService.isAvailable()) {
            return;
        }
        String paid = GiftTransactionMirrorTestData.anActiveStatus();
        choose(GiftTransactionMirrorService.GIFT_TRANSACTIONS_TO_GIFTS, paid);
        Id household = [SELECT AccountId FROM Contact WHERE LastName = 'Garcia' LIMIT 1].AccountId;
        SObject online = GiftTransactionMirrorSchema.objectType().newSObject();
        online.put('DonorId', household);
        online.put('TransactionDate', START.addDays(3));
        online.put('OriginalAmount', 60);
        online.put('Status', paid);
        Database.SaveResult saved = Database.insert(online, false);
        Assert.isTrue(
            saved.isSuccess(),
            'This org\'s Gift Transactions need more than the reference records: ' +
            saved.getErrors()
        );
        List<SObject> chunk = Database.queryWithBinds(
            'SELECT Id, ' +
                String.join(GiftTransactionMirrorSchema.READ, ', ') +
                ' FROM ' +
                GiftTransactionMirrorSchema.objectName() +
                ' WHERE Id = :madeId',
            new Map<String, Object>{ 'madeId' => saved.getId() },
            AccessLevel.SYSTEM_MODE
        );
        User runner = GiftTransactionMirrorTestData.runner();
        GiftTransactionMirrorService.Result first;
        GiftTransactionMirrorService.Result again;
        Test.startTest();
        System.runAs(runner) {
            first = GiftTransactionGiftService.makeGifts(chunk);
            again = GiftTransactionGiftService.makeGifts(chunk);
        }
        Test.stopTest();
        Assert.areEqual(1, first.created, 'A gift is made: ' + first.refusals.count());
        Assert.areEqual(1, again.unchanged, 'Once only (R-GT6).');
        Gift__c made = [
            SELECT Amount__c, Gift_Date__c, Type__c, Status__c, Donor_Account__c
            FROM Gift__c
            WHERE Gift_Transaction_Id__c = :String.valueOf(saved.getId())
            WITH SYSTEM_MODE
        ];
        Assert.areEqual(60, made.Amount__c, 'Original Amount.');
        Assert.areEqual(START.addDays(3), made.Gift_Date__c, 'Transaction Date.');
        Assert.areEqual('Other', made.Type__c, 'Type Other.');
        Assert.areEqual('Received', made.Status__c, 'Received.');
        Assert.areEqual(household, made.Donor_Account__c, 'The donor account.');
    }

    @IsTest
    static void aGiftTransactionWithoutAnAmountOrADonorIsRefusedInWords() {
        Gift__c noAmount = new Gift__c(Amount__c = 0, Donor_Account__c = null);
        Assert.areEqual(
            Label.Connect_GiftTransactionMirror_AmountNotAboveZero,
            GiftTransactionGiftService.refusalFor(noAmount)
        );
        Gift__c noDonor = new Gift__c(Amount__c = 10);
        Assert.areEqual(
            Label.Connect_GiftTransactionMirror_NoDonor,
            GiftTransactionGiftService.refusalFor(noDonor)
        );
        noDonor.Donor_Account__c = GivingTestDataFactory.insertOrganization('Riverside Rotary').Id;
        Assert.isNull(GiftTransactionGiftService.refusalFor(noDonor), 'Nothing missing.');
    }
}

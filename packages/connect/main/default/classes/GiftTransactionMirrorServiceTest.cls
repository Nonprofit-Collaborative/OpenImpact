/**
 * The Gift Transaction mirror's settings, the link check on Gift, and Gifts to Gift Transactions
 * (X-07, canonical model Section 29D), as Maria sees them.
 *
 * Neither CI test org has Nonprofit Cloud, so every test asserts what the mirror does without Gift
 * Transactions: nothing, with no error and no Error Log entry (R-GT1). The rules that decide what
 * is copied are tested in memory and hold in every org; the tests that write Gift Transactions run
 * their second half only where the running person's describe has them. Gift Transactions are named
 * only as strings resolved through `GiftTransactionMirrorSchema`, so this class compiles anywhere.
 */
@IsTest
private class GiftTransactionMirrorServiceTest {
    private static final Date GIFT_DATE = Date.newInstance(2026, 9, 20);
    private static final Date START = Date.newInstance(2026, 9, 1);

    @TestSetup
    static void setup() {
        GivingTestDataFactory.ensureDefaultFund();
        GivingTestDataFactory.insertHouseholdContact('The Garcia Household', 'Luis', 'Garcia');
    }

    private static void choose(String direction, String status, Date startDate) {
        Connect_Settings__c settings = Connect_Settings__c.getOrgDefaults();
        settings.Gift_Transaction_Mirror_Direction__c = direction;
        settings.Gift_Transaction_Mirror_Status__c = status;
        settings.Gift_Transaction_Mirror_Start__c = startDate == null
            ? null
            : Datetime.newInstance(startDate, Time.newInstance(12, 0, 0, 0));
        upsert settings;
    }

    private static Id luisId() {
        return [SELECT Id FROM Contact WHERE LastName = 'Garcia' LIMIT 1].Id;
    }

    private static Gift__c gift(Decimal amount) {
        Gift__c gift = GivingTestDataFactory.buildGift(luisId(), amount);
        gift.Gift_Date__c = GIFT_DATE;
        return gift;
    }

    private static Gift__c reread(Id giftId) {
        return (Gift__c) Database.queryWithBinds(
            'SELECT ' +
                GiftTransactionMirrorSelector.GIFT_FIELDS +
                ' FROM Gift__c WHERE Id = :giftId',
            new Map<String, Object>{ 'giftId' => giftId },
            AccessLevel.SYSTEM_MODE
        )[0];
    }

    private static List<Error_Log__c> mirrorLogs() {
        return [
            SELECT Message__c, Severity__c
            FROM Error_Log__c
            WHERE Context__c LIKE 'Gift Transaction mirror%'
            WITH SYSTEM_MODE
        ];
    }

    /** An identifier of the Gift Transaction kind that names no record, as a person might type. */
    private static String aGiftTransactionId() {
        return GiftTransactionMirrorSchema.objectType().getDescribe().getKeyPrefix() +
            '000000000001';
    }

    @IsTest
    static void anOrgWithoutGiftTransactionsSavesAndDeletesTwoHundredGiftsUntouched() {
        GiftTransactionMirrorSchema.absentForTest = true;
        choose(GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS, 'Paid', START);
        List<Gift__c> gifts = GivingTestDataFactory.buildGifts(luisId(), 200, 25);
        gifts[0].Gift_Transaction_Id__c = 'typed by hand';
        Test.startTest();
        insert gifts;
        Assert.areEqual(
            'typed by hand',
            reread(gifts[0].Id).Gift_Transaction_Id__c,
            'Nothing is checked where there are no Gift Transactions (R-GT1).'
        );
        GiftTransactionMirrorService.Result result = GiftTransactionMirrorService.copyGifts(
            [
                SELECT
                    Id,
                    Name,
                    Status__c,
                    Amount__c,
                    Type__c,
                    Gift_Date__c,
                    Donor_Account__c,
                    Household__c,
                    Gift_Transaction_Id__c
                FROM Gift__c
            ]
        );
        delete gifts;
        Test.stopTest();

        Assert.isFalse(GiftTransactionMirrorService.isAvailable(), 'The seam hides the object.');
        Assert.areEqual(0, result.created + result.updated + result.failed, 'Nothing is copied.');
        Assert.areEqual(0, mirrorLogs().size(), 'Nothing is logged, not even the delete.');
    }

    @IsTest
    static void aTypedLinkMustBeAGiftTransactionsIdentifier() {
        Gift__c given = gift(100);
        given.Gift_Transaction_Id__c = UserInfo.getUserId();
        Test.startTest();
        Database.SaveResult saved = Database.insert(given, false);
        Test.stopTest();
        if (!GiftTransactionMirrorService.isAvailable()) {
            Assert.isTrue(saved.isSuccess(), 'Without Gift Transactions nothing is checked.');
            return;
        }
        Assert.isFalse(saved.isSuccess(), 'Another object\'s identifier is refused (R-GT9).');
        Assert.areEqual(
            Label.Connect_GiftTransactionMirror_InvalidGiftTransactionId,
            saved.getErrors()[0].getMessage(),
            'In words Maria can act on.'
        );
    }

    @IsTest
    static void aFifteenCharacterLinkIsStoredInItsEighteenCharacterForm() {
        if (!GiftTransactionMirrorService.isAvailable()) {
            Assert.isNull(GiftTransactionMirrorSchema.objectName(), 'No object, no name.');
            return;
        }
        Gift__c given = gift(100);
        given.Gift_Transaction_Id__c = aGiftTransactionId();
        Test.startTest();
        insert given;
        Test.stopTest();
        Assert.areEqual(
            String.valueOf(Id.valueOf(aGiftTransactionId())),
            reread(given.Id).Gift_Transaction_Id__c,
            'Stored as 18 characters, so uniqueness holds (R-GT9).'
        );
    }

    @IsTest
    static void aNewGiftTransactionGetsTheDonorDateAmountStatusAndName() {
        Account rotary = GivingTestDataFactory.insertOrganization('Riverside Rotary');
        Gift__c given = GivingTestDataFactory.buildAccountGift(rotary.Id, 250);
        given.Gift_Date__c = GIFT_DATE;
        Set<String> everything = new Set<String>(GiftTransactionMirrorSchema.CREATED);

        Map<String, Object> created = GiftTransactionMirrorService.desiredValues(
            given,
            true,
            everything,
            'Paid'
        );
        Assert.areEqual(rotary.Id, created.get('DonorId'), 'The Donor Account is the donor.');
        Assert.areEqual(GIFT_DATE, created.get('TransactionDate'), 'Gift Date.');
        Assert.areEqual(250, (Decimal) created.get('OriginalAmount'), 'Amount.');
        Assert.areEqual(250, (Decimal) created.get('CurrentAmount'), 'Amount, at creation.');
        Assert.areEqual('Paid', created.get('Status'), 'The paid status, at creation.');
        Assert.isFalse(created.containsKey('Name'), 'A gift not yet saved has no name to give.');

        Map<String, Object> later = GiftTransactionMirrorService.desiredValues(
            given,
            false,
            everything,
            'Paid'
        );
        Assert.areEqual(
            new Set<String>(GiftTransactionMirrorSchema.COMPARED),
            later.keySet(),
            'Afterwards only Donor, Transaction Date and Original Amount follow the gift (R-GT4).'
        );

        everything.remove('CurrentAmount');
        Assert.isFalse(
            GiftTransactionMirrorService.desiredValues(given, true, everything, 'Paid')
                .containsKey('CurrentAmount'),
            'A field the runner may not write is left out, never forced.'
        );
    }

    @IsTest
    static void aPersonStoredAsAContactGivesThroughTheirHousehold() {
        Contact luis = [SELECT Id, AccountId FROM Contact WHERE LastName = 'Garcia' LIMIT 1];
        Gift__c given = gift(40);
        given.Household__c = luis.AccountId;
        Assert.areEqual(
            luis.AccountId,
            GiftTransactionMirrorService.donorOf(given),
            'A Gift Transaction\'s donor must be an account (R-GT4).'
        );
        given.Household__c = null;
        Assert.isNull(GiftTransactionMirrorService.donorOf(given), 'None: refused, not guessed.');
    }

    @IsTest
    static void onlyADifferenceInACopiedValueIsAnUpdate() {
        Map<String, Object> desired = new Map<String, Object>{
            'OriginalAmount' => 100,
            'TransactionDate' => GIFT_DATE
        };
        Assert.isFalse(
            GiftTransactionMirrorService.differs(
                desired,
                new Map<String, Object>{
                    'OriginalAmount' => 100.00,
                    'TransactionDate' => GIFT_DATE
                }
            ),
            'The same amount at another scale is the same.'
        );
        Assert.isTrue(
            GiftTransactionMirrorService.differs(
                desired,
                new Map<String, Object>{
                    'OriginalAmount' => 100,
                    'TransactionDate' => GIFT_DATE.addDays(1)
                }
            ),
            'Another date is a difference.'
        );
        Assert.areEqual(
            100,
            GiftTransactionMirrorSchema.decimalOf(Double.valueOf(100)),
            'A number field read as a Double compares as a Decimal.'
        );
    }

    @IsTest
    static void onlyReceivedGiftsAboveZeroNotInKindFromTheStartDateAreCopied() {
        choose(GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS, 'Paid', START);
        Gift__c received = gift(10);
        Assert.isTrue(GiftTransactionMirrorService.isMirrored(received), 'Received (R-GT3).');

        Gift__c refund = gift(-10);
        Assert.isFalse(GiftTransactionMirrorService.isMirrored(refund), 'Never a refund.');
        Gift__c goods = gift(0);
        goods.Type__c = GiftTransactionMirrorService.TYPE_IN_KIND;
        Assert.isFalse(GiftTransactionMirrorService.isMirrored(goods), 'Never in-kind.');
        Gift__c pledged = gift(10);
        pledged.Status__c = 'Pending';
        Assert.isFalse(GiftTransactionMirrorService.isMirrored(pledged), 'Not Pending.');
        Gift__c refunded = gift(10);
        refunded.Status__c = 'Refunded';
        Assert.isFalse(GiftTransactionMirrorService.isMirrored(refunded), 'Not once refunded.');
        Gift__c early = gift(10);
        early.Gift_Date__c = START.addDays(-1);
        Assert.isFalse(GiftTransactionMirrorService.isMirrored(early), 'Not before the start.');

        choose(GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS, 'Paid', null);
        Assert.isFalse(
            GiftTransactionMirrorService.isMirrored(received),
            'Without a start date nothing is (R-GT2).'
        );
    }

    @IsTest
    static void nothingMovesUntilThePaidStatusAndTheStartDateAreSet() {
        String direction = GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS;
        choose(direction, '  ', START);
        Assert.areEqual(
            Label.Connect_GiftTransactionMirror_NoStatus,
            GiftTransactionMirrorService.notReadyReason(),
            'A blank status is no status (R-GT2).'
        );
        if (!GiftTransactionMirrorService.isAvailable()) {
            choose(direction, 'Paid', START);
            Assert.areEqual(
                String.format(
                    Label.Connect_GiftTransactionMirror_UnknownStatus,
                    new List<Object>{ 'Paid' }
                ),
                GiftTransactionMirrorService.notReadyReason(),
                'With no Status list, no value is one of its values.'
            );
            return;
        }
        String paid = GiftTransactionMirrorTestData.anActiveStatus();
        choose(direction, paid + ' (typo)', START);
        Assert.isTrue(
            GiftTransactionMirrorService.notReadyReason().contains(paid + ' (typo)'),
            'A value the org does not have is named.'
        );
        choose(direction, paid, null);
        Assert.areEqual(
            Label.Connect_GiftTransactionMirror_NoStartDate,
            GiftTransactionMirrorService.notReadyReason()
        );
        choose(direction, ' ' + paid + ' ', START);
        Assert.isNull(GiftTransactionMirrorService.notReadyReason(), 'Ready, spaces trimmed.');
    }

    @IsTest
    static void deletingALinkedGiftLeavesItsGiftTransactionAndSaysSoOnce() {
        choose(GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS, 'Paid', START);
        Boolean available = GiftTransactionMirrorService.isAvailable();
        Gift__c given = gift(100);
        given.Gift_Transaction_Id__c = available ? aGiftTransactionId() : 'typed by hand';
        insert given;
        Test.startTest();
        delete given;
        Test.stopTest();
        List<Error_Log__c> logged = mirrorLogs();
        if (!available) {
            Assert.areEqual(0, logged.size(), 'Without Gift Transactions nothing is said.');
            return;
        }
        Assert.areEqual(1, logged.size(), 'One Warning for the delete (R-GT8).');
        Assert.areEqual('Warning', logged[0].Severity__c, 'At Warning.');
        Assert.isTrue(
            logged[0].Message__c.contains(Label.Connect_GiftTransactionMirror_DeletedKept),
            'It says the Gift Transaction is left in place: ' + logged[0].Message__c
        );
    }

    @IsTest
    static void aGiftIsCopiedOnceThenFollowedAndLeftAloneWhenNothingChanged() {
        if (!GiftTransactionMirrorService.isAvailable()) {
            Assert.areEqual(
                0,
                GiftTransactionMirrorService.copyGifts(new List<Gift__c>{ gift(10) }).created,
                'Without Gift Transactions a run copies nothing.'
            );
            return;
        }
        choose(
            GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS,
            GiftTransactionMirrorTestData.anActiveStatus(),
            START
        );
        Gift__c given = gift(100);
        insert given;
        User runner = GiftTransactionMirrorTestData.runner();
        String linked;
        GiftTransactionMirrorService.Result second;
        GiftTransactionMirrorService.Result third;
        Test.startTest();
        System.runAs(runner) {
            GiftTransactionMirrorService.Result first = GiftTransactionMirrorService.copyGifts(
                new List<Gift__c>{ reread(given.Id) }
            );
            Assert.areEqual(
                1,
                first.created,
                'Created. If not, this org\'s Gift Transactions need more than R-GT4 writes.'
            );
            linked = reread(given.Id).Gift_Transaction_Id__c;
            Assert.isNotNull(linked, 'The link is stored on the gift.');
            update new Gift__c(Id = given.Id, Amount__c = 150);
            second = GiftTransactionMirrorService.copyGifts(new List<Gift__c>{ reread(given.Id) });
            third = GiftTransactionMirrorService.copyGifts(new List<Gift__c>{ reread(given.Id) });
        }
        Test.stopTest();
        Assert.areEqual(1, second.updated, 'The new amount follows the gift.');
        Assert.areEqual(1, third.unchanged, 'Nothing to write when nothing differs.');
        Assert.areEqual(linked, reread(given.Id).Gift_Transaction_Id__c, 'The same one.');
        SObject copy = Database.queryWithBinds(
            'SELECT Id, OriginalAmount FROM ' +
                GiftTransactionMirrorSchema.objectName() +
                ' WHERE Id = :linked',
            new Map<String, Object>{ 'linked' => linked },
            AccessLevel.SYSTEM_MODE
        )[0];
        Assert.areEqual(
            150,
            GiftTransactionMirrorSchema.decimalOf(copy.get('OriginalAmount')),
            'Original Amount is the gift\'s.'
        );
    }

    @IsTest
    static void aLinkedGiftTransactionThatCannotBeFoundIsReportedAndNotReplaced() {
        if (!GiftTransactionMirrorService.isAvailable()) {
            Assert.isFalse(
                GiftTransactionMirrorService.canRun(
                    GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS
                ),
                'Without Gift Transactions no run can do anything.'
            );
            return;
        }
        choose(
            GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS,
            GiftTransactionMirrorTestData.anActiveStatus(),
            START
        );
        Gift__c given = gift(100);
        given.Gift_Transaction_Id__c = aGiftTransactionId();
        insert given;
        User runner = GiftTransactionMirrorTestData.runner();
        GiftTransactionMirrorService.Result result;
        Test.startTest();
        System.runAs(runner) {
            result = GiftTransactionMirrorService.copyGifts(new List<Gift__c>{ reread(given.Id) });
        }
        Test.stopTest();
        Assert.areEqual(1, result.failed, 'Counted as not copied.');
        Assert.areEqual(0, result.created, 'No replacement is made (R-GT8).');
        Assert.areEqual(1, result.refusals.count(), 'One refusal, for the run to write.');
    }
}

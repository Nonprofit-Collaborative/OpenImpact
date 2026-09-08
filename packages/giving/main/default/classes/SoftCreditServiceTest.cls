/**
 * Automatic household soft credits, in both membership modes, at bulk, and through every path a
 * gift can take (feature G-08).
 */
@IsTest
private class SoftCreditServiceTest {
    @IsTest
    static void creditsTheOtherHouseholdMemberInContactMode() {
        RecognitionTestData.setAutomaticHouseholdCredits(true);
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        Contact luis = RecognitionTestData.person('Luis', 'Garcia', garcias.Id);

        Test.startTest();
        Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);
        Test.stopTest();

        List<Soft_Credit__c> credits = RecognitionTestData.creditsFor(gift.Id);
        System.assertEquals(1, credits.size(), 'Luis is the only other member of the household');
        System.assertEquals(luis.Id, credits[0].Contact__c, 'The spouse is the credited person');
        System.assertEquals(
            SoftCreditService.ROLE_HOUSEHOLD_MEMBER,
            credits[0].Role__c,
            'The role says why the credit is there'
        );
        System.assertEquals(500, credits[0].Amount__c, 'A household credit is for the whole gift');
        System.assertEquals(true, credits[0].Is_Automatic__c, 'The package created this credit');
    }

    @IsTest
    static void creditsTheOtherHouseholdMemberInJunctionMode() {
        RecognitionTestData.setAutomaticHouseholdCredits(true);
        RecognitionTestData.useJunctionMembership();
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', null);
        Contact luis = RecognitionTestData.person('Luis', 'Garcia', null);
        RecognitionTestData.membership(garcias.Id, ana.Id, 'Head');
        RecognitionTestData.membership(garcias.Id, luis.Id, 'Spouse or Partner');

        Test.startTest();
        Gift__c gift = RecognitionTestData.gift(ana.Id, null, 250);
        Test.stopTest();

        List<Soft_Credit__c> credits = RecognitionTestData.creditsFor(gift.Id);
        System.assertEquals(1, credits.size(), 'Junction membership credits the same one person');
        System.assertEquals(luis.Id, credits[0].Contact__c, 'The spouse is the credited person');
        System.assertEquals(250, credits[0].Amount__c, 'The credit is for the whole gift');
    }

    @IsTest
    static void creditsNobodyWhenTheSettingIsOff() {
        RecognitionTestData.setAutomaticHouseholdCredits(false);
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        RecognitionTestData.person('Luis', 'Garcia', garcias.Id);

        Test.startTest();
        Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);
        Test.stopTest();

        System.assertEquals(
            0,
            RecognitionTestData.creditsFor(gift.Id).size(),
            'The organization asked for no automatic credits'
        );
    }

    @IsTest
    static void recomputesWhenTheAmountChanges() {
        RecognitionTestData.setAutomaticHouseholdCredits(true);
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        RecognitionTestData.person('Luis', 'Garcia', garcias.Id);
        Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);

        Test.startTest();
        gift.Amount__c = 750;
        update gift;
        Test.stopTest();

        List<Soft_Credit__c> credits = RecognitionTestData.creditsFor(gift.Id);
        System.assertEquals(1, credits.size(), 'The credit is recomputed, not duplicated');
        System.assertEquals(750, credits[0].Amount__c, 'The credit follows the gift');
    }

    @IsTest
    static void movesTheCreditWhenTheDonorChanges() {
        RecognitionTestData.setAutomaticHouseholdCredits(true);
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        Contact luis = RecognitionTestData.person('Luis', 'Garcia', garcias.Id);
        Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);

        Test.startTest();
        gift.Donor_Contact__c = luis.Id;
        update gift;
        Test.stopTest();

        List<Soft_Credit__c> credits = RecognitionTestData.creditsFor(gift.Id);
        System.assertEquals(1, credits.size(), 'Still one credit, for the other member');
        System.assertEquals(ana.Id, credits[0].Contact__c, 'Ana is now the one recognized');
    }

    @IsTest
    static void removesCreditsWhenTheGiftIsRefunded() {
        RecognitionTestData.setAutomaticHouseholdCredits(true);
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        RecognitionTestData.person('Luis', 'Garcia', garcias.Id);
        Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);

        Test.startTest();
        gift.Status__c = 'Refunded';
        update gift;
        Test.stopTest();

        System.assertEquals(
            0,
            RecognitionTestData.creditsFor(gift.Id).size(),
            'A refunded gift recognizes nobody'
        );
    }

    @IsTest
    static void aRefundProducesNegativeCredits() {
        RecognitionTestData.setAutomaticHouseholdCredits(true);
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        Contact luis = RecognitionTestData.person('Luis', 'Garcia', garcias.Id);

        Test.startTest();
        Gift__c refund = RecognitionTestData.gift(ana.Id, null, -500);
        Test.stopTest();

        List<Soft_Credit__c> credits = RecognitionTestData.creditsFor(refund.Id);
        System.assertEquals(1, credits.size(), 'The refund recognizes the household too');
        System.assertEquals(luis.Id, credits[0].Contact__c, 'The same person is recognized');
        System.assertEquals(
            -500,
            credits[0].Amount__c,
            'A negative gift produces a negative credit so totals stay right'
        );
    }

    @IsTest
    static void leavesCreditsEnteredByStaffAlone() {
        RecognitionTestData.setAutomaticHouseholdCredits(true);
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        RecognitionTestData.person('Luis', 'Garcia', garcias.Id);
        Contact solicitor = RecognitionTestData.person('Tom', 'Alvarez', null);
        Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);
        Soft_Credit__c manual = RecognitionTestData.manualCredit(
            gift.Id,
            solicitor.Id,
            'Solicitor',
            500
        );

        Test.startTest();
        gift.Amount__c = 900;
        update gift;
        Test.stopTest();

        Map<Id, Soft_Credit__c> byId = new Map<Id, Soft_Credit__c>(
            RecognitionTestData.creditsFor(gift.Id)
        );
        System.assertEquals(2, byId.size(), 'Both credits are still there');
        System.assertEquals(
            500,
            byId.get(manual.Id).Amount__c,
            'The credit a person entered is not recomputed'
        );
    }

    @IsTest
    static void recomputationIsIdempotent() {
        RecognitionTestData.setAutomaticHouseholdCredits(true);
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        RecognitionTestData.person('Luis', 'Garcia', garcias.Id);
        Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);
        Id firstCreditId = RecognitionTestData.creditsFor(gift.Id)[0].Id;

        Test.startTest();
        SoftCreditService.createHouseholdMemberCredits(
            GiftLookupSelector.selectForRecognition(new Set<Id>{ gift.Id })
        );
        SoftCreditService.createHouseholdMemberCredits(
            GiftLookupSelector.selectForRecognition(new Set<Id>{ gift.Id })
        );
        Test.stopTest();

        List<Soft_Credit__c> credits = RecognitionTestData.creditsFor(gift.Id);
        System.assertEquals(1, credits.size(), 'Running twice changes nothing');
        System.assertEquals(firstCreditId, credits[0].Id, 'The same record is kept');
    }

    @IsTest
    static void removesCreditsBeforeTheGiftIsDeleted() {
        RecognitionTestData.setAutomaticHouseholdCredits(true);
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        RecognitionTestData.person('Luis', 'Garcia', garcias.Id);
        Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);
        Id giftId = gift.Id;

        Test.startTest();
        delete gift;
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Soft_Credit__c WHERE Gift__c = :giftId],
            'The credits go with the gift'
        );
    }

    @IsTest
    static void creditsTwoHundredGiftsInOneInsert() {
        RecognitionTestData.setAutomaticHouseholdCredits(true);
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        RecognitionTestData.person('Luis', 'Garcia', garcias.Id);

        List<Gift__c> gifts = new List<Gift__c>();
        for (Integer i = 0; i < 200; i++) {
            gifts.add(RecognitionTestData.newGift(ana.Id, null, 10 + i));
        }

        Test.startTest();
        insert gifts;
        Test.stopTest();

        System.assertEquals(
            200,
            [SELECT COUNT() FROM Soft_Credit__c WHERE Is_Automatic__c = TRUE],
            'Two hundred gifts credit two hundred times, in one transaction'
        );
    }

    @IsTest
    static void creditsNobodyForAnOrganizationGift() {
        RecognitionTestData.setAutomaticHouseholdCredits(true);
        Account riverbend = RecognitionTestData.organization('Riverbend Manufacturing');

        Test.startTest();
        Gift__c gift = RecognitionTestData.gift(null, riverbend.Id, 1000);
        Test.stopTest();

        System.assertEquals(
            0,
            RecognitionTestData.creditsFor(gift.Id).size(),
            'An organization has no household members'
        );
    }

    @IsTest
    static void percentAndAmountConvertBothWays() {
        System.assertEquals(
            50,
            SoftCreditService.percentOf(250, 500),
            'Half a gift is fifty percent of it'
        );
        System.assertEquals(
            250,
            SoftCreditService.amountOf(50, 500),
            'Fifty percent of a gift is half of it'
        );
        System.assertEquals(
            null,
            SoftCreditService.percentOf(250, 0),
            'A gift of nothing has no share'
        );
    }
}

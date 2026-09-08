/**
 * What the two record page panels call (features G-08 and G-09).
 */
@IsTest
private class RecognitionControllerTest {
    @IsTest
    static void listsTheCreditsOnAGift() {
        RecognitionTestData.setAutomaticHouseholdCredits(true);
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        RecognitionTestData.person('Luis', 'Garcia', garcias.Id);
        Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);

        Test.startTest();
        SoftCreditController.SoftCreditPanel panel = SoftCreditController.getCredits(gift.Id);
        Test.stopTest();

        System.assertEquals(1, panel.credits.size(), 'The household credit is listed');
        System.assertEquals(true, panel.credits[0].isAutomatic, 'And marked as automatic');
        System.assertEquals('Luis Garcia', panel.credits[0].personName, 'By name');
    }

    @IsTest
    static void addsAndRemovesACreditAPersonEntered() {
        RecognitionTestData.setAutomaticHouseholdCredits(false);
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        Contact solicitor = RecognitionTestData.person('Tom', 'Alvarez', null);
        Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);

        Test.startTest();
        SoftCreditController.SoftCreditPanel afterAdd = SoftCreditController.addCredit(
            gift.Id,
            solicitor.Id,
            'Solicitor',
            null,
            500
        );
        SoftCreditController.SoftCreditPanel afterRemove = SoftCreditController.removeCredit(
            afterAdd.credits[0].recordId
        );
        Test.stopTest();

        System.assertEquals(1, afterAdd.credits.size(), 'The credit was added');
        System.assertEquals(0, afterRemove.credits.size(), 'And removed again');
    }

    @IsTest
    static void refusesToRemoveAnAutomaticCredit() {
        RecognitionTestData.setAutomaticHouseholdCredits(true);
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        RecognitionTestData.person('Luis', 'Garcia', garcias.Id);
        Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);
        Id automaticCreditId = RecognitionTestData.creditsFor(gift.Id)[0].Id;

        Test.startTest();
        Boolean refused = false;
        try {
            SoftCreditController.removeCredit(automaticCreditId);
        } catch (Exception expected) {
            refused = true;
        }
        Test.stopTest();

        System.assertEquals(true, refused, 'It would come straight back, so it is refused');
    }

    @IsTest
    static void refusesACreditWithNoGift() {
        Test.startTest();
        Boolean refused = false;
        try {
            SoftCreditController.getCredits(null);
        } catch (Exception expected) {
            refused = true;
        }
        Test.stopTest();

        System.assertEquals(true, refused, 'A soft credit belongs to a gift');
    }

    @IsTest
    static void summarizesATributeAndMarksItSent() {
        RecognitionTestData.setAutomaticHouseholdCredits(false);
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        Gift__c gift = RecognitionTestData.gift(ana.Id, null, 100);
        Tribute__c tribute = RecognitionTestData.tribute(
            gift.Id,
            TributeService.TYPE_IN_MEMORY_OF,
            'Rosa Garcia'
        );
        tribute.Notification_Recipient_Contact__c = ana.Id;
        insert tribute;

        Test.startTest();
        TributeController.TributeView before = TributeController.getTribute(gift.Id);
        TributeController.TributeView after = TributeController.markNotificationSent(tribute.Id);
        Test.stopTest();

        System.assertEquals('Rosa Garcia', before.honoreeName, 'The honoree is named');
        System.assertEquals('Ana Garcia', before.recipientName, 'And so is the person to tell');
        System.assertEquals(false, before.notificationSent, 'Nothing had gone out yet');
        System.assertEquals(true, after.notificationSent, 'Now it has');
        System.assertEquals(Date.today(), after.notificationSentDate, 'With the date it went');
    }

    @IsTest
    static void answersWithNothingWhenAGiftHasNoTribute() {
        RecognitionTestData.setAutomaticHouseholdCredits(false);
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        Gift__c gift = RecognitionTestData.gift(ana.Id, null, 100);

        Test.startTest();
        TributeController.TributeView view = TributeController.getTribute(gift.Id);
        Test.stopTest();

        System.assertEquals(null, view, 'Most gifts honor nobody, and that is not an error');
    }

    @IsTest
    static void refusesToMarkATributeThatIsNotThere() {
        Test.startTest();
        Boolean refused = false;
        try {
            TributeController.markNotificationSent(null);
        } catch (Exception expected) {
            refused = true;
        }
        Test.stopTest();

        System.assertEquals(true, refused, 'The panel is told what went wrong');
    }
}

/**
 * At most one fund is the default, and Maria never has to remember to untick the old one
 * (R-F1).
 */
@IsTest
private class FundTriggerHandlerTest {
    @IsTest
    static void markingANewDefaultClearsTheOldOne() {
        Fund__c general = GivingTestDataFactory.buildFund('General', true);
        insert general;
        Fund__c annual = GivingTestDataFactory.buildFund('Annual Fund', false);
        insert annual;

        Test.startTest();
        annual.Is_Default__c = true;
        update annual;
        Test.stopTest();

        System.assertEquals(
            false,
            [SELECT Is_Default__c FROM Fund__c WHERE Id = :general.Id].Is_Default__c,
            'Only one fund catches undesignated gifts.'
        );
        System.assertEquals(
            true,
            [SELECT Is_Default__c FROM Fund__c WHERE Id = :annual.Id].Is_Default__c,
            'The fund Maria just marked is the default.'
        );
    }

    @IsTest
    static void twoDefaultsInOneSaveAreRefused() {
        String message = '';

        Test.startTest();
        try {
            insert new List<Fund__c>{
                GivingTestDataFactory.buildFund('General', true),
                GivingTestDataFactory.buildFund('Building', true)
            };
        } catch (DmlException twoDefaults) {
            message = twoDefaults.getDmlMessage(0);
        }
        Test.stopTest();

        System.assert(
            message.contains('Only one fund can be the default'),
            'Two defaults in one save has no defensible answer: ' + message
        );
    }

    @IsTest
    static void theDefaultFundIsResolvedForGiftEntry() {
        Fund__c general = GivingTestDataFactory.buildFund('General', true);
        insert general;

        Test.startTest();
        Id resolved = GiftService.resolveDefaultFundId();
        Test.stopTest();

        System.assertEquals(general.Id, resolved, 'The flagged fund is the default fund.');
    }

    @IsTest
    static void withNoFundAtAllThereIsNoDefault() {
        Test.startTest();
        Id resolved = GiftService.resolveDefaultFundId();
        Test.stopTest();

        System.assertEquals(
            null,
            resolved,
            'A fresh org has no default fund yet, and says so rather than guessing.'
        );
    }

    @IsTest
    static void twoHundredFundsSaveInOneGo() {
        List<Fund__c> funds = new List<Fund__c>();
        for (Integer i = 0; i < 200; i++) {
            funds.add(GivingTestDataFactory.buildFund('Fund ' + i, false));
        }

        Test.startTest();
        insert funds;
        Test.stopTest();

        System.assertEquals(200, [SELECT COUNT() FROM Fund__c], 'Two hundred in one save.');
    }
}

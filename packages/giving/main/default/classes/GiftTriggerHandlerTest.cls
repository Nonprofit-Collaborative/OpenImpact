/**
 * David enters gifts. These tests are the rules he never has to think about: the household
 * arrives by itself, a gift with no date is today's gift, a receipted gift stops changing, and
 * a gift with no designation still lands in a fund.
 */
@IsTest
private class GiftTriggerHandlerTest {
    @TestSetup
    static void makeData() {
        GivingTestDataFactory.insertDefaultFund();
        GivingTestDataFactory.insertHouseholdContact('The Nolan Family', 'Ana', 'Nolan');
    }

    private static Contact donor() {
        return [SELECT Id, AccountId FROM Contact LIMIT 1];
    }

    @IsTest
    static void householdIsDerivedFromTheDonorContact() {
        Contact person = donor();

        Test.startTest();
        Gift__c gift = GivingTestDataFactory.buildGift(person.Id, 250);
        insert gift;
        Test.stopTest();

        Gift__c saved = [SELECT Id, Household__c, Gift_Date__c FROM Gift__c WHERE Id = :gift.Id];
        System.assertEquals(
            person.AccountId,
            saved.Household__c,
            'David should not have to fill in the household: it comes from the donor.'
        );
        System.assertEquals(
            Date.today(),
            saved.Gift_Date__c,
            'A gift saved without a date is a gift that arrived today.'
        );
    }

    @IsTest
    static void householdIsClearedWhenTheDonorChangesToAnOrganization() {
        Contact person = donor();
        Gift__c gift = GivingTestDataFactory.buildGift(person.Id, 100);
        insert gift;
        Account employer = GivingTestDataFactory.insertOrganization('Riverside Foundation');

        Test.startTest();
        gift.Donor_Contact__c = null;
        gift.Donor_Account__c = employer.Id;
        update gift;
        Test.stopTest();

        Gift__c saved = [SELECT Id, Household__c FROM Gift__c WHERE Id = :gift.Id];
        System.assertEquals(
            null,
            saved.Household__c,
            'An organization has no household, so the gift should not keep the old one.'
        );
    }

    @IsTest
    static void householdIsTheDonorAccountWhenThatAccountIsAHousehold() {
        List<RecordType> householdTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account' AND DeveloperName = 'Household'
            LIMIT 1
        ];
        if (householdTypes.isEmpty()) {
            return;
        }
        Account household = new Account(
            Name = 'The Okafor Family',
            RecordTypeId = householdTypes[0].Id
        );
        insert household;

        Test.startTest();
        Gift__c gift = GivingTestDataFactory.buildAccountGift(household.Id, 500);
        insert gift;
        Test.stopTest();

        Gift__c saved = [SELECT Id, Household__c FROM Gift__c WHERE Id = :gift.Id];
        System.assertEquals(
            household.Id,
            saved.Household__c,
            'A household giving in its own name is credited to itself.'
        );
    }

    @IsTest
    static void personHeldAsAnAccountGetsItsHouseholdFromCore() {
        if (!OrgShapeDetector.detect().hasPersonAccounts) {
            return;
        }
        Set<Id> personTypeIds = OrgShapeDetector.detect().personAccountRecordTypeIds;
        if (personTypeIds.isEmpty()) {
            return;
        }
        Account person = new Account();
        person.put('LastName', 'Okafor');
        person.put('RecordTypeId', new List<Id>(personTypeIds)[0]);
        insert person;

        Test.startTest();
        Gift__c gift = GivingTestDataFactory.buildAccountGift(person.Id, 75);
        insert gift;
        Test.stopTest();

        Gift__c saved = [SELECT Id, Donor_Account__c FROM Gift__c WHERE Id = :gift.Id];
        System.assertEquals(
            person.Id,
            saved.Donor_Account__c,
            'A person held as an account is a donor account, and the household comes from Core.'
        );
    }

    @IsTest
    static void aReceiptedGiftStopsChanging() {
        Contact person = donor();
        Gift__c gift = GivingTestDataFactory.buildGift(person.Id, 250);
        insert gift;
        gift.Receipt_Number__c = 'R-000001';
        update gift;

        String message = '';
        Test.startTest();
        try {
            gift.Amount__c = 300;
            update gift;
        } catch (DmlException lockError) {
            message = lockError.getDmlMessage(0);
        }
        Test.stopTest();

        System.assert(
            message.contains('receipt number'),
            'The amount on a receipted gift must not change: ' + message
        );
    }

    @IsTest
    static void changingTheAmountMovesTheOnlyAllocationWithIt() {
        Contact person = donor();
        Gift__c gift = GivingTestDataFactory.buildGift(person.Id, 250);
        insert gift;

        Test.startTest();
        gift.Amount__c = 400;
        update gift;
        Test.stopTest();

        Gift_Allocation__c allocation = [
            SELECT Id, Amount__c
            FROM Gift_Allocation__c
            WHERE Gift__c = :gift.Id
        ];
        System.assertEquals(
            400,
            allocation.Amount__c,
            'A gift with one allocation carries that allocation with it.'
        );
    }

    @IsTest
    static void changingTheAmountOfASplitGiftIsRefused() {
        Contact person = donor();
        Fund__c second = GivingTestDataFactory.buildFund('Scholarship', false);
        insert second;
        Gift__c gift = GivingTestDataFactory.buildGift(person.Id, 200);
        Fund__c general = [SELECT Id FROM Fund__c WHERE Is_Default__c = TRUE LIMIT 1];
        try {
            GiftService.suppressDefaultAllocations = true;
            insert gift;
        } finally {
            GiftService.suppressDefaultAllocations = false;
        }
        insert new List<Gift_Allocation__c>{
            GivingTestDataFactory.buildAllocation(gift.Id, general.Id, 150),
            GivingTestDataFactory.buildAllocation(gift.Id, second.Id, 50)
        };

        String message = '';
        Test.startTest();
        try {
            gift.Amount__c = 300;
            update gift;
        } catch (DmlException splitError) {
            message = splitError.getDmlMessage(0);
        }
        Test.stopTest();

        System.assert(
            message.contains('split across more than one fund'),
            'A split gift cannot have its amount changed silently: ' + message
        );
    }

    @IsTest
    static void twoHundredGiftsSaveInOneGo() {
        Contact person = donor();

        Test.startTest();
        List<Gift__c> gifts = GivingTestDataFactory.buildGifts(person.Id, 200, 25);
        insert gifts;
        Test.stopTest();

        System.assertEquals(
            200,
            [SELECT COUNT() FROM Gift__c],
            'Two hundred gifts in one save is the governor-limit bar (plan Section 7.2).'
        );
        System.assertEquals(
            200,
            [SELECT COUNT() FROM Gift_Allocation__c],
            'Every one of them gets its default allocation.'
        );
    }
}

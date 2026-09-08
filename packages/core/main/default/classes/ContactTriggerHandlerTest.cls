/**
 * The household upkeep that happens when a person is saved, changed, deleted, or restored.
 */
@IsTest
private class ContactTriggerHandlerTest {
    @IsTest
    static void changingASurnameRenamesTheHousehold() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        insert maria;
        Id household = [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId;

        Test.startTest();
        update new Contact(Id = maria.Id, LastName = 'Garcia-Lee');
        Test.stopTest();

        Assert.areEqual(
            'The Garcia-Lee Family',
            [SELECT Name FROM Account WHERE Id = :household].Name,
            'The household follows the surname'
        );
    }

    @IsTest
    static void markingSomeoneDeceasedRewritesTheGreetings() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account household = HouseholdTestDataFactory.newHousehold('The Smith Family');
        insert household;
        Contact john = new Contact(
            Salutation = 'Mr.',
            FirstName = 'John',
            LastName = 'Smith',
            AccountId = household.Id
        );
        Contact jane = new Contact(
            Salutation = 'Mrs.',
            FirstName = 'Jane',
            LastName = 'Smith',
            AccountId = household.Id
        );
        insert new List<Contact>{ john, jane };

        Test.startTest();
        update new Contact(Id = jane.Id, Deceased__c = true);
        Test.stopTest();

        Assert.areEqual(
            'John',
            [SELECT Household_Informal_Greeting__c FROM Account WHERE Id = :household.Id]
            .Household_Informal_Greeting__c,
            'Jane is no longer greeted'
        );
    }

    @IsTest
    static void deletingTheLastMemberTidiesTheHouseholdAway() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        insert maria;
        Id household = [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId;

        Test.startTest();
        delete maria;
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Account WHERE Id = :household],
            'The empty household went too'
        );
    }

    @IsTest
    static void restoringAPersonPutsTheCountBack() {
        Nonprofit_Settings__c settings = HouseholdTestDataFactory.settings(
            HouseholdTestDataFactory.MODE_CONTACT
        );
        settings.Delete_Empty_Households__c = false;
        HouseholdTestDataFactory.save(settings);
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        insert maria;
        Id household = [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId;
        delete maria;

        Test.startTest();
        undelete maria;
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT Member_Count__c FROM Account WHERE Id = :household].Member_Count__c,
            'Maria is counted again'
        );
    }

    @IsTest
    static void movingSomeoneByEditingTheirHouseholdRecountsBoth() {
        Nonprofit_Settings__c settings = HouseholdTestDataFactory.settings(
            HouseholdTestDataFactory.MODE_CONTACT
        );
        settings.Delete_Empty_Households__c = false;
        HouseholdTestDataFactory.save(settings);
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
        insert new List<Contact>{ maria, wei };
        Id fromHousehold = [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId;
        Id toHousehold = [SELECT AccountId FROM Contact WHERE Id = :wei.Id].AccountId;

        Test.startTest();
        update new Contact(Id = maria.Id, AccountId = toHousehold);
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT Member_Count__c FROM Account WHERE Id = :fromHousehold].Member_Count__c,
            'The household Maria left counts nobody'
        );
        Assert.areEqual(
            'Garcia and Lee Household',
            [SELECT Name FROM Account WHERE Id = :toHousehold].Name,
            'The household Maria joined lists both surnames'
        );
    }
}

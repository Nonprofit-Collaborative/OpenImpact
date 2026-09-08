/**
 * The household upkeep that happens when a household itself is saved or changed.
 */
@IsTest
private class AccountTriggerHandlerTest {
    @IsTest
    static void aHouseholdSavedWithNoNameGetsAPlaceholder() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);

        Test.startTest();
        Account household = new Account(RecordTypeId = HouseholdService.householdRecordTypeId());
        insert household;
        Test.stopTest();

        Assert.areEqual(
            Label.Core_Households_NamePlaceholder,
            [SELECT Name FROM Account WHERE Id = :household.Id].Name,
            'An empty household is never saved without a name'
        );
    }

    @IsTest
    static void clearingTheCustomNameBoxRenamesTheHousehold() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account household = HouseholdTestDataFactory.newHousehold('The Reverend and Mrs. Smith');
        household.Custom_Name__c = true;
        insert household;
        insert new Contact(
            Salutation = 'Mr.',
            FirstName = 'John',
            LastName = 'Smith',
            AccountId = household.Id
        );

        Test.startTest();
        update new Account(Id = household.Id, Custom_Name__c = false);
        Test.stopTest();

        Assert.areEqual(
            'The Smith Family',
            [SELECT Name FROM Account WHERE Id = :household.Id].Name,
            'The household goes back to being named from the pattern'
        );
    }

    @IsTest
    static void checkingTheCustomNameBoxLeavesTheWordingAlone() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
        insert john;
        Id household = [SELECT AccountId FROM Contact WHERE Id = :john.Id].AccountId;

        Test.startTest();
        update new Account(
            Id = household,
            Custom_Name__c = true,
            Name = 'The Reverend and Mrs. Smith'
        );
        Test.stopTest();

        Assert.areEqual(
            'The Reverend and Mrs. Smith',
            [SELECT Name FROM Account WHERE Id = :household].Name,
            'David keeps his wording'
        );
    }

    @IsTest
    static void anOrganizationIsNeverRenamed() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);

        Test.startTest();
        Account organization = new Account(Name = 'Riverside Community Trust');
        insert organization;
        update new Account(Id = organization.Id, Custom_Name__c = false);
        Test.stopTest();

        Assert.areEqual(
            'Riverside Community Trust',
            [SELECT Name FROM Account WHERE Id = :organization.Id].Name,
            'Household naming never touches an organization'
        );
    }

    @IsTest
    static void householdsForPeopleStoredAsAccountsAreOnlyMadeWhenAskedFor() {
        Nonprofit_Settings__c settings = HouseholdTestDataFactory.settings(
            HouseholdTestDataFactory.MODE_JUNCTION
        );
        settings.Create_Households_For_Person_Accounts__c = false;
        HouseholdTestDataFactory.save(settings);
        HouseholdService.personAccountOverride = true;

        Test.startTest();
        insert new Account(Name = 'Maria Garcia');
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Household_Member__c],
            'The setting is off, so nothing was created'
        );
    }

    @IsTest
    static void aPersonStoredAsAnAccountGetsAHouseholdWhenTheSettingIsOn() {
        Nonprofit_Settings__c settings = HouseholdTestDataFactory.settings(
            HouseholdTestDataFactory.MODE_JUNCTION
        );
        settings.Create_Households_For_Person_Accounts__c = true;
        HouseholdTestDataFactory.save(settings);
        HouseholdService.personAccountOverride = true;
        PersonRecordSelector.personRecordOverride = true;
        // The org running this test may have no person name fields at all, so the test
        // declares the person these details belong to.
        PersonRecordSelector.personOverridesByName = new Map<String, HouseholdService.Person>{
            'Maria Garcia' => HouseholdTestDataFactory.person('Ms.', 'Maria', 'Garcia', 'Head')
        };

        Test.startTest();
        insert new Account(Name = 'Maria Garcia');
        Test.stopTest();

        List<Household_Member__c> memberships = [
            SELECT
                Household__c,
                Account__c,
                Role__c,
                Is_Primary__c,
                Household__r.Name,
                Household__r.Member_Count__c,
                Household__r.RecordTypeId
            FROM Household_Member__c
        ];
        Assert.areEqual(1, memberships.size(), 'Maria was joined to a household');
        Assert.areEqual(
            HouseholdService.householdRecordTypeId(),
            memberships[0].Household__r.RecordTypeId,
            'The household is a household'
        );
        Assert.areEqual(
            'The Garcia Family',
            memberships[0].Household__r.Name,
            'And it is named from her surname'
        );
        Assert.areEqual(1, memberships[0].Household__r.Member_Count__c, 'And counts her');
        Assert.areEqual('Head', memberships[0].Role__c, 'She heads her own household');
        Assert.isTrue(memberships[0].Is_Primary__c, 'And is its primary member');
    }
}

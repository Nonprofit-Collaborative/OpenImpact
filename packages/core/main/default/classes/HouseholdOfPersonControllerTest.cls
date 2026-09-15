/**
 * What the Household panel on a person and the Make primary action ask for: the household
 * a person belongs to in either way of belonging, the empty state, and the primary contact
 * being moved from one membership record to another.
 */
@IsTest
private class HouseholdOfPersonControllerTest {
    @IsTest
    static void aContactPointsAtItsHouseholdInTheSimpleWay() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account household = HouseholdTestDataFactory.newHousehold('The Smith Family');
        household.Household_Formal_Greeting__c = 'Mr. John Smith';
        household.Member_Count__c = 1;
        insert household;
        Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
        john.AccountId = household.Id;
        insert john;

        Test.startTest();
        List<HouseholdOfPersonController.HouseholdView> households = HouseholdOfPersonController.getHouseholdsForPerson(
            john.Id
        );
        Test.stopTest();

        Assert.areEqual(1, households.size(), 'John is in one household');
        Assert.areEqual(household.Id, households[0].householdId, 'It is the one he points at');
        Assert.areEqual(1, households[0].memberCount, 'The member count is shown');
        Assert.isTrue(
            String.isNotBlank(households[0].formalGreeting),
            'The formal greeting is shown'
        );
        Assert.isTrue(String.isNotBlank(households[0].name), 'The household is named');
    }

    @IsTest
    static void aContactWhoPointsAtAnOrganizationIsInNoHousehold() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        HouseholdService.suspendAutomaticCreation();
        Account organization = new Account(Name = 'The Union Foundation');
        insert organization;
        Contact harper = HouseholdTestDataFactory.newContact('Ms.', 'Harper', 'Garcia');
        harper.AccountId = organization.Id;
        insert harper;

        Test.startTest();
        List<HouseholdOfPersonController.HouseholdView> households = HouseholdOfPersonController.getHouseholdsForPerson(
            harper.Id
        );
        Test.stopTest();

        Assert.isTrue(households.isEmpty(), 'An organization is not a household');
    }

    @IsTest
    static void aMembershipRecordPointsAtTheHouseholdInTheFlexibleWay() {
        HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
        Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        insert household;
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        insert maria;
        insert new Household_Member__c(
            Household__c = household.Id,
            Contact__c = maria.Id,
            Role__c = 'Head',
            Is_Primary__c = true,
            Start_Date__c = Date.today()
        );

        Test.startTest();
        List<HouseholdOfPersonController.HouseholdView> households = HouseholdOfPersonController.getHouseholdsForPerson(
            maria.Id
        );
        Test.stopTest();

        Assert.areEqual(1, households.size(), 'Maria is in one household');
        Assert.areEqual(
            household.Id,
            households[0].householdId,
            'It is the one her membership names'
        );
    }

    @IsTest
    static void aPersonWithNoMembershipIsInNoHousehold() {
        HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
        Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
        insert wei;

        Test.startTest();
        List<HouseholdOfPersonController.HouseholdView> households = HouseholdOfPersonController.getHouseholdsForPerson(
            wei.Id
        );
        Test.stopTest();

        Assert.isTrue(households.isEmpty(), 'Nobody has joined Wei to a household yet');
    }

    @IsTest
    static void askingAboutNobodyIsAnsweredWithNothing() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);

        Test.startTest();
        List<HouseholdOfPersonController.HouseholdView> households = HouseholdOfPersonController.getHouseholdsForPerson(
            null
        );
        Test.stopTest();

        Assert.isTrue(households.isEmpty(), 'No person, no household');
    }

    @IsTest
    static void makePrimaryMovesTheFlagToThePersonChosen() {
        HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
        Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        insert household;
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
        insert new List<Contact>{ maria, wei };
        Household_Member__c mariaRow = new Household_Member__c(
            Household__c = household.Id,
            Contact__c = maria.Id,
            Is_Primary__c = true,
            Start_Date__c = Date.today()
        );
        Household_Member__c weiRow = new Household_Member__c(
            Household__c = household.Id,
            Contact__c = wei.Id,
            Is_Primary__c = false,
            Start_Date__c = Date.today()
        );
        insert new List<Household_Member__c>{ mariaRow, weiRow };

        Test.startTest();
        HouseholdOfPersonController.makePrimary(household.Id, wei.Id);
        Test.stopTest();

        Map<Id, Household_Member__c> rows = new Map<Id, Household_Member__c>(
            [SELECT Id, Is_Primary__c FROM Household_Member__c WHERE Household__c = :household.Id]
        );
        Assert.isTrue(rows.get(weiRow.Id).Is_Primary__c, 'Wei is now the primary contact');
        Assert.isFalse(rows.get(mariaRow.Id).Is_Primary__c, 'Maria no longer is');
    }

    @IsTest
    static void makePrimaryOnSomebodyOutsideTheHouseholdIsRefused() {
        HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
        Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        insert household;
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        Contact stranger = HouseholdTestDataFactory.newContact('Mr.', 'Sam', 'Stone');
        insert new List<Contact>{ maria, stranger };
        insert new Household_Member__c(
            Household__c = household.Id,
            Contact__c = maria.Id,
            Is_Primary__c = true,
            Start_Date__c = Date.today()
        );
        String message;

        Test.startTest();
        try {
            HouseholdOfPersonController.makePrimary(household.Id, stranger.Id);
        } catch (AuraHandledException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.areEqual(
            Label.Core_HouseholdPanel_NotAMember,
            message,
            'The screen is told in plain words that the person is not a member'
        );
        Assert.isTrue(
            [
                SELECT Is_Primary__c
                FROM Household_Member__c
                WHERE Household__c = :household.Id
                LIMIT 1
            ]
            .Is_Primary__c,
            'Maria is still the primary contact'
        );
    }

    @IsTest
    static void makePrimaryWithNothingChosenIsRefused() {
        HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
        Boolean refused = false;

        Test.startTest();
        try {
            HouseholdOfPersonController.makePrimary(null, null);
        } catch (AuraHandledException e) {
            refused = true;
        }
        Test.stopTest();

        Assert.isTrue(refused, 'Nothing chosen, nothing changed');
    }

    @IsTest
    static void aUserWhoCannotEditMembershipsGetsAFriendlyRefusal() {
        HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
        Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        insert household;
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
        insert new List<Contact>{ maria, wei };
        insert new List<Household_Member__c>{
            new Household_Member__c(
                Household__c = household.Id,
                Contact__c = maria.Id,
                Is_Primary__c = true,
                Start_Date__c = Date.today()
            ),
            new Household_Member__c(
                Household__c = household.Id,
                Contact__c = wei.Id,
                Is_Primary__c = false,
                Start_Date__c = Date.today()
            )
        };
        User reader = HouseholdTestDataFactory.standardUser('reader');
        HouseholdTestDataFactory.grantMembershipRead('Membership_Read_Only', reader.Id);
        String message;

        Test.startTest();
        System.runAs(reader) {
            try {
                HouseholdOfPersonController.makePrimary(household.Id, wei.Id);
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
        }
        Test.stopTest();

        Assert.isNotNull(message, 'A user without edit access is refused');
        Assert.isFalse(
            message.containsIgnoreCase('INSUFFICIENT'),
            'The refusal is worded for a person, not copied from the platform'
        );
    }
}

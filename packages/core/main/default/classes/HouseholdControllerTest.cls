/**
 * What the household screens ask for: the naming preview, the members panel, the move
 * action, and the recompute.
 */
@IsTest
private class HouseholdControllerTest {
    @IsTest
    static void thePreviewShowsFiveSampleHouseholds() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);

        Test.startTest();
        List<HouseholdController.HouseholdPreview> rows = HouseholdController.preview(
            'The {LastName} Family',
            '{Salutation} {FirstName} {LastName}',
            '{FirstName}'
        );
        Test.stopTest();

        Assert.areEqual(5, rows.size(), 'Maria sees five sample households');
        Assert.areEqual(
            'The Smith Family',
            rows[0].name,
            'The first sample is a couple who share a surname'
        );
        Assert.areEqual(
            'Mr. and Mrs. John Smith',
            rows[0].formalGreeting,
            'The formal greeting is combined'
        );
        Assert.areEqual(
            'John and Jane',
            rows[0].informalGreeting,
            'The informal greeting names both'
        );
    }

    @IsTest
    static void thePreviewFollowsThePatternBeingTyped() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);

        Test.startTest();
        List<HouseholdController.HouseholdPreview> rows = HouseholdController.preview(
            '{LastName} Household',
            '{Salutation} {FirstName} {LastName}',
            '{FirstName}'
        );
        Test.stopTest();

        Assert.areEqual(
            'Smith Household',
            rows[0].name,
            'The preview uses the pattern, not the saved one'
        );
    }

    @IsTest
    static void theMembersPanelListsTheHousehold() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account household = HouseholdTestDataFactory.newHousehold('The Smith Family');
        insert household;
        Contact john = new Contact(
            Salutation = 'Mr.',
            FirstName = 'John',
            LastName = 'Smith',
            AccountId = household.Id,
            Household_Role__c = 'Head'
        );
        insert john;
        update new Account(Id = household.Id, Primary_Contact__c = john.Id);

        Test.startTest();
        List<HouseholdController.MemberView> members = HouseholdController.getMembers(household.Id);
        Test.stopTest();

        Assert.areEqual(1, members.size(), 'One member');
        Assert.areEqual('John Smith', members[0].name, 'The member is named in full');
        Assert.areEqual('Head', members[0].role, 'The role is shown');
        Assert.isFalse(members[0].isDeceased, 'John is alive');
    }

    @IsTest
    static void askingForMembersOfSomethingThatIsNotAHouseholdIsRefused() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        insert maria;
        Boolean refused = false;

        Test.startTest();
        try {
            HouseholdController.getMembers(maria.Id);
        } catch (Exception e) {
            refused = true;
        }
        Test.stopTest();

        Assert.isTrue(refused, 'A person is not a household');
    }

    @IsTest
    static void movingSomeoneFromThePanelMovesThem() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
        insert new List<Contact>{ maria, wei };
        Id toHousehold = [SELECT AccountId FROM Contact WHERE Id = :wei.Id].AccountId;

        Test.startTest();
        HouseholdController.moveContact(maria.Id, toHousehold);
        Test.stopTest();

        Assert.areEqual(
            toHousehold,
            [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId,
            'Maria is in the household she was moved to'
        );
    }

    @IsTest
    static void movingSomeoneNowhereReturnsAMessageTheScreenCanShow() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Boolean refused = false;

        Test.startTest();
        try {
            HouseholdController.moveContact(null, null);
        } catch (Exception e) {
            refused = true;
        }
        Test.stopTest();

        Assert.isTrue(refused, 'The screen is told that nothing was chosen');
    }

    @IsTest
    static void recomputeAllStartsTheJob() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);

        Test.startTest();
        String jobId = HouseholdController.recomputeAll();
        Test.stopTest();

        Assert.isNotNull(jobId, 'Maria gets a job to watch');
    }
}

/**
 * What the merge and split screen calls, including the picker and the read only check.
 */
@IsTest
private class HouseholdMergeControllerTest {
    @IsTest
    static void theSearchOffersHouseholdsAndNotOrganizations() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        Account duplicate = HouseholdTestDataFactory.newHousehold('Garcia Household');
        Account organization = new Account(Name = 'Garcia Family Foundation');
        insert new List<Account>{ household, duplicate, organization };

        Test.startTest();
        List<HouseholdMergeController.HouseholdOption> options = HouseholdMergeController.searchHouseholds(
            'Garcia',
            household.Id
        );
        Test.stopTest();

        Assert.areEqual(1, options.size(), 'Only the other household is offered');
        Assert.areEqual(duplicate.Id, options[0].id, 'And it is the duplicate');
    }

    @IsTest
    static void aVeryShortSearchAsksForMore() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);

        Test.startTest();
        List<HouseholdMergeController.HouseholdOption> options = HouseholdMergeController.searchHouseholds(
            'G',
            null
        );
        Test.stopTest();

        Assert.isTrue(options.isEmpty(), 'One letter is not a search');
    }

    @IsTest
    static void theScreenIsToldWhenThePersonCanEdit() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        insert household;

        Test.startTest();
        Boolean canEdit = HouseholdMergeController.canEdit(household.Id);
        Test.stopTest();

        Assert.isTrue(canEdit, 'The person who created it can edit it');
        Assert.isFalse(HouseholdMergeController.canEdit(null), 'Nothing is not editable');
    }

    @IsTest
    static void previewReachesTheScreen() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account survivor = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        Account victim = HouseholdTestDataFactory.newHousehold('Garcia Household');
        insert new List<Account>{ survivor, victim };

        Test.startTest();
        HouseholdMergeService.MergePreview preview = HouseholdMergeController.preview(
            survivor.Id,
            victim.Id
        );
        Test.stopTest();

        Assert.areEqual(survivor.Id, preview.survivorId, 'The survivor comes back');
        Assert.isTrue(preview.canEdit, 'The person who created both may merge them');
        Assert.isFalse(preview.fields.isEmpty(), 'There is something to compare');
    }

    @IsTest
    static void mergeFromTheScreenReturnsTheSurvivor() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
        insert new List<Contact>{ maria, wei };
        Id survivorId = [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId;
        Id victimId = [SELECT AccountId FROM Contact WHERE Id = :wei.Id].AccountId;

        Test.startTest();
        Id result = HouseholdMergeController.mergeHouseholds(
            survivorId,
            victimId,
            new Map<String, String>()
        );
        Test.stopTest();

        Assert.areEqual(survivorId, result, 'The screen is sent to the survivor');
        Assert.areEqual(
            2,
            [SELECT Member_Count__c FROM Account WHERE Id = :survivorId].Member_Count__c,
            'Both people are in it'
        );
    }

    @IsTest
    static void splitFromTheScreenReturnsTheNewHousehold() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        insert maria;
        Id householdId = [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId;
        Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
        wei.AccountId = householdId;
        insert wei;

        Test.startTest();
        Id created = HouseholdMergeController.splitHousehold(
            householdId,
            new List<Id>{ wei.Id },
            null
        );
        Test.stopTest();

        Assert.isNotNull(created, 'The screen is sent to the household that was created');
        Assert.areEqual(
            created,
            [SELECT AccountId FROM Contact WHERE Id = :wei.Id].AccountId,
            'Wei is in it'
        );
    }

    @IsTest
    static void aRefusalReachesTheScreenAsSomethingAPersonCanRead() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        Account organization = new Account(Name = 'Bay Area Food Bank');
        insert new List<Account>{ household, organization };

        String message;
        Test.startTest();
        try {
            HouseholdMergeController.mergeHouseholds(
                household.Id,
                organization.Id,
                new Map<String, String>()
            );
        } catch (Exception e) {
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.areEqual(
            Label.Core_HouseholdMerge_ErrorNotHousehold,
            message,
            'The screen shows the same words the guide quotes'
        );
    }
}

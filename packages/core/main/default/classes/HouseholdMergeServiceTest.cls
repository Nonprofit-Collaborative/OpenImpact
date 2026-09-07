/**
 * Combining and separating households, in both membership modes.
 * Canonical model R-H11, R-H12, R-H13.
 */
@IsTest
private class HouseholdMergeServiceTest {
    // ------------------------------------------------------------------ preview

    @IsTest
    static void previewShowsWhereTheTwoHouseholdsDisagree() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account survivor = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        survivor.BillingCity = 'Oakland';
        Account victim = HouseholdTestDataFactory.newHousehold('Garcia Household');
        victim.BillingCity = 'Oakland';
        victim.Anniversary__c = Date.newInstance(2010, 6, 12);
        insert new List<Account>{ survivor, victim };

        Test.startTest();
        HouseholdMergeService.MergePreview preview = HouseholdMergeService.preview(
            survivor.Id,
            victim.Id
        );
        Test.stopTest();

        Assert.areEqual('The Garcia Family', preview.survivorName, 'The survivor is named');
        Assert.areEqual('Garcia Household', preview.victimName, 'The other household is named');
        Map<String, HouseholdMergeService.FieldChoice> byField = byFieldName(preview);
        Assert.isTrue(byField.get('Name').inConflict, 'The two names disagree');
        Assert.isTrue(byField.get('Anniversary__c').inConflict, 'Only one has an anniversary');
        Assert.isFalse(byField.get('BillingCity').inConflict, 'Both are in the same city');
        Assert.isFalse(
            byField.get('BillingStreet').inConflict,
            'Two empty values are not a disagreement'
        );
    }

    @IsTest
    static void previewListsEveryoneFromBothHouseholds() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
        insert new List<Contact>{ maria, wei };
        Id survivorId = householdOf(maria.Id);
        Id victimId = householdOf(wei.Id);

        Test.startTest();
        HouseholdMergeService.MergePreview preview = HouseholdMergeService.preview(
            survivorId,
            victimId
        );
        Test.stopTest();

        Assert.areEqual(2, preview.members.size(), 'Both people are listed');
        Set<String> names = new Set<String>();
        for (HouseholdMergeService.MemberChoice member : preview.members) {
            names.add(member.name);
        }
        Assert.isTrue(names.contains('Maria Garcia'), 'Maria is listed');
        Assert.isTrue(names.contains('Wei Lee'), 'Wei is listed');
    }

    // ------------------------------------------------------------------ merge, contact mode

    @IsTest
    static void mergeMovesEveryoneAndRemovesTheOtherHousehold() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
        insert new List<Contact>{ maria, wei };
        Id survivorId = householdOf(maria.Id);
        Id victimId = householdOf(wei.Id);

        Test.startTest();
        Id result = HouseholdMergeService.mergeHouseholds(
            survivorId,
            victimId,
            new HouseholdMergeService.MergeChoices(null)
        );
        Test.stopTest();

        Assert.areEqual(survivorId, result, 'The survivor is answered');
        Assert.areEqual(
            survivorId,
            householdOf(wei.Id),
            'Wei now belongs to the surviving household'
        );
        Account survivor = [
            SELECT Name, Member_Count__c
            FROM Account
            WHERE Id = :survivorId
        ];
        Assert.areEqual(2, survivor.Member_Count__c, 'The survivor counts both people');
        Assert.areEqual(
            'Garcia and Lee Household',
            survivor.Name,
            'The name was recalculated from both members'
        );
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Account WHERE Id = :victimId AND IsDeleted = FALSE],
            'The other household is gone'
        );
    }

    @IsTest
    static void mergeKeepsTheChosenNameWhenTheCustomNameBoxIsTaken() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
        insert new List<Contact>{ maria, wei };
        Id survivorId = householdOf(maria.Id);
        Id victimId = householdOf(wei.Id);
        update new Account(
            Id = victimId,
            Name = 'The Reverend and Mrs. Garcia',
            Custom_Name__c = true
        );

        Test.startTest();
        HouseholdMergeService.mergeHouseholds(
            survivorId,
            victimId,
            new HouseholdMergeService.MergeChoices(
                new Map<String, String>{
                    'Name' => HouseholdMergeService.KEEP_VICTIM,
                    'Custom_Name__c' => HouseholdMergeService.KEEP_VICTIM
                }
            )
        );
        Test.stopTest();

        Account survivor = [
            SELECT Name, Custom_Name__c, Member_Count__c
            FROM Account
            WHERE Id = :survivorId
        ];
        Assert.areEqual(
            'The Reverend and Mrs. Garcia',
            survivor.Name,
            'The wording the person chose stands'
        );
        Assert.isTrue(survivor.Custom_Name__c, 'The household is now one nothing recomputes');
        Assert.areEqual(2, survivor.Member_Count__c, 'The count is still brought up to date');
    }

    @IsTest
    static void mergeTakesTheChosenAddressAndAnniversary() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account survivor = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        survivor.BillingCity = 'Oakland';
        Account victim = HouseholdTestDataFactory.newHousehold('Garcia Household');
        victim.BillingCity = 'Berkeley';
        victim.Anniversary__c = Date.newInstance(2010, 6, 12);
        insert new List<Account>{ survivor, victim };

        Test.startTest();
        HouseholdMergeService.mergeHouseholds(
            survivor.Id,
            victim.Id,
            new HouseholdMergeService.MergeChoices(
                new Map<String, String>{
                    'BillingCity' => HouseholdMergeService.KEEP_VICTIM,
                    'Anniversary__c' => HouseholdMergeService.KEEP_VICTIM
                }
            )
        );
        Test.stopTest();

        Account saved = [
            SELECT BillingCity, Anniversary__c
            FROM Account
            WHERE Id = :survivor.Id
        ];
        Assert.areEqual('Berkeley', saved.BillingCity, 'The chosen address survives');
        Assert.areEqual(
            Date.newInstance(2010, 6, 12),
            saved.Anniversary__c,
            'The chosen anniversary survives'
        );
    }

    // ------------------------------------------------------------------ merge, junction mode

    @IsTest
    static void mergeInJunctionModeLeavesNobodyInTheHouseholdTwice() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
        Account survivor = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        Account victim = HouseholdTestDataFactory.newHousehold('Garcia Household');
        insert new List<Account>{ survivor, victim };
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
        insert new List<Contact>{ maria, wei };
        // Maria belongs to both households already, which is what junction mode allows.
        insert new List<Household_Member__c>{
            new Household_Member__c(Household__c = survivor.Id, Contact__c = maria.Id),
            new Household_Member__c(Household__c = victim.Id, Contact__c = maria.Id),
            new Household_Member__c(Household__c = victim.Id, Contact__c = wei.Id)
        };

        Test.startTest();
        HouseholdMergeService.mergeHouseholds(
            survivor.Id,
            victim.Id,
            new HouseholdMergeService.MergeChoices(null)
        );
        Test.stopTest();

        Integer mariaRows = [
            SELECT COUNT()
            FROM Household_Member__c
            WHERE Household__c = :survivor.Id AND Contact__c = :maria.Id AND End_Date__c = NULL
        ];
        Assert.areEqual(1, mariaRows, 'Maria is in the surviving household exactly once');
        Assert.areEqual(
            2,
            [SELECT Member_Count__c FROM Account WHERE Id = :survivor.Id].Member_Count__c,
            'The survivor counts two people, not three'
        );
    }

    // ------------------------------------------------------------------ refusals

    @IsTest
    static void anOrganizationCannotBeMergedIntoAHousehold() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        Account organization = new Account(Name = 'Bay Area Food Bank');
        insert new List<Account>{ household, organization };

        String message;
        Test.startTest();
        try {
            HouseholdMergeService.mergeHouseholds(
                household.Id,
                organization.Id,
                new HouseholdMergeService.MergeChoices(null)
            );
        } catch (HouseholdException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.areEqual(
            Label.Core_HouseholdMerge_ErrorNotHousehold,
            message,
            'The refusal names the problem in plain language'
        );
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Account WHERE Id = :organization.Id],
            'The organization is untouched'
        );
    }

    @IsTest
    static void aHouseholdCannotBeMergedIntoItself() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        insert household;

        String message;
        Test.startTest();
        try {
            HouseholdMergeService.mergeHouseholds(
                household.Id,
                household.Id,
                new HouseholdMergeService.MergeChoices(null)
            );
        } catch (HouseholdException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.areEqual(Label.Core_HouseholdMerge_ErrorSameRecord, message, 'The refusal is clear');
    }

    @IsTest
    static void aPersonWithoutEditAccessCannotMerge() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account survivor = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        Account victim = HouseholdTestDataFactory.newHousehold('Garcia Household');
        insert new List<Account>{ survivor, victim };
        User reader = readOnlyUser();

        String message;
        Test.startTest();
        System.runAs(reader) {
            try {
                HouseholdMergeService.mergeHouseholds(
                    survivor.Id,
                    victim.Id,
                    new HouseholdMergeService.MergeChoices(null)
                );
            } catch (Exception e) {
                message = e.getMessage();
            }
        }
        Test.stopTest();

        Assert.isNotNull(message, 'A person who cannot edit these households is refused');
        Assert.areEqual(
            2,
            [SELECT COUNT() FROM Account WHERE Id IN (:survivor.Id, :victim.Id)],
            'Both households are untouched'
        );
    }

    // ------------------------------------------------------------------ split

    @IsTest
    static void splitToANewHouseholdRenamesBoth() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        insert maria;
        Id householdId = householdOf(maria.Id);
        Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
        wei.AccountId = householdId;
        insert wei;
        HouseholdService.afterMembershipChange(new Set<Id>{ householdId });

        Test.startTest();
        Id created = HouseholdMergeService.split(householdId, new Set<Id>{ wei.Id }, null);
        Test.stopTest();

        Assert.isNotNull(created, 'A household was created for Wei');
        Assert.areEqual(created, householdOf(wei.Id), 'Wei belongs to the new household');
        Assert.areEqual(
            'The Lee Family',
            [SELECT Name FROM Account WHERE Id = :created].Name,
            'The new household is named from the person who moved'
        );
        Account source = [SELECT Name, Member_Count__c FROM Account WHERE Id = :householdId];
        Assert.areEqual(1, source.Member_Count__c, 'The household he left counts one');
        Assert.areEqual('The Garcia Family', source.Name, 'And it was renamed');
    }

    @IsTest
    static void splitToAnExistingHouseholdMovesThePersonThere() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        insert maria;
        Id householdId = householdOf(maria.Id);
        Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
        wei.AccountId = householdId;
        insert wei;
        Account destination = HouseholdTestDataFactory.newHousehold('The Lee Family');
        insert destination;

        Test.startTest();
        Id result = HouseholdMergeService.split(householdId, new Set<Id>{ wei.Id }, destination.Id);
        Test.stopTest();

        Assert.areEqual(destination.Id, result, 'The destination is answered');
        Assert.areEqual(destination.Id, householdOf(wei.Id), 'Wei moved to the household chosen');
        Assert.areEqual(
            1,
            [SELECT Member_Count__c FROM Account WHERE Id = :destination.Id].Member_Count__c,
            'The destination counts him'
        );
    }

    @IsTest
    static void theEmptiedHouseholdGoesAwayWhenTheOrgAsksForThat() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
        insert wei;
        Id householdId = householdOf(wei.Id);
        Account destination = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        insert destination;

        Test.startTest();
        HouseholdMergeService.split(householdId, new Set<Id>{ wei.Id }, destination.Id);
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Account WHERE Id = :householdId],
            'The household he was the last member of was tidied away'
        );
    }

    @IsTest
    static void theEmptiedHouseholdStaysWhenTheOrgSaysSo() {
        Nonprofit_Settings__c settings = HouseholdTestDataFactory.settings(
            HouseholdTestDataFactory.MODE_CONTACT
        );
        settings.Delete_Empty_Households__c = false;
        HouseholdTestDataFactory.save(settings);
        Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
        insert wei;
        Id householdId = householdOf(wei.Id);
        Account destination = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        insert destination;

        Test.startTest();
        HouseholdMergeService.split(householdId, new Set<Id>{ wei.Id }, destination.Id);
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Account WHERE Id = :householdId],
            'The empty household was kept, because the org asked for that'
        );
    }

    @IsTest
    static void splittingSomebodyWhoIsNotInTheHouseholdIsRefused() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
        insert new List<Contact>{ maria, wei };

        String message;
        Test.startTest();
        try {
            HouseholdMergeService.split(householdOf(maria.Id), new Set<Id>{ wei.Id }, null);
        } catch (HouseholdException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.areEqual(
            Label.Core_HouseholdMerge_ErrorSplitNotMembers,
            message,
            'The refusal says the people are not in this household'
        );
    }

    @IsTest
    static void splittingNobodyIsRefused() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        insert household;

        String message;
        Test.startTest();
        try {
            HouseholdMergeService.split(household.Id, new Set<Id>(), null);
        } catch (HouseholdException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.areEqual(
            Label.Core_HouseholdMerge_ErrorSplitNoMembers,
            message,
            'The refusal asks for at least one person'
        );
    }

    // ------------------------------------------------------------------ bulk

    @IsTest
    static void fiftyPeopleCanBeSplitOutInOneGo() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account household = HouseholdTestDataFactory.newHousehold('The Big Family');
        Account destination = HouseholdTestDataFactory.newHousehold('The Other Family');
        insert new List<Account>{ household, destination };
        List<Contact> people = HouseholdTestDataFactory.manyContacts(50, 'Member');
        for (Contact person : people) {
            person.AccountId = household.Id;
        }
        insert people;
        Set<Id> movers = new Map<Id, Contact>(people).keySet();

        Test.startTest();
        HouseholdMergeService.split(household.Id, movers, destination.Id);
        Test.stopTest();

        Assert.areEqual(
            50,
            [SELECT COUNT() FROM Contact WHERE AccountId = :destination.Id],
            'All fifty people moved in one pass'
        );
        Assert.areEqual(
            50,
            [SELECT Member_Count__c FROM Account WHERE Id = :destination.Id].Member_Count__c,
            'The destination counts all fifty'
        );
    }

    // ------------------------------------------------------------------ helpers

    private static Id householdOf(Id contactId) {
        return [SELECT AccountId FROM Contact WHERE Id = :contactId].AccountId;
    }

    private static Map<String, HouseholdMergeService.FieldChoice> byFieldName(
        HouseholdMergeService.MergePreview preview
    ) {
        Map<String, HouseholdMergeService.FieldChoice> result = new Map<String, HouseholdMergeService.FieldChoice>();
        for (HouseholdMergeService.FieldChoice choice : preview.fields) {
            result.put(choice.fieldName, choice);
        }
        return result;
    }

    /**
     * A user on the most restricted standard profile, so that a merge attempted without
     * edit access is refused by the same record access check the screen asks about.
     */
    private static User readOnlyUser() {
        Profile readOnly = [SELECT Id FROM Profile WHERE Name = 'Read Only' LIMIT 1];
        User reader = new User(
            ProfileId = readOnly.Id,
            LastName = 'Reader',
            Email = 'reader@openimpact.test.invalid',
            Username = 'reader' + DateTime.now().getTime() + '@openimpact.test.invalid',
            Alias = 'reader',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert reader;
        return reader;
    }
}

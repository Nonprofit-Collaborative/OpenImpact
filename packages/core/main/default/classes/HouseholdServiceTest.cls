/**
 * Membership in both modes: creation, counting, moving, and tidying up.
 * Canonical model R-H1, R-H2, R-H3, R-H11, R-H12.
 */
@IsTest
private class HouseholdServiceTest {
    @IsTest
    static void aNewPersonWithNoHouseholdGetsOne() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);

        Test.startTest();
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        insert maria;
        Test.stopTest();

        Contact saved = [
            SELECT AccountId, Account.Name, Account.Member_Count__c
            FROM Contact
            WHERE Id = :maria.Id
        ];
        Assert.isNotNull(saved.AccountId, 'Maria was given a household');
        Assert.areEqual(
            'The Garcia Family',
            saved.Account.Name,
            'The household is named from her surname'
        );
        Assert.areEqual(1, saved.Account.Member_Count__c, 'The household counts one member');
    }

    @IsTest
    static void twoHundredPeopleInOneSaveEachGetAHousehold() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        List<Contact> people = HouseholdTestDataFactory.manyContacts(200, 'Bulk');

        Test.startTest();
        insert people;
        Test.stopTest();

        Integer withHousehold = [
            SELECT COUNT()
            FROM Contact
            WHERE Id IN :people AND AccountId != NULL
        ];
        Assert.areEqual(200, withHousehold, 'Every person in the batch has a household');
    }

    @IsTest
    static void noHouseholdIsCreatedWhenTheSettingIsOff() {
        Nonprofit_Settings__c settings = HouseholdTestDataFactory.settings(
            HouseholdTestDataFactory.MODE_CONTACT
        );
        settings.Auto_Create_Households__c = false;
        HouseholdTestDataFactory.save(settings);

        Test.startTest();
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        insert maria;
        Test.stopTest();

        Contact saved = [SELECT AccountId FROM Contact WHERE Id = :maria.Id];
        Assert.isNull(saved.AccountId, 'Nothing was created for Maria');
    }

    @IsTest
    static void movingSomeoneRecountsBothHouseholdsAndDeletesTheEmptyOne() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
        insert new List<Contact>{ maria, wei };
        Id fromHousehold = [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId;
        Id toHousehold = [SELECT AccountId FROM Contact WHERE Id = :wei.Id].AccountId;

        Test.startTest();
        HouseholdService.moveContact(maria.Id, toHousehold);
        Test.stopTest();

        Assert.areEqual(
            2,
            [SELECT Member_Count__c FROM Account WHERE Id = :toHousehold].Member_Count__c,
            'The household Maria joined counts two'
        );
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Account WHERE Id = :fromHousehold],
            'The household Maria left was empty and was deleted'
        );
    }

    @IsTest
    static void anEmptyHouseholdIsKeptWhenTheSettingIsOff() {
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
        HouseholdService.moveContact(maria.Id, toHousehold);
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Account WHERE Id = :fromHousehold],
            'The empty household was kept because the org asked for that'
        );
        Assert.areEqual(
            0,
            [SELECT Member_Count__c FROM Account WHERE Id = :fromHousehold].Member_Count__c,
            'The empty household counts nobody'
        );
    }

    @IsTest
    static void junctionModeReadsMembersFromTheJunction() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
        Account household = HouseholdTestDataFactory.newHousehold('The Smith Family');
        insert household;
        Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
        insert john;
        insert new Household_Member__c(
            Household__c = household.Id,
            Contact__c = john.Id,
            Role__c = 'Head',
            Is_Primary__c = true,
            Start_Date__c = Date.today()
        );

        Test.startTest();
        Map<Id, List<HouseholdService.Person>> members = HouseholdService.getMembers(
            new Set<Id>{ household.Id }
        );
        Test.stopTest();

        Assert.areEqual(1, members.get(household.Id).size(), 'The junction row is the membership');
        Assert.areEqual(
            'Head',
            members.get(household.Id)[0].role,
            'The role comes from the junction row'
        );
        Assert.isTrue(
            members.get(household.Id)[0].isPrimary,
            'The primary flag comes from the junction row'
        );
    }

    @IsTest
    static void junctionModeEndsTheOldMembershipWhenSomeoneMoves() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
        List<Account> households = new List<Account>{
            HouseholdTestDataFactory.newHousehold('The Smith Family'),
            HouseholdTestDataFactory.newHousehold('The Garcia Family')
        };
        insert households;
        Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
        insert john;
        insert new Household_Member__c(
            Household__c = households[0].Id,
            Contact__c = john.Id,
            Start_Date__c = Date.today()
        );

        Test.startTest();
        HouseholdService.moveContact(john.Id, households[1].Id);
        Test.stopTest();

        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM Household_Member__c
                WHERE Contact__c = :john.Id AND End_Date__c != NULL
            ],
            'The old membership was ended rather than deleted'
        );
        Assert.areEqual(
            1,
            HouseholdService.getMembers(new Set<Id>{ households[1].Id })
                .get(households[1].Id)
                .size(),
            'John belongs to the household he moved to'
        );
        Assert.areEqual(
            0,
            HouseholdService.getMembers(new Set<Id>{ households[0].Id })
                .get(households[0].Id)
                .size(),
            'A membership ended today is over today, not tomorrow'
        );
        HouseholdService.recalculateMemberCounts(new Set<Id>{ households[0].Id, households[1].Id });
        Assert.areEqual(
            0,
            [SELECT Member_Count__c FROM Account WHERE Id = :households[0].Id].Member_Count__c,
            'The household John left counts nobody'
        );
        Assert.areEqual(
            1,
            [SELECT Member_Count__c FROM Account WHERE Id = :households[1].Id].Member_Count__c,
            'The household John joined counts him'
        );
        Assert.areEqual(
            households[1].Id,
            HouseholdService.getHouseholdIdsFor(new Set<Id>{ john.Id }).get(john.Id),
            'The household a caller is told about is the one he moved to'
        );
    }

    @IsTest
    static void movingSomeoneNowhereIsRefusedWithAnExplanation() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        String message = '';
        try {
            HouseholdService.moveContact(null, null);
        } catch (HouseholdException e) {
            message = e.getMessage();
        }
        Assert.areEqual(
            Label.Core_Households_ErrorMoveMissingInput,
            message,
            'Maria is told what to do'
        );
    }

    @IsTest
    static void movingSomeoneToAnOrganizationIsRefused() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        insert maria;
        Account organization = new Account(Name = 'Riverside Community Trust');
        insert organization;
        String message = '';

        Test.startTest();
        try {
            HouseholdService.moveContact(maria.Id, organization.Id);
        } catch (HouseholdException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.areEqual(
            Label.Core_Households_ErrorNotAHousehold,
            message,
            'An organization is not a household'
        );
    }

    @IsTest
    static void anOrgWithoutPeopleStoredAsAccountsSkipsThatBranch() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
        HouseholdService.personAccountOverride = false;

        Test.startTest();
        insert new Account(Name = 'Riverside Community Trust');
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Household_Member__c], 'No membership was created');
    }

    @IsTest
    static void aPersonStoredAsAnAccountGetsAHouseholdAndAMembership() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
        HouseholdService.personAccountOverride = true;
        Account person = new Account(Name = 'Maria Garcia');
        insert person;

        Test.startTest();
        HouseholdService.createHouseholdsForPersonAccounts(new List<SObject>{ person });
        Test.stopTest();

        List<Household_Member__c> memberships = [
            SELECT Household__c, Account__c, Role__c, Is_Primary__c
            FROM Household_Member__c
            WHERE Account__c = :person.Id
        ];
        Assert.areEqual(1, memberships.size(), 'The person was joined to a household');
        Assert.areEqual('Head', memberships[0].Role__c, 'They are the head of their own household');
        Assert.isTrue(memberships[0].Is_Primary__c, 'They are the primary member');
        Assert.isNotNull(memberships[0].Household__c, 'A household was created for them');
    }

    @IsTest
    static void memberCountsAreRecalculatedForEveryHouseholdGiven() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account household = HouseholdTestDataFactory.newHousehold('The Smith Family');
        insert household;
        insert new List<Contact>{
            new Contact(
                Salutation = 'Mr.',
                FirstName = 'John',
                LastName = 'Smith',
                AccountId = household.Id
            ),
            new Contact(
                Salutation = 'Mrs.',
                FirstName = 'Jane',
                LastName = 'Smith',
                AccountId = household.Id
            )
        };
        update new Account(Id = household.Id, Member_Count__c = 99);

        Test.startTest();
        HouseholdService.recalculateMemberCounts(new Set<Id>{ household.Id });
        Test.stopTest();

        Assert.areEqual(
            2,
            [SELECT Member_Count__c FROM Account WHERE Id = :household.Id].Member_Count__c,
            'The count was put right'
        );
    }

    @IsTest
    static void theHouseholdOfAPersonIsAnsweredInContactMode() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        insert maria;
        Id household = [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId;
        Contact atWork = HouseholdTestDataFactory.newContact('Mr.', 'Tom', 'Rivera');
        Account organization = new Account(Name = 'Riverside Community Trust');
        insert organization;
        atWork.AccountId = organization.Id;
        insert atWork;

        Test.startTest();
        Map<Id, Id> households = HouseholdService.getHouseholdIdsFor(
            new Set<Id>{ maria.Id, atWork.Id }
        );
        Test.stopTest();

        Assert.areEqual(household, households.get(maria.Id), 'Maria belongs to her household');
        Assert.areEqual(
            null,
            households.get(atWork.Id),
            'A person attached to an organization has no household'
        );
    }

    @IsTest
    static void theHouseholdOfAPersonIsAnsweredInJunctionMode() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
        List<Account> households = new List<Account>{
            HouseholdTestDataFactory.newHousehold('The Smith Family'),
            HouseholdTestDataFactory.newHousehold('The Garcia Family')
        };
        insert households;
        Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        insert new List<Contact>{ john, maria };
        insert new List<Household_Member__c>{
            new Household_Member__c(
                Household__c = households[0].Id,
                Contact__c = john.Id,
                Is_Primary__c = true,
                Start_Date__c = Date.today()
            ),
            new Household_Member__c(
                Household__c = households[1].Id,
                Contact__c = john.Id,
                Start_Date__c = Date.today()
            ),
            new Household_Member__c(
                Household__c = households[1].Id,
                Contact__c = maria.Id,
                Start_Date__c = Date.today()
            )
        };

        Test.startTest();
        Map<Id, Id> answered = HouseholdService.getHouseholdIdsFor(
            new Set<Id>{ john.Id, maria.Id }
        );
        Test.stopTest();

        Assert.areEqual(
            households[0].Id,
            answered.get(john.Id),
            'John belongs to two households, so the one he is primary in is the answer'
        );
        Assert.areEqual(
            households[1].Id,
            answered.get(maria.Id),
            'Maria belongs to one household, so that is the answer'
        );
    }

    @IsTest
    static void askingTwiceAsksTheDatabaseOnce() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        insert maria;

        Test.startTest();
        HouseholdService.getHouseholdIdsFor(new Set<Id>{ maria.Id });
        Integer afterFirst = Limits.getQueries();
        HouseholdService.getHouseholdIdsFor(new Set<Id>{ maria.Id });
        Integer afterSecond = Limits.getQueries();
        Test.stopTest();

        Assert.areEqual(afterFirst, afterSecond, 'The second question was answered from memory');
    }

    @IsTest
    static void theMembersOfAHouseholdAreAnsweredInContactMode() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account household = HouseholdTestDataFactory.newHousehold('The Smith Family');
        insert household;
        Contact john = new Contact(
            Salutation = 'Mr.',
            FirstName = 'John',
            LastName = 'Smith',
            AccountId = household.Id
        );
        insert john;

        Test.startTest();
        Map<Id, Set<Id>> members = HouseholdService.getMemberPersonIds(new Set<Id>{ household.Id });
        Test.stopTest();

        Assert.areEqual(1, members.get(household.Id).size(), 'One person belongs to the household');
        Assert.isTrue(members.get(household.Id).contains(john.Id), 'That person is John');
    }

    @IsTest
    static void theMembersOfAHouseholdAreAnsweredInJunctionMode() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
        Account household = HouseholdTestDataFactory.newHousehold('The Smith Family');
        insert household;
        Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
        insert john;
        insert new Household_Member__c(
            Household__c = household.Id,
            Contact__c = john.Id,
            Start_Date__c = Date.today()
        );

        Test.startTest();
        Map<Id, Set<Id>> members = HouseholdService.getMemberPersonIds(new Set<Id>{ household.Id });
        Test.stopTest();

        Assert.isTrue(
            members.get(household.Id).contains(john.Id),
            'The junction row is the member'
        );
    }

    @IsTest
    static void askingAboutNobodyAnswersNothing() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Assert.areEqual(
            0,
            HouseholdService.getHouseholdIdsFor(new Set<Id>()).size(),
            'No people asked about, nothing answered'
        );
        Assert.areEqual(
            0,
            HouseholdService.getMemberPersonIds(null).size(),
            'No households asked about, nothing answered'
        );
    }

    @IsTest
    static void aPersonStoredAsAnAccountIsMovedThroughTheJunction() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
        HouseholdService.personAccountOverride = true;
        PersonRecordSelector.personRecordOverride = true;
        Account person = new Account(Name = 'Maria Garcia');
        insert person;
        List<Account> households = new List<Account>{
            HouseholdTestDataFactory.newHousehold('The Garcia Family'),
            HouseholdTestDataFactory.newHousehold('The Lee Family')
        };
        insert households;
        insert new Household_Member__c(
            Household__c = households[0].Id,
            Account__c = person.Id,
            Role__c = 'Head',
            Is_Primary__c = true,
            Start_Date__c = Date.today()
        );

        Test.startTest();
        HouseholdService.moveContact(person.Id, households[1].Id);
        Test.stopTest();

        List<Household_Member__c> current = [
            SELECT Household__c, Account__c, Contact__c, Role__c, Is_Primary__c
            FROM Household_Member__c
            WHERE Account__c = :person.Id AND End_Date__c = NULL
        ];
        Assert.areEqual(1, current.size(), 'Maria has one current membership');
        Assert.areEqual(
            households[1].Id,
            current[0].Household__c,
            'It is the household she moved to'
        );
        Assert.areEqual(null, current[0].Contact__c, 'She is not recorded as a contact');
        Assert.areEqual('Head', current[0].Role__c, 'Her role came with her');
        Assert.isTrue(current[0].Is_Primary__c, 'So did the primary flag');
    }

    @IsTest
    static void aPersonStoredAsAnAccountCannotBeMovedInTheSimpleMode() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        HouseholdService.personAccountOverride = true;
        PersonRecordSelector.personRecordOverride = true;
        Account person = new Account(Name = 'Maria Garcia');
        insert person;
        Account household = HouseholdTestDataFactory.newHousehold('The Lee Family');
        insert household;
        String message = '';

        Test.startTest();
        try {
            HouseholdService.moveContact(person.Id, household.Id);
        } catch (HouseholdException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.areEqual(
            Label.Core_Households_ErrorMoveNeedsJunction,
            message,
            'Maria is told which setting has to change first'
        );
    }

    @IsTest
    static void anOrganizationNeverGetsAMemberCount() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account organization = new Account(Name = 'Riverside Community Trust');
        insert organization;
        insert new Contact(
            Salutation = 'Mr.',
            FirstName = 'Tom',
            LastName = 'Rivera',
            AccountId = organization.Id
        );

        Test.startTest();
        HouseholdService.recalculateMemberCounts(new Set<Id>{ organization.Id });
        Test.stopTest();

        Assert.areEqual(
            null,
            [SELECT Member_Count__c FROM Account WHERE Id = :organization.Id].Member_Count__c,
            'A member count is never stamped on an organization'
        );
    }

    @IsTest
    static void aStandardUserWithNoPackagedAccessCanStillSaveAPerson() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        User staff = HouseholdTestDataFactory.standardUser('house');

        Test.startTest();
        System.runAs(staff) {
            insert HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        }
        Test.stopTest();

        Contact saved = [
            SELECT AccountId, Account.Name, Account.Member_Count__c
            FROM Contact
            WHERE LastName = 'Garcia'
            LIMIT 1
        ];
        Assert.isNotNull(
            saved.AccountId,
            'The household was created for a user with no packaged access'
        );
        Assert.areEqual('The Garcia Family', saved.Account.Name, 'And it was named');
        Assert.areEqual(1, saved.Account.Member_Count__c, 'And counted');
    }
    @IsTest
    static void upkeepAfterAMembershipChangeIsOnePlaceAnyCallerCanUse() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account household = HouseholdTestDataFactory.newHousehold('Placeholder');
        insert household;
        // Saved without the trigger noticing, the way another package would leave it.
        Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
        john.AccountId = household.Id;
        insert john;
        update new Account(Id = household.Id, Name = 'Placeholder', Member_Count__c = 0);

        Test.startTest();
        HouseholdService.afterMembershipChange(new Set<Id>{ household.Id });
        Test.stopTest();

        Account saved = [SELECT Name, Member_Count__c FROM Account WHERE Id = :household.Id];
        Assert.areEqual(1, saved.Member_Count__c, 'The household counts John again');
        Assert.areEqual('The Smith Family', saved.Name, 'And is named from him');
    }
}

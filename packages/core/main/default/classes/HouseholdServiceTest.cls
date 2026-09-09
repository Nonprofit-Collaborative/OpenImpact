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

    /**
     * The defect ADR-NEXT closes, asserted from the configuration an administrator arrives
     * at by following the product's own recommendation in a Nonprofit Cloud org: junction
     * membership, and nothing else changed.
     */
    @IsTest
    static void aNewPersonInJunctionModeGetsAHouseholdAndAMembershipRow() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);

        Test.startTest();
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        insert maria;
        Test.stopTest();

        List<Household_Member__c> memberships = [
            SELECT
                Household__c,
                Contact__c,
                Account__c,
                Role__c,
                Is_Primary__c,
                Household__r.Name,
                Household__r.Member_Count__c,
                Household__r.RecordTypeId
            FROM Household_Member__c
            WHERE Contact__c = :maria.Id
        ];
        Assert.areEqual(1, memberships.size(), 'Maria was joined to a household (R-H2)');
        Assert.areEqual(
            HouseholdService.householdRecordTypeId(),
            memberships[0].Household__r.RecordTypeId,
            'The household is a household'
        );
        Assert.areEqual(
            'The Garcia Family',
            memberships[0].Household__r.Name,
            'And it is named from her surname, the same way contact mode names it'
        );
        Assert.areEqual(1, memberships[0].Household__r.Member_Count__c, 'And counts her');
        Assert.areEqual('Head', memberships[0].Role__c, 'She heads her own household');
        Assert.isTrue(memberships[0].Is_Primary__c, 'And is its primary member');
        Assert.isNull(
            memberships[0].Account__c,
            'She is recorded as a contact, because that is the object she is stored on'
        );
        Assert.areEqual(
            memberships[0].Household__c,
            HouseholdService.getHouseholdIdsFor(new Set<Id>{ maria.Id }).get(maria.Id),
            'And the service answers with that household when asked whose she is'
        );
    }

    @IsTest
    static void noHouseholdIsCreatedInJunctionModeWhenTheSettingIsOff() {
        HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();

        Test.startTest();
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        insert maria;
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Household_Member__c],
            'The org said no, so nobody was joined to anything'
        );
        Assert.areEqual(
            0,
            [
                SELECT COUNT()
                FROM Account
                WHERE RecordTypeId = :HouseholdService.householdRecordTypeId()
            ],
            'And no household was made either'
        );
    }

    @IsTest
    static void twoHundredPeopleInOneSaveEachGetAHouseholdInJunctionMode() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
        List<Contact> people = HouseholdTestDataFactory.manyContacts(200, 'Bulk');

        Test.startTest();
        insert people;
        Test.stopTest();

        Assert.areEqual(
            200,
            [SELECT COUNT() FROM Household_Member__c WHERE Contact__c IN :people],
            'Every person in the batch is joined to a household of their own (R-H2)'
        );
        Assert.areEqual(
            200,
            [
                SELECT COUNT()
                FROM Account
                WHERE RecordTypeId = :HouseholdService.householdRecordTypeId()
            ],
            'And exactly one household was made for each of them, not two'
        );
    }

    /**
     * Somebody saved straight into a household they were given is not given a second one.
     * This is how a person arrives from the merge and split screens and from an import that
     * names their household, and it is the junction mode form of the contact mode test that
     * a contact arriving with an account keeps it.
     */
    @IsTest
    static void aPersonSavedIntoAHouseholdInJunctionModeIsNotGivenASecondOne() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
        Account household = HouseholdTestDataFactory.newHousehold('The Smith Family');
        insert household;

        Test.startTest();
        Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
        john.AccountId = household.Id;
        insert john;
        Test.stopTest();

        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM Account
                WHERE RecordTypeId = :HouseholdService.householdRecordTypeId()
            ],
            'The household he was saved into is the only one there is'
        );
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
        HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
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
        Nonprofit_Settings__c settings = HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
        // The household John leaves has to still be there afterwards for this test to be
        // able to look at what happened to his membership of it. Household Member cascades
        // from its household, so tidying the emptied household away would take the ended
        // membership row with it and there would be nothing left to assert on.
        settings.Delete_Empty_Households__c = false;
        HouseholdTestDataFactory.save(settings);
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
        HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
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
        HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
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
        HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
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
    @IsTest
    static void aScreenNeverShowsAFieldTheUserCannotRead() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        User staff = HouseholdTestDataFactory.standardUser('fls');
        Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
        john.Deceased__c = true;
        // Saved by the same user who will read it back, so that what this test measures is
        // field level access and nothing else. Whether a user can see a person somebody
        // else entered is the org's sharing model, which differs from org to org, and a
        // test that depends on it is testing the org rather than the package.
        System.runAs(staff) {
            insert john;
        }
        Id householdId = [SELECT AccountId FROM Contact WHERE Id = :john.Id].AccountId;
        Assert.isTrue(
            HouseholdService.getMembers(new Set<Id>{ householdId }).get(householdId)[0].isDeceased,
            'Upkeep sees the whole record, which is how the greetings stay right'
        );

        List<HouseholdController.MemberView> shown;
        Test.startTest();
        System.runAs(staff) {
            shown = HouseholdController.getMembers(householdId);
        }
        Test.stopTest();

        Assert.areEqual(1, shown.size(), 'The panel still lists John');
        Assert.areEqual('John Smith', shown[0].name, 'By the name this user can read');
        Assert.isFalse(
            shown[0].isDeceased,
            'A user with no access to the deceased field is not told that he died'
        );
    }

    @IsTest
    static void aBulkMoveMovesEverybodyAtOnceAndAnswersWithEveryHouseholdItTouched() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
        Contact amara = HouseholdTestDataFactory.newContact('Ms.', 'Amara', 'Okonkwo');
        insert new List<Contact>{ maria, wei, amara };
        Id mariaHousehold = [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId;
        Id weiHousehold = [SELECT AccountId FROM Contact WHERE Id = :wei.Id].AccountId;
        Id target = [SELECT AccountId FROM Contact WHERE Id = :amara.Id].AccountId;

        Test.startTest();
        Set<Id> affected = HouseholdService.moveMembers(new Set<Id>{ maria.Id, wei.Id }, target);
        Test.stopTest();

        Assert.areEqual(
            new Set<Id>{ mariaHousehold, weiHousehold, target },
            affected,
            'Both households somebody left and the one they joined are answered'
        );
        Assert.areEqual(
            3,
            [SELECT COUNT() FROM Contact WHERE AccountId = :target],
            'Both people moved in one pass'
        );
    }

    @IsTest
    static void aMoveThatNamesSomebodyWhoIsGoneIsRefused() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
        insert new List<Contact>{ maria, wei };
        Id target = [SELECT AccountId FROM Contact WHERE Id = :wei.Id].AccountId;
        Id goneId = maria.Id;
        delete maria;
        String message = '';

        Test.startTest();
        try {
            HouseholdService.moveMembers(new Set<Id>{ goneId }, target);
        } catch (HouseholdException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.areEqual(
            Label.Core_Households_ErrorMoveNotFound,
            message,
            'A stale id is refused rather than quietly dropped from the move'
        );
    }

    @IsTest
    static void peopleStoredAsAccountsMoveInBulkThroughTheJunction() {
        HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
        HouseholdService.personAccountOverride = true;
        PersonRecordSelector.personRecordOverride = true;
        List<Account> people = new List<Account>{
            new Account(Name = 'Maria Garcia'),
            new Account(Name = 'Wei Lee')
        };
        insert people;
        List<Account> households = new List<Account>{
            HouseholdTestDataFactory.newHousehold('The Garcia Family'),
            HouseholdTestDataFactory.newHousehold('The Lee Family')
        };
        insert households;
        insert new List<Household_Member__c>{
            new Household_Member__c(
                Household__c = households[0].Id,
                Account__c = people[0].Id,
                Role__c = 'Head',
                Is_Primary__c = true,
                Start_Date__c = Date.today()
            ),
            new Household_Member__c(
                Household__c = households[0].Id,
                Account__c = people[1].Id,
                Role__c = 'Spouse or Partner',
                Start_Date__c = Date.today()
            )
        };

        Test.startTest();
        Set<Id> affected = HouseholdService.moveMembers(
            new Set<Id>{ people[0].Id, people[1].Id },
            households[1].Id
        );
        Test.stopTest();

        Assert.areEqual(
            new Set<Id>{ households[0].Id, households[1].Id },
            affected,
            'Both households are answered'
        );
        List<Household_Member__c> current = [
            SELECT Account__c, Contact__c, Role__c, Is_Primary__c
            FROM Household_Member__c
            WHERE Household__c = :households[1].Id AND End_Date__c = NULL
            ORDER BY Role__c
        ];
        Assert.areEqual(2, current.size(), 'Both people are current members of the new household');
        Assert.areEqual('Head', current[0].Role__c, 'Maria is still the Head');
        Assert.isTrue(current[0].Is_Primary__c, 'And still the primary member');
        Assert.areEqual(null, current[0].Contact__c, 'Neither is recorded as a contact');
    }

    @IsTest
    static void twoPrimaryPeopleMovingIntoOneHouseholdLeaveItOnePrimary() {
        HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
        List<Contact> people = new List<Contact>{
            HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia'),
            HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee')
        };
        insert people;
        List<Account> households = new List<Account>{
            HouseholdTestDataFactory.newHousehold('The Garcia Family'),
            HouseholdTestDataFactory.newHousehold('The Lee Family'),
            HouseholdTestDataFactory.newHousehold('The Okonkwo Family')
        };
        insert households;
        insert new List<Household_Member__c>{
            new Household_Member__c(
                Household__c = households[0].Id,
                Contact__c = people[0].Id,
                Role__c = 'Head',
                Is_Primary__c = true,
                Start_Date__c = Date.today()
            ),
            new Household_Member__c(
                Household__c = households[1].Id,
                Contact__c = people[1].Id,
                Role__c = 'Head',
                Is_Primary__c = true,
                Start_Date__c = Date.today()
            )
        };

        Test.startTest();
        HouseholdService.moveMembers(new Set<Id>{ people[0].Id, people[1].Id }, households[2].Id);
        Test.stopTest();

        Assert.areEqual(
            0,
            [
                SELECT COUNT()
                FROM Household_Member__c
                WHERE
                    Household__c = :households[2].Id
                    AND End_Date__c = NULL
                    AND Is_Primary__c = TRUE
            ],
            'Two people who were each primary do not both arrive primary (R-M3)'
        );
        Assert.areEqual(
            2,
            [
                SELECT COUNT()
                FROM Household_Member__c
                WHERE Household__c = :households[2].Id AND End_Date__c = NULL
            ],
            'Both are still members, and both kept their role'
        );
    }

    @IsTest
    static void anArrivingPrimaryDoesNotDisplaceTheOneAlreadyThere() {
        HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
        List<Contact> people = new List<Contact>{
            HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia'),
            HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee')
        };
        insert people;
        List<Account> households = new List<Account>{
            HouseholdTestDataFactory.newHousehold('The Garcia Family'),
            HouseholdTestDataFactory.newHousehold('The Lee Family')
        };
        insert households;
        insert new List<Household_Member__c>{
            new Household_Member__c(
                Household__c = households[0].Id,
                Contact__c = people[0].Id,
                Role__c = 'Head',
                Is_Primary__c = true,
                Start_Date__c = Date.today()
            ),
            new Household_Member__c(
                Household__c = households[1].Id,
                Contact__c = people[1].Id,
                Role__c = 'Head',
                Is_Primary__c = true,
                Start_Date__c = Date.today()
            )
        };

        Test.startTest();
        HouseholdService.moveMembers(new Set<Id>{ people[0].Id }, households[1].Id);
        Test.stopTest();

        List<Household_Member__c> primaries = [
            SELECT Contact__c
            FROM Household_Member__c
            WHERE Household__c = :households[1].Id AND End_Date__c = NULL AND Is_Primary__c = TRUE
        ];
        Assert.areEqual(1, primaries.size(), 'The household still has exactly one primary (R-M3)');
        Assert.areEqual(
            people[1].Id,
            primaries[0].Contact__c,
            'It is the person who was already there'
        );
    }

    @IsTest
    static void thePrimaryContactIsClearedWhenThatPersonLeavesInContactMode() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account household = HouseholdTestDataFactory.newHousehold('The Smith Family');
        Account target = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        insert new List<Account>{ household, target };
        Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
        Contact jane = HouseholdTestDataFactory.newContact('Mrs.', 'Jane', 'Smith');
        john.AccountId = household.Id;
        jane.AccountId = household.Id;
        insert new List<Contact>{ john, jane };
        update new Account(Id = household.Id, Primary_Contact__c = john.Id);

        Test.startTest();
        HouseholdService.moveContact(john.Id, target.Id);
        Test.stopTest();

        Assert.areEqual(
            null,
            [SELECT Primary_Contact__c FROM Account WHERE Id = :household.Id].Primary_Contact__c,
            'The reference to the person who left was cleared (R-H10)'
        );
    }

    @IsTest
    static void thePrimaryContactIsClearedWhenThatPersonLeavesInJunctionMode() {
        HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
        Account household = HouseholdTestDataFactory.newHousehold('The Smith Family');
        Account target = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        insert new List<Account>{ household, target };
        Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
        Contact jane = HouseholdTestDataFactory.newContact('Mrs.', 'Jane', 'Smith');
        insert new List<Contact>{ john, jane };
        insert new List<Household_Member__c>{
            new Household_Member__c(
                Household__c = household.Id,
                Contact__c = john.Id,
                Role__c = 'Head',
                Is_Primary__c = true,
                Start_Date__c = Date.today()
            ),
            new Household_Member__c(
                Household__c = household.Id,
                Contact__c = jane.Id,
                Role__c = 'Spouse or Partner',
                Start_Date__c = Date.today()
            )
        };
        update new Account(Id = household.Id, Primary_Contact__c = john.Id);

        Test.startTest();
        HouseholdService.moveContact(john.Id, target.Id);
        Test.stopTest();

        Assert.areEqual(
            null,
            [SELECT Primary_Contact__c FROM Account WHERE Id = :household.Id].Primary_Contact__c,
            'The reference to the person who left was cleared (R-H10)'
        );
    }

    @IsTest
    static void nobodyIsPromotedIntoThePrimaryContactTheLeaverGaveUp() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account household = HouseholdTestDataFactory.newHousehold('The Smith Family');
        Account target = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        insert new List<Account>{ household, target };
        Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
        Contact jane = HouseholdTestDataFactory.newContact('Mrs.', 'Jane', 'Smith');
        john.AccountId = household.Id;
        jane.AccountId = household.Id;
        insert new List<Contact>{ john, jane };
        update new Account(Id = household.Id, Primary_Contact__c = john.Id);

        Test.startTest();
        HouseholdService.moveContact(john.Id, target.Id);
        Test.stopTest();

        Account saved = [
            SELECT Primary_Contact__c, Member_Count__c
            FROM Account
            WHERE Id = :household.Id
        ];
        Assert.areEqual(1, saved.Member_Count__c, 'Jane is still a member');
        Assert.areEqual(
            null,
            saved.Primary_Contact__c,
            'Jane was not silently promoted: the next member is proposed, not assigned (R-H10)'
        );
    }

    @IsTest
    static void aPrimaryContactWhoStaysIsLeftAlone() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account household = HouseholdTestDataFactory.newHousehold('The Smith Family');
        Account target = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        insert new List<Account>{ household, target };
        Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
        Contact jane = HouseholdTestDataFactory.newContact('Mrs.', 'Jane', 'Smith');
        john.AccountId = household.Id;
        jane.AccountId = household.Id;
        insert new List<Contact>{ john, jane };
        update new Account(Id = household.Id, Primary_Contact__c = jane.Id);

        Test.startTest();
        HouseholdService.moveContact(john.Id, target.Id);
        Test.stopTest();

        Assert.areEqual(
            jane.Id,
            [SELECT Primary_Contact__c FROM Account WHERE Id = :household.Id].Primary_Contact__c,
            'The primary contact who is still a member is untouched'
        );
    }

    @IsTest
    static void anOrganizationKeepsItsPrimaryContactWhenSomebodyLeaves() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account organization = new Account(Name = 'Riverside Shelter');
        Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        insert new List<Account>{ organization, household };
        Contact staff = HouseholdTestDataFactory.newContact('Ms.', 'Ada', 'Nkosi');
        staff.AccountId = organization.Id;
        insert staff;
        update new Account(Id = organization.Id, Primary_Contact__c = staff.Id);

        Test.startTest();
        HouseholdService.moveContact(staff.Id, household.Id);
        Test.stopTest();

        Assert.areEqual(
            staff.Id,
            [SELECT Primary_Contact__c FROM Account WHERE Id = :organization.Id].Primary_Contact__c,
            'An organization shares the field but not the rule (R-O3), so it is left alone'
        );
    }

    @IsTest
    static void peopleAreJoinedToSeveralHouseholdsAtOnceInJunctionMode() {
        HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
        List<Account> households = new List<Account>{
            HouseholdTestDataFactory.newHousehold('The Smith Family'),
            HouseholdTestDataFactory.newHousehold('The Garcia Family')
        };
        insert households;
        Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
        Contact jane = HouseholdTestDataFactory.newContact('Mrs.', 'Jane', 'Smith');
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        insert new List<Contact>{ john, jane, maria };

        Test.startTest();
        Set<Id> affected = HouseholdService.addMembers(
            new Map<Id, Set<Id>>{
                households[0].Id => new Set<Id>{ john.Id, jane.Id },
                households[1].Id => new Set<Id>{ maria.Id }
            }
        );
        Test.stopTest();

        Assert.areEqual(2, affected.size(), 'Both households were touched');
        Assert.areEqual(
            3,
            [SELECT COUNT() FROM Household_Member__c WHERE End_Date__c = NULL],
            'One membership row per person'
        );
        Assert.areEqual(
            2,
            HouseholdService.getMembers(new Set<Id>{ households[0].Id })
                .get(households[0].Id)
                .size(),
            'The Smiths are members of their household'
        );
        Assert.areEqual(
            households[1].Id,
            HouseholdService.getHouseholdIdsFor(new Set<Id>{ maria.Id }).get(maria.Id),
            'Maria belongs to the household she was joined to'
        );
    }

    @IsTest
    static void joiningSomebodyTwiceLeavesThemOneMembership() {
        HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
        Account household = HouseholdTestDataFactory.newHousehold('The Smith Family');
        insert household;
        Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
        insert john;
        Map<Id, Set<Id>> joining = new Map<Id, Set<Id>>{ household.Id => new Set<Id>{ john.Id } };

        Test.startTest();
        HouseholdService.addMembers(joining);
        HouseholdService.addMembers(joining);
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Household_Member__c WHERE End_Date__c = NULL],
            'Somebody who is already a current member is left alone'
        );
    }

    @IsTest
    static void joiningInContactModeIsTheirOwnHouseholdField() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account first = HouseholdTestDataFactory.newHousehold('The Smith Family');
        Account second = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        insert new List<Account>{ first, second };
        Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
        john.AccountId = first.Id;
        insert john;

        Test.startTest();
        Set<Id> affected = HouseholdService.addMembers(
            new Map<Id, Set<Id>>{ second.Id => new Set<Id>{ john.Id } }
        );
        Test.stopTest();

        Assert.areEqual(
            second.Id,
            [SELECT AccountId FROM Contact WHERE Id = :john.Id].AccountId,
            'The contact now points at the household he joined'
        );
        Assert.isTrue(
            affected.contains(first.Id),
            'The household he left is in the answer, so the caller can settle it up'
        );
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Household_Member__c],
            'Contact membership writes no membership rows (R-M1)'
        );
    }

    @IsTest
    static void joiningAnOrganizationIsRefused() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account organization = new Account(Name = 'Riverside Trust');
        insert organization;
        Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
        insert john;

        String message = '';
        Test.startTest();
        try {
            HouseholdService.addMembers(
                new Map<Id, Set<Id>>{ organization.Id => new Set<Id>{ john.Id } }
            );
        } catch (HouseholdException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.areEqual(
            Label.Core_Households_ErrorNotAHousehold,
            message,
            'An organization is never a household to join'
        );
    }
}

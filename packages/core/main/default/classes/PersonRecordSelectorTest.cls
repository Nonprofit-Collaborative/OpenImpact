/**
 * Reading a person that the org stores as an account. These tests run on every org shape:
 * where the org does not store people that way, the selector returns nothing rather than
 * failing, which is the behavior Core depends on.
 */
@IsTest
private class PersonRecordSelectorTest {
    @IsTest
    static void nothingIsReadWhenTheOrgDoesNotStorePeopleAsAccounts() {
        HouseholdService.personAccountOverride = false;
        Account organization = new Account(Name = 'Riverside Community Trust');
        insert organization;

        Test.startTest();
        List<HouseholdService.Person> people = PersonRecordSelector.getPersons(
            new Set<Id>{ organization.Id }
        );
        Test.stopTest();

        Assert.areEqual(0, people.size(), 'The person branch does not run on this org shape');
    }

    @IsTest
    static void anEmptyRequestReadsNothing() {
        HouseholdService.personAccountOverride = true;
        Assert.areEqual(
            0,
            PersonRecordSelector.getPersons(new Set<Id>()).size(),
            'No ids means no query and no rows'
        );
    }

    /**
     * The upkeep read is what household naming and the member count are built from, and it
     * has to work for a user who holds no packaged permission set at all (ADR-0021).
     *
     * The org shape is declared through personAccountOverride, because a Platform only test
     * org has no person accounts to make. Nothing else is substituted: no declared person
     * stands in for the record, so the query really runs and the flag really comes off the
     * account.
     */
    @IsTest
    static void theUpkeepReadSeesAFieldTheReadingUserCannotRead() {
        HouseholdService.personAccountOverride = true;
        User staff = HouseholdTestDataFactory.standardUser('upk');
        Account person = new Account(Name = 'Maria Garcia');
        // Saved by the same user who reads it back, so that what this measures is field
        // level access and not the org's sharing model.
        System.runAs(staff) {
            insert person;
        }
        update new Account(Id = person.Id, Deceased__c = true);
        List<HouseholdService.Person> people;

        Test.startTest();
        System.runAs(staff) {
            people = PersonRecordSelector.getPersons(new Set<Id>{ person.Id });
        }
        Test.stopTest();

        Assert.areEqual(1, people.size(), 'The read works for a user with no packaged access');
        Assert.isTrue(people[0].isDeceased, 'And it sees the flag the greetings depend on');
    }

    /**
     * The display read, on the same record and the same user: the field the user cannot
     * read is stripped rather than throwing, so the panel still lists the person.
     *
     * Substitution as above: the org shape only.
     */
    @IsTest
    static void theDisplayReadStripsAFieldTheReadingUserCannotRead() {
        HouseholdService.personAccountOverride = true;
        User staff = HouseholdTestDataFactory.standardUser('disp');
        Account person = new Account(Name = 'Maria Garcia');
        System.runAs(staff) {
            insert person;
        }
        update new Account(Id = person.Id, Deceased__c = true);
        List<HouseholdService.Person> people;

        Test.startTest();
        System.runAs(staff) {
            people = PersonRecordSelector.getPersonsForDisplay(new Set<Id>{ person.Id });
        }
        Test.stopTest();

        Assert.areEqual(1, people.size(), 'The person is still shown');
        Assert.isFalse(
            people[0].isDeceased,
            'A user with no access to the deceased field is not told that she died'
        );
    }

    @IsTest
    static void aDisplayReadOfNobodyReadsNothing() {
        HouseholdService.personAccountOverride = true;
        Assert.areEqual(
            0,
            PersonRecordSelector.getPersonsForDisplay(new Set<Id>()).size(),
            'No ids means no query and no rows'
        );
    }

    @IsTest
    static void aRecordIsTurnedIntoAPersonWithoutNamingFieldsThatMayNotExist() {
        Account record = new Account(Name = 'Maria Garcia');
        insert record;

        Test.startTest();
        HouseholdService.Person person = PersonRecordSelector.toPerson(
            [SELECT Id, Name, Preferred_Name__c, Deceased__c FROM Account WHERE Id = :record.Id]
        );
        Test.stopTest();

        Assert.areEqual(record.Id, person.id, 'The person is the record');
        Assert.areEqual(
            HouseholdService.SOURCE_ACCOUNT,
            person.sourceObject,
            'The person came from an account'
        );
        Assert.isFalse(person.isDeceased, 'A missing or empty flag reads as false');
    }

    @IsTest
    static void anOrganizationIsNeverTakenForAPerson() {
        Account organization = new Account(Name = 'Riverside Community Trust');
        insert organization;

        Test.startTest();
        Boolean isPerson = PersonRecordSelector.isPersonRecord(organization);
        List<SObject> people = PersonRecordSelector.filterPeople(new List<SObject>{ organization });
        Test.stopTest();

        Assert.isFalse(isPerson, 'An organization is not a person');
        Assert.areEqual(0, people.size(), 'Nothing is treated as a person');
    }

    @IsTest
    static void nothingAtAllIsHandled() {
        Assert.isFalse(PersonRecordSelector.isPersonRecord(null), 'No record means no person');
        Assert.areEqual(
            0,
            PersonRecordSelector.filterPeople(null).size(),
            'No list means no people'
        );
    }

    @IsTest
    static void aListOfRecordsIsTurnedIntoPeople() {
        Account record = new Account(Name = 'Maria Garcia');
        insert record;

        Test.startTest();
        List<HouseholdService.Person> people = PersonRecordSelector.toPersons(
            [SELECT Id, Name, Preferred_Name__c, Deceased__c FROM Account WHERE Id = :record.Id]
        );
        Test.stopTest();

        Assert.areEqual(1, people.size(), 'One record makes one person');
    }
}

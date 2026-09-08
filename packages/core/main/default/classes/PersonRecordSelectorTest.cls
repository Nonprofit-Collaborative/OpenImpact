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

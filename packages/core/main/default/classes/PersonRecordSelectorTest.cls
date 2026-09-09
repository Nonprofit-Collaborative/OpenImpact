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

    /**
     * Every attribute the wording is built from, one at a time, on plain accounts with no
     * override of any kind in play. The five Core person fields are on the account object
     * in every org, so this exercises the real comparison rather than a stand-in.
     */
    @IsTest
    static void everyAttributeTheWordingIsBuiltFromCountsAsAChange() {
        Map<String, Object> changes = new Map<String, Object>{
            'Preferred_Name__c' => 'Mari',
            'Deceased__c' => true,
            'Household_Role__c' => 'Head',
            'Exclude_From_Household_Name__c' => true,
            'Exclude_From_Greetings__c' => true
        };

        Test.startTest();
        Map<String, Boolean> noticed = new Map<String, Boolean>();
        for (String fieldName : changes.keySet()) {
            Account previous = new Account(Name = 'Maria Garcia');
            Account record = new Account(Name = 'Maria Garcia');
            record.put(fieldName, changes.get(fieldName));
            noticed.put(fieldName, PersonRecordSelector.namingChanged(record, previous));
        }
        Test.stopTest();

        for (String fieldName : changes.keySet()) {
            Assert.isTrue(
                noticed.get(fieldName),
                'A change to ' + fieldName + ' changes what the household is called'
            );
        }
    }

    @IsTest
    static void aChangeTheWordingIsNotBuiltFromIsIgnored() {
        Account previous = new Account(Name = 'Maria Garcia', Deceased__c = false);
        Account record = new Account(
            Name = 'Maria Garcia',
            Deceased__c = false,
            BillingCity = 'Riverside',
            Description = 'Met at the gala'
        );

        Test.startTest();
        Boolean noticed = PersonRecordSelector.namingChanged(record, previous);
        Boolean unchanged = PersonRecordSelector.namingChanged(previous, previous);
        Test.stopTest();

        Assert.isFalse(noticed, 'An address or a note is not part of the wording');
        Assert.isFalse(unchanged, 'A record compared with itself has not changed');
    }

    @IsTest
    static void aChangeBackAgainIsNotAChange() {
        Account previous = new Account(Name = 'Maria Garcia', Household_Role__c = 'Head');
        Account record = new Account(Name = 'Maria Garcia', Household_Role__c = 'Head');

        Test.startTest();
        Boolean noticed = PersonRecordSelector.namingChanged(record, previous);
        Test.stopTest();

        Assert.isFalse(noticed, 'The same value on both sides is not a change');
    }

    @IsTest
    static void nothingToCompareIsNotAChange() {
        Assert.isFalse(
            PersonRecordSelector.namingChanged(null, new Account(Name = 'Maria Garcia')),
            'No record means nothing changed'
        );
        Assert.isFalse(
            PersonRecordSelector.namingChanged(new Account(Name = 'Maria Garcia'), null),
            'No previous version means nothing to compare with'
        );
    }
}

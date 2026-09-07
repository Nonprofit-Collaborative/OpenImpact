/**
 * Propagation of the default address to household members, in both membership modes, and
 * the handler classes the trigger dispatcher instantiates.
 *
 * Contact mode is exercised end to end through the triggers. Junction mode is exercised by
 * handing AddressService the membership HouseholdService would return, because the
 * membership junction and person accounts cannot both be created in one org shape; the
 * service reads membership only through that one call, so this is the whole of the
 * difference between the two modes as far as addresses are concerned.
 */
@IsTest
private class AddressPropagationTest {
    private static final String WINTER_STREET = '4120 East Camelback Road';
    private static final String WINTER_CITY = 'Phoenix';

    @IsTest
    static void contactModeMembersGetTheHouseholdAddress() {
        Account garcia = TestDataFactory.newHousehold('The Garcia Family');
        insert garcia;
        List<Contact> members = new List<Contact>{
            TestDataFactory.newContact('Ana', 'Garcia', garcia.Id),
            TestDataFactory.newContact('Luis', 'Garcia', garcia.Id),
            TestDataFactory.newContact('Sofia', 'Garcia', garcia.Id)
        };
        insert members;

        Test.startTest();
        insert new Address__c(
            Account__c = garcia.Id,
            Type__c = 'Home',
            Street__c = WINTER_STREET,
            City__c = WINTER_CITY,
            Is_Default__c = true
        );
        Test.stopTest();

        List<Contact> moved = [
            SELECT MailingStreet, MailingCity
            FROM Contact
            WHERE AccountId = :garcia.Id
        ];
        Assert.areEqual(3, moved.size(), 'All three members should still be in the household.');
        for (Contact member : moved) {
            Assert.areEqual(
                WINTER_STREET,
                member.MailingStreet,
                'Every member moves with the household.'
            );
            Assert.areEqual(
                WINTER_CITY,
                member.MailingCity,
                'Every member moves with the household.'
            );
        }
    }

    @IsTest
    static void junctionModeMembershipOverridesWhatContactModeWouldSay() {
        Account garcia = TestDataFactory.newHousehold('The Garcia Family');
        Account otherHousehold = TestDataFactory.newHousehold('The Nowak Family');
        insert new List<Account>{ garcia, otherHousehold };
        Contact ana = TestDataFactory.newContact('Ana', 'Garcia', otherHousehold.Id);
        insert ana;

        Test.startTest();
        AddressService.membersByHouseholdOverride = new Map<Id, Set<Id>>{
            garcia.Id => new Set<Id>{ ana.Id }
        };
        try {
            insert new Address__c(
                Account__c = garcia.Id,
                Type__c = 'Home',
                Street__c = WINTER_STREET,
                City__c = WINTER_CITY,
                Is_Default__c = true
            );
        } finally {
            AddressService.membersByHouseholdOverride = null;
        }
        Test.stopTest();

        Contact moved = [SELECT MailingStreet FROM Contact WHERE Id = :ana.Id];
        Assert.areEqual(
            WINTER_STREET,
            moved.MailingStreet,
            'A person who belongs to the household through the junction moves with it, even though the contact sits under another account.'
        );
    }

    @IsTest
    static void aPersonAccountMemberIsWrittenOnlyWherePersonAccountsExist() {
        Account garcia = TestDataFactory.newHousehold('The Garcia Family');
        Account personLikeAccount = TestDataFactory.newHousehold('Ana Garcia');
        insert new List<Account>{ garcia, personLikeAccount };

        Test.startTest();
        AddressService.membersByHouseholdOverride = new Map<Id, Set<Id>>{
            garcia.Id => new Set<Id>{ personLikeAccount.Id }
        };
        try {
            insert new Address__c(
                Account__c = garcia.Id,
                Type__c = 'Home',
                Street__c = WINTER_STREET,
                City__c = WINTER_CITY,
                Is_Default__c = true
            );
        } finally {
            AddressService.membersByHouseholdOverride = null;
        }
        Test.stopTest();

        Account member = [SELECT BillingStreet FROM Account WHERE Id = :personLikeAccount.Id];
        Assert.areEqual(
            null,
            member.BillingStreet,
            'A member account is written through its person mailing fields, never through its billing fields.'
        );
        Account household = [SELECT BillingStreet FROM Account WHERE Id = :garcia.Id];
        Assert.areEqual(
            WINTER_STREET,
            household.BillingStreet,
            'The household that owns the address still gets its billing fields.'
        );
    }

    @IsTest
    static void addressHandlerIgnoresASaveThatChangedNothingAboutTheAddress() {
        Account garcia = TestDataFactory.newHousehold('The Garcia Family');
        insert garcia;
        Address__c home = new Address__c(
            Account__c = garcia.Id,
            Type__c = 'Home',
            Street__c = WINTER_STREET,
            City__c = WINTER_CITY,
            Is_Default__c = true
        );
        insert home;
        Contact ana = TestDataFactory.newContact('Ana', 'Garcia', garcia.Id);
        insert ana;
        update new Contact(Id = ana.Id, MailingStreet = null, MailingCity = null);

        Test.startTest();
        AddressTriggerHandler handler = new AddressTriggerHandler();
        Address__c unchanged = [
            SELECT
                Id,
                Account__c,
                Contact__c,
                Person_Account__c,
                Type__c,
                Street__c,
                City__c,
                State__c,
                Postal_Code__c,
                Country__c,
                Is_Default__c
            FROM Address__c
            WHERE Id = :home.Id
        ];
        handler.afterUpdate(
            new List<Address__c>{ unchanged },
            new Map<Id, SObject>{ unchanged.Id => unchanged }
        );
        Test.stopTest();

        Contact stillCleared = [SELECT MailingStreet FROM Contact WHERE Id = :ana.Id];
        Assert.areEqual(
            null,
            stillCleared.MailingStreet,
            'Saving an address without changing it should not rewrite anybody.'
        );
    }

    @IsTest
    static void handlerContextsThatDoNothingAreSafeToCall() {
        Account garcia = TestDataFactory.newHousehold('The Garcia Family');
        insert garcia;
        Contact ana = TestDataFactory.newContact('Ana', 'Garcia', garcia.Id);
        insert ana;
        List<SObject> none = new List<SObject>();
        Map<Id, SObject> noneById = new Map<Id, SObject>();

        Test.startTest();
        AddressTriggerHandler addressHandler = new AddressTriggerHandler();
        addressHandler.beforeInsert(none);
        addressHandler.beforeUpdate(none, noneById);
        addressHandler.beforeDelete(none);
        addressHandler.afterInsert(none);
        addressHandler.afterUpdate(none, noneById);
        addressHandler.afterDelete(none);
        addressHandler.afterUndelete(none);

        ContactAddressHandler contactHandler = new ContactAddressHandler();
        contactHandler.beforeInsert(none);
        contactHandler.beforeUpdate(none, noneById);
        contactHandler.beforeDelete(none);
        contactHandler.afterInsert(none);
        contactHandler.afterUpdate(none, noneById);
        contactHandler.afterDelete(none);
        contactHandler.afterUndelete(none);

        AccountAddressHandler accountHandler = new AccountAddressHandler();
        accountHandler.beforeInsert(none);
        accountHandler.beforeUpdate(none, noneById);
        accountHandler.beforeDelete(none);
        accountHandler.afterInsert(none);
        accountHandler.afterUpdate(none, noneById);
        accountHandler.afterDelete(none);
        accountHandler.afterUndelete(none);
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Address__c],
            'A handler called with nothing to do writes nothing.'
        );
    }

    @IsTest
    static void handlersCalledDirectlyDoTheirWork() {
        Account garcia = TestDataFactory.newHousehold('The Garcia Family');
        garcia.BillingStreet = WINTER_STREET;
        garcia.BillingCity = WINTER_CITY;
        insert garcia;
        Account reloaded = [
            SELECT
                Id,
                RecordTypeId,
                BillingStreet,
                BillingCity,
                BillingState,
                BillingPostalCode,
                BillingCountry
            FROM Account
            WHERE Id = :garcia.Id
        ];
        delete [SELECT Id FROM Address__c];

        Test.startTest();
        new AccountAddressHandler().afterInsert(new List<Account>{ reloaded });
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Address__c WHERE Account__c = :garcia.Id],
            'The account handler should keep the address the household was created with.'
        );
    }

    @IsTest
    static void contactHandlerCapturesOnlyThePeopleWhoActuallyMoved() {
        Account garcia = TestDataFactory.newHousehold('The Garcia Family');
        insert garcia;
        List<Contact> members = new List<Contact>{
            TestDataFactory.newContact('Ana', 'Garcia', garcia.Id),
            TestDataFactory.newContact('Luis', 'Garcia', garcia.Id)
        };
        insert members;
        Contact ana = new Contact(Id = members[0].Id, MailingStreet = WINTER_STREET);
        Contact luis = new Contact(Id = members[1].Id);
        Map<Id, SObject> oldMap = new Map<Id, SObject>{
            members[0].Id => new Contact(Id = members[0].Id),
            members[1].Id => new Contact(Id = members[1].Id)
        };

        Test.startTest();
        new ContactAddressHandler().afterUpdate(new List<Contact>{ ana, luis }, oldMap);
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Address__c WHERE Account__c = :garcia.Id],
            'One household address, created once, from the one person who moved.'
        );
    }
}

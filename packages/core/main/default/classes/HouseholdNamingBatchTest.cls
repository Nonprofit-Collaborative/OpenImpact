/**
 * The recompute Maria starts after she changes a naming pattern.
 */
@IsTest
private class HouseholdNamingBatchTest {
    @IsTest
    static void everyHouseholdIsRenamedExceptTheOnesWordedByHand() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account patterned = HouseholdTestDataFactory.newHousehold('Old name');
        Account byHand = HouseholdTestDataFactory.newHousehold('The Reverend and Mrs. Smith');
        byHand.Custom_Name__c = true;
        insert new List<Account>{ patterned, byHand };
        insert new List<Contact>{
            new Contact(
                Salutation = 'Ms.',
                FirstName = 'Maria',
                LastName = 'Garcia',
                AccountId = patterned.Id
            ),
            new Contact(
                Salutation = 'Mr.',
                FirstName = 'John',
                LastName = 'Smith',
                AccountId = byHand.Id
            )
        };
        update new Account(Id = patterned.Id, Name = 'Old name');

        Test.startTest();
        Database.executeBatch(new HouseholdNamingBatch(), 200);
        Test.stopTest();

        Assert.areEqual(
            'The Garcia Family',
            [SELECT Name FROM Account WHERE Id = :patterned.Id].Name,
            'The household was renamed from the pattern'
        );
        Assert.areEqual(
            'The Reverend and Mrs. Smith',
            [SELECT Name FROM Account WHERE Id = :byHand.Id].Name,
            'A household worded by hand is never touched'
        );
    }

    @IsTest
    static void theJobKeepsCountOfWhatItRead() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account household = HouseholdTestDataFactory.newHousehold('Old name');
        insert household;
        HouseholdNamingBatch job = new HouseholdNamingBatch();

        Test.startTest();
        job.execute(null, new List<Account>{ household });
        Test.stopTest();

        Assert.areEqual(1, job.householdsRead, 'One household was read');
    }
}

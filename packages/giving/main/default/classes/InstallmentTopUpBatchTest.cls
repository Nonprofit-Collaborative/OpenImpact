/**
 * Tests for the nightly top up batch: every active recurring commitment is reached, not
 * only the oldest handful, and the run is recorded when the batch finishes.
 */
@IsTest
private class InstallmentTopUpBatchTest {
    @IsTest
    static void extendsEveryActiveRecurringCommitmentNotJustTheOldest() {
        Contact person = new Contact(FirstName = 'Sarah', LastName = 'Nguyen');
        insert person;
        List<Commitment__c> recurring = new List<Commitment__c>();
        for (Integer index = 0; index < 60; index++) {
            recurring.add(
                new Commitment__c(
                    Type__c = 'Recurring',
                    Status__c = 'Active',
                    Donor_Contact__c = person.Id,
                    Amount__c = 25,
                    Frequency__c = 'Yearly',
                    Start_Date__c = Date.today().addDays(-index)
                )
            );
        }
        insert recurring;
        delete [SELECT Id FROM Installment__c];

        Test.startTest();
        Database.executeBatch(new InstallmentTopUpBatch(), InstallmentTopUpBatch.CHUNK_SIZE);
        Test.stopTest();

        Assert.areEqual(
            60,
            [SELECT COUNT() FROM Installment__c],
            'Every one of the sixty commitments was reached, across more chunks than one.'
        );
        Assert.areNotEqual(
            null,
            Giving_Settings__c.getOrgDefaults().Installment_Top_Up_Last_Run__c,
            'The batch records when it finished, which is what the Hub shows.'
        );
    }

    @IsTest
    static void leavesAPausedCommitmentAlone() {
        Contact person = new Contact(FirstName = 'Sarah', LastName = 'Nguyen');
        insert person;
        Commitment__c paused = new Commitment__c(
            Type__c = 'Recurring',
            Status__c = 'Paused',
            Donor_Contact__c = person.Id,
            Amount__c = 25,
            Frequency__c = 'Monthly',
            Start_Date__c = Date.today()
        );
        insert paused;
        delete [SELECT Id FROM Installment__c];

        Test.startTest();
        Database.executeBatch(new InstallmentTopUpBatch(), InstallmentTopUpBatch.CHUNK_SIZE);
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Installment__c WHERE Commitment__c = :paused.Id],
            'A paused commitment generates nothing (R-CM3).'
        );
    }
}

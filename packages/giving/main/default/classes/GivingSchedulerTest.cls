/**
 * Tests for the two daily jobs and for the helper that schedules them when the Giving
 * module is turned on.
 */
@IsTest
private class GivingSchedulerTest {
    @IsTest
    static void schedulesBothDailyJobs() {
        Test.startTest();
        GivingScheduler.scheduleAll();
        Test.stopTest();

        Assert.areEqual(
            3,
            [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'Open Impact Giving%'],
            'Turning the module on schedules the top up, the overdue pass and the donor levels pass.'
        );
    }

    @IsTest
    static void theOverdueJobRuns() {
        Contact person = new Contact(FirstName = 'Sarah', LastName = 'Nguyen');
        insert person;
        Commitment__c pledge = new Commitment__c(
            Type__c = 'Pledge',
            Status__c = 'Active',
            Donor_Contact__c = person.Id,
            Amount__c = 100,
            Frequency__c = 'Monthly',
            Start_Date__c = Date.today().addMonths(-2),
            Expected_Total__c = 200,
            Installments_Planned__c = 2
        );
        insert pledge;
        delete [SELECT Id FROM Installment__c WHERE Commitment__c = :pledge.Id];
        insert new Installment__c(
            Commitment__c = pledge.Id,
            Sequence__c = 1,
            Due_Date__c = Date.today().addDays(-40),
            Expected_Amount__c = 100,
            Status__c = 'Scheduled'
        );

        Test.startTest();
        new InstallmentSchedulable().execute(null);
        Test.stopTest();

        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM Installment__c
                WHERE Status__c = 'Overdue' AND Commitment__c = :pledge.Id
            ],
            'The daily pass marks a payment forty days late Overdue.'
        );
    }

    @IsTest
    static void theOverdueJobLeavesAPaymentInsideTheGracePeriodAlone() {
        Contact person = new Contact(FirstName = 'Sarah', LastName = 'Nguyen');
        insert person;
        Commitment__c pledge = new Commitment__c(
            Type__c = 'Pledge',
            Status__c = 'Active',
            Donor_Contact__c = person.Id,
            Amount__c = 100,
            Frequency__c = 'Monthly',
            Start_Date__c = Date.today(),
            Expected_Total__c = 100,
            Installments_Planned__c = 1
        );
        insert pledge;
        delete [SELECT Id FROM Installment__c WHERE Commitment__c = :pledge.Id];
        insert new Installment__c(
            Commitment__c = pledge.Id,
            Sequence__c = 1,
            Due_Date__c = Date.today().addDays(-1),
            Expected_Amount__c = 100,
            Status__c = 'Scheduled'
        );

        Test.startTest();
        new InstallmentSchedulable().execute(null);
        Test.stopTest();

        Assert.areEqual(
            0,
            [
                SELECT COUNT()
                FROM Installment__c
                WHERE Status__c = 'Overdue' AND Commitment__c = :pledge.Id
            ],
            'A payment one day late is inside the five day grace period, so it stays Scheduled.'
        );
    }

    @IsTest
    static void theTopUpJobRunsAndRecordsWhenItFinished() {
        Contact person = new Contact(FirstName = 'Sarah', LastName = 'Nguyen');
        insert person;
        insert new Commitment__c(
            Type__c = 'Recurring',
            Status__c = 'Active',
            Donor_Contact__c = person.Id,
            Amount__c = 25,
            Frequency__c = 'Monthly',
            Start_Date__c = Date.today()
        );

        Test.startTest();
        new InstallmentTopUpSchedulable().execute(null);
        Test.stopTest();
        // Test.stopTest() runs the batch the schedulable started, so its work is done here.

        Assert.areNotEqual(
            null,
            Giving_Settings__c.getOrgDefaults().Installment_Top_Up_Last_Run__c,
            'The job says when it last finished, so Maria can see it is running.'
        );
        Assert.isTrue(
            [SELECT COUNT() FROM Installment__c] > 0,
            'The top up puts a year of payments in front of a recurring gift.'
        );
    }
}

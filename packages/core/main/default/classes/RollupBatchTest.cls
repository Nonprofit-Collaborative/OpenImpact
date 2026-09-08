/**
 * The nightly reconciliation and the schedule the console starts and stops.
 *
 * These tests have not been executed: no Salesforce org exists in this environment.
 */
@IsTest
private class RollupBatchTest {
    private static Rollup_Definition__c memberCount(String key, String mode, Boolean active) {
        return new Rollup_Definition__c(
            Name = key,
            Definition_Key__c = key,
            Source_Object__c = 'Household_Member__c',
            Target_Object__c = 'Account',
            Relationship_Path__c = 'Household__c',
            Aggregate__c = 'COUNT',
            Target_Field__c = 'Member_Count__c',
            Mode__c = mode,
            Fiscal_Year_Aware__c = false,
            Active__c = active
        );
    }

    @IsTest
    static void theNightlyRunCoversScheduledAndBothAndNothingElse() {
        insert new List<Rollup_Definition__c>{
            memberCount('Core_Scheduled', RollupService.MODE_SCHEDULED, true),
            memberCount('Core_Both', RollupService.MODE_BOTH, true),
            memberCount('Core_Real_Time', RollupService.MODE_REAL_TIME, true),
            memberCount('Core_Inactive', RollupService.MODE_SCHEDULED, false)
        };
        RollupService.skipEngine = true;

        Test.startTest();
        Database.executeBatch(new RollupBatch(), 1);
        Test.stopTest();

        List<Rollup_Definition__c> stamped = [
            SELECT Definition_Key__c
            FROM Rollup_Definition__c
            WHERE Last_Calculated__c != NULL
        ];
        Set<String> keys = new Set<String>();
        for (Rollup_Definition__c definition : stamped) {
            keys.add(definition.Definition_Key__c);
        }
        System.Assert.areEqual(
            new Set<String>{ 'Core_Scheduled', 'Core_Both' },
            keys,
            'R-R4: a real time rollup is already right, and an inactive one does not run'
        );
    }

    @IsTest
    static void theScheduleIsStartedAndStoppedFromTheConsole() {
        Test.startTest();
        RollupScheduler.start();
        Boolean scheduledAfterStart = RollupScheduler.isScheduled();
        RollupScheduler.stop();
        Boolean scheduledAfterStop = RollupScheduler.isScheduled();
        Test.stopTest();

        System.Assert.isTrue(scheduledAfterStart, 'Starting the nightly run schedules it');
        System.Assert.isFalse(scheduledAfterStop, 'And stopping it takes it away');
    }

    @IsTest
    static void startingTwiceDoesNotScheduleTwoJobs() {
        Test.startTest();
        Id first = RollupScheduler.start();
        Id second = RollupScheduler.start();
        Test.stopTest();

        System.Assert.areEqual(first, second, 'The same job, so a second click changes nothing');
    }
}

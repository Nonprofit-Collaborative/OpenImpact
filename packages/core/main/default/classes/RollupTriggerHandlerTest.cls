/**
 * The generic real-time handler: one handler, whichever entity a package registers it against.
 *
 * These tests have not been executed: no Salesforce org exists in this environment.
 */
@IsTest
private class RollupTriggerHandlerTest {
    private static Rollup_Definition__c memberCount() {
        return new Rollup_Definition__c(
            Name = 'Household member count',
            Definition_Key__c = 'Core_Household_Member_Count',
            Source_Object__c = 'Household_Member__c',
            Target_Object__c = 'Account',
            Relationship_Path__c = 'Household__c',
            Aggregate__c = 'COUNT',
            Target_Field__c = 'Member_Count__c',
            Mode__c = RollupService.MODE_REAL_TIME,
            Fiscal_Year_Aware__c = false,
            Active__c = true
        );
    }

    @IsTest
    static void theHandlerRunsTheDefinitionsForWhateverEntityItWasGiven() {
        insert memberCount();
        Account household = new Account(Name = 'Test household');
        insert household;
        Contact person = new Contact(LastName = 'Okafor', AccountId = household.Id);
        insert person;
        Household_Member__c membership = new Household_Member__c(
            Household__c = household.Id,
            Contact__c = person.Id
        );
        insert membership;

        RollupService.skipEngine = true;
        TriggerHandler.clearRunClaims();
        TriggerHandler.testNew = new List<SObject>{ membership };

        Test.startTest();
        new RollupTriggerHandler().afterInsert();
        Test.stopTest();

        System.Assert.isNotNull(RollupService.lastMetadata, 'The definition reached the engine');
        System.Assert.areEqual(
            'Household_Member__c',
            RollupService.lastMetadata[0].CalcItemText__c,
            'The entity was worked out from the records in front of the handler, not hard coded'
        );
    }

    @IsTest
    static void thesameRecordsAreNotRunTwiceInOneTransaction() {
        insert memberCount();
        Account household = new Account(Name = 'Test household');
        insert household;
        Household_Member__c membership = new Household_Member__c(Household__c = household.Id);
        insert membership;

        RollupService.skipEngine = true;
        TriggerHandler.clearRunClaims();
        TriggerHandler.testNew = new List<SObject>{ membership };

        RollupTriggerHandler handler = new RollupTriggerHandler();
        handler.afterInsert();
        RollupService.lastMetadata = null;

        Test.startTest();
        handler.afterInsert();
        Test.stopTest();

        System.Assert.isNull(
            RollupService.lastMetadata,
            'A rollup that causes its own object to be saved again does its work once per record'
        );
    }

    /**
     * A definition asking for a SUM with nothing to sum cannot be expressed to the engine, so
     * the adapter refuses it. `skipEngine` stands the engine down but not this path: the refusal
     * happens while the definition is being turned into metadata, before the engine would be
     * called at all. Two things have to be true afterwards: the save went through, and Maria can
     * find out why the number did not move.
     *
     * The membership is saved before the broken definition exists, so the only run of the rollup
     * over it is the one this test makes, and the single log entry below is that run's.
     */
    @IsTest
    static void aFailureIsLoggedRatherThanFailingTheSave() {
        Account household = new Account(Name = 'Test household');
        insert household;
        Household_Member__c membership = new Household_Member__c(Household__c = household.Id);
        insert membership;

        Rollup_Definition__c broken = memberCount();
        broken.Aggregate__c = 'SUM';
        broken.Source_Field__c = null;
        insert broken;

        RollupService.skipEngine = true;
        RollupService.lastMetadata = null;
        TriggerHandler.clearRunClaims();
        TriggerHandler.testNew = new List<SObject>{ membership };

        Test.startTest();
        new RollupTriggerHandler().afterInsert();
        Test.getEventBus().deliver();
        Test.stopTest();

        // Nothing thrown: the administrator's save went through.
        System.Assert.isNull(
            RollupService.lastMetadata,
            'The broken definition never reached the engine, so the refusal is the path that ran'
        );
        System.Assert.areEqual(
            1,
            [SELECT COUNT() FROM Household_Member__c WHERE Id = :membership.Id],
            'The save the rollup was running for stands (R-R4, plan Principle 2)'
        );
        List<Error_Log__c> logged = [
            SELECT Message__c, Technical_Detail__c, Record_Reference__c, Object_Name__c
            FROM Error_Log__c
            WHERE Context__c = 'RollupService.runRealTime'
        ];
        System.Assert.areEqual(1, logged.size(), 'And the failure is in the log, once');
        System.Assert.areEqual(
            String.valueOf(broken.Id),
            logged[0].Record_Reference__c,
            'Pointing at the definition Maria has to fix'
        );
        System.Assert.areEqual(
            'Rollup_Definition__c',
            logged[0].Object_Name__c,
            'So the entry can be grouped by what it is about'
        );
        System.Assert.areEqual(
            Label.Core_ErrorLog_UnexpectedFailure,
            logged[0].Message__c,
            'What Maria reads is plain language'
        );
        System.Assert.isTrue(
            logged[0].Technical_Detail__c.contains('RollupAdapterException'),
            'And the detail she forwards names what refused the definition'
        );
    }

    @IsTest
    static void theHandlerNamesItselfTheWayTheRegistryDoes() {
        System.Assert.areEqual(
            'RollupTriggerHandler',
            new RollupTriggerHandler().getName(),
            'The name matches the Automation Registry rows that register it'
        );
    }
}

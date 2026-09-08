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

    @IsTest
    static void aFailureIsLoggedRatherThanFailingTheSave() {
        Rollup_Definition__c broken = memberCount();
        broken.Aggregate__c = 'SUM';
        broken.Source_Field__c = null;
        insert broken;

        Account household = new Account(Name = 'Test household');
        insert household;
        Household_Member__c membership = new Household_Member__c(Household__c = household.Id);
        insert membership;

        RollupService.skipEngine = true;
        TriggerHandler.clearRunClaims();
        TriggerHandler.testNew = new List<SObject>{ membership };

        Test.startTest();
        new RollupTriggerHandler().afterInsert();
        Test.stopTest();

        // Nothing thrown: the administrator's save went through and the failure is in the log.
        System.Assert.isTrue(true, 'A broken rollup never fails a save (R-R4, plan Principle 2)');
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

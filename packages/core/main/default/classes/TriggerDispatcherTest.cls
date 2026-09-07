/**
 * The trigger framework, exercised without a trigger.
 *
 * v0.1 ships no packaged trigger: feature C-01 adds the first two. So these tests dispatch a
 * test-only handler with an explicit context, which is the same code path a real trigger takes
 * once the dispatcher has read `Trigger.operationType`.
 */
@IsTest
private class TriggerDispatcherTest {
    private static final String HANDLER_NAME = 'Test_Recording_Handler';

    private class RecordingHandler extends TriggerHandler {
        public String lastPhase;
        public Integer runCount = 0;
        public Boolean shouldFail = false;

        public override String getName() {
            return HANDLER_NAME;
        }

        public override void beforeInsert(List<SObject> newRecords) {
            note('beforeInsert');
        }

        public override void afterInsert(
            List<SObject> newRecords,
            Map<Id, SObject> newRecordsById
        ) {
            note('afterInsert');
        }

        public override void beforeUpdate(
            List<SObject> newRecords,
            Map<Id, SObject> newRecordsById,
            List<SObject> oldRecords,
            Map<Id, SObject> oldRecordsById
        ) {
            note('beforeUpdate');
        }

        public override void afterUpdate(
            List<SObject> newRecords,
            Map<Id, SObject> newRecordsById,
            List<SObject> oldRecords,
            Map<Id, SObject> oldRecordsById
        ) {
            note('afterUpdate');
        }

        public override void beforeDelete(
            List<SObject> oldRecords,
            Map<Id, SObject> oldRecordsById
        ) {
            note('beforeDelete');
        }

        public override void afterDelete(
            List<SObject> oldRecords,
            Map<Id, SObject> oldRecordsById
        ) {
            note('afterDelete');
        }

        public override void afterUndelete(
            List<SObject> newRecords,
            Map<Id, SObject> newRecordsById
        ) {
            note('afterUndelete');
        }

        private void note(String phase) {
            lastPhase = phase;
            runCount++;
            if (shouldFail) {
                throw new IllegalArgumentException('Maria pasted a value this handler cannot use.');
            }
        }
    }

    private static TriggerDispatcher.Context contextFor(System.TriggerOperation operation) {
        List<Error_Log__c> records = TestDataFactory.insertErrorLogs(2, ErrorLogger.STATUS_NEW);
        Map<Id, SObject> byId = new Map<Id, SObject>((List<SObject>) records);
        Boolean isDelete =
            operation == System.TriggerOperation.BEFORE_DELETE ||
            operation == System.TriggerOperation.AFTER_DELETE;
        return new TriggerDispatcher.Context(
            operation,
            isDelete ? null : (List<SObject>) records,
            isDelete ? null : byId,
            isDelete ? (List<SObject>) records : null,
            isDelete ? byId : null
        );
    }

    @IsTest
    static void dispatchesEveryTriggerContext() {
        Map<System.TriggerOperation, String> expected = new Map<System.TriggerOperation, String>{
            System.TriggerOperation.BEFORE_INSERT => 'beforeInsert',
            System.TriggerOperation.AFTER_INSERT => 'afterInsert',
            System.TriggerOperation.BEFORE_UPDATE => 'beforeUpdate',
            System.TriggerOperation.AFTER_UPDATE => 'afterUpdate',
            System.TriggerOperation.BEFORE_DELETE => 'beforeDelete',
            System.TriggerOperation.AFTER_DELETE => 'afterDelete',
            System.TriggerOperation.AFTER_UNDELETE => 'afterUndelete'
        };
        for (System.TriggerOperation operation : expected.keySet()) {
            RecordingHandler handler = new RecordingHandler();
            TriggerDispatcher.run(handler, contextFor(operation));
            Assert.areEqual(
                expected.get(operation),
                handler.lastPhase,
                'The dispatcher ran the wrong method for ' + operation
            );
        }
    }

    @IsTest
    static void bypassStopsTheHandler() {
        RecordingHandler handler = new RecordingHandler();
        TriggerDispatcher.Context context = contextFor(System.TriggerOperation.BEFORE_INSERT);

        AutomationControl.bypass(HANDLER_NAME);
        TriggerDispatcher.run(handler, context);
        Assert.areEqual(0, handler.runCount, 'A bypassed handler must not run.');

        AutomationControl.clearBypass(HANDLER_NAME);
        TriggerDispatcher.run(handler, context);
        Assert.areEqual(1, handler.runCount, 'Clearing the bypass must let the handler run.');

        AutomationControl.bypass(HANDLER_NAME);
        AutomationControl.clearAllBypasses();
        TriggerDispatcher.run(handler, context);
        Assert.areEqual(2, handler.runCount, 'Clearing all bypasses must let the handler run.');
    }

    @IsTest
    static void globalPauseStopsTheHandler() {
        TestDataFactory.pausedSettings(2);
        RecordingHandler handler = new RecordingHandler();

        TriggerDispatcher.run(handler, contextFor(System.TriggerOperation.AFTER_INSERT));

        Assert.areEqual(0, handler.runCount, 'No handler runs while automation is paused.');
    }

    @IsTest
    static void anExpiredPauseDoesNotStopTheHandler() {
        TestDataFactory.pausedSettings(-1);
        RecordingHandler handler = new RecordingHandler();

        TriggerDispatcher.run(handler, contextFor(System.TriggerOperation.AFTER_INSERT));

        Assert.areEqual(1, handler.runCount, 'A pause in the past must have expired by itself.');
    }

    @IsTest
    static void aSwitchedOffAutomationStopsTheHandler() {
        TestDataFactory.insertAutomationSettings(new Map<String, Boolean>{ HANDLER_NAME => false });
        RecordingHandler handler = new RecordingHandler();

        TriggerDispatcher.run(handler, contextFor(System.TriggerOperation.BEFORE_INSERT));

        Assert.areEqual(0, handler.runCount, 'A switched off automation must not run.');
    }

    @IsTest
    static void aFailureInAnAfterContextIsLoggedAndReported() {
        RecordingHandler handler = new RecordingHandler();
        handler.shouldFail = true;
        Boolean reported = false;

        Test.startTest();
        try {
            TriggerDispatcher.run(handler, contextFor(System.TriggerOperation.AFTER_UPDATE));
        } catch (TriggerDispatcher.TriggerDispatcherException expected) {
            reported = true;
            Assert.areEqual(
                Label.Core_Automation_UnexpectedError,
                expected.getMessage(),
                'David must see the friendly message, not a stack trace.'
            );
        }

        Test.stopTest();

        Assert.isTrue(reported, 'A failure after the save must be reported to the user.');
        List<Error_Log__c> logged = [
            SELECT Context__c, Message__c, Technical_Detail__c, Severity__c, Status__c
            FROM Error_Log__c
            WHERE Context__c = :HANDLER_NAME
        ];
        Assert.areEqual(1, logged.size(), 'The failure must be in the Error Log.');
        Assert.areEqual(ErrorLogger.SEVERITY_ERROR, logged[0].Severity__c, 'Severity is Error.');
        Assert.areEqual(ErrorLogger.STATUS_NEW, logged[0].Status__c, 'A new entry starts as New.');
        Assert.isTrue(
            logged[0].Technical_Detail__c.contains('IllegalArgumentException'),
            'The technical detail names the exception type.'
        );
    }

    @IsTest
    static void aFailureInABeforeContextIsLoggedOnce() {
        RecordingHandler handler = new RecordingHandler();
        handler.shouldFail = true;

        // Outside a real trigger there is nothing to call addError on, so the dispatcher reports
        // the same friendly message by throwing. Inside a before trigger it addErrors instead,
        // which only a deployed org can exercise.
        Test.startTest();
        try {
            TriggerDispatcher.run(handler, contextFor(System.TriggerOperation.BEFORE_INSERT));
        } catch (TriggerDispatcher.TriggerDispatcherException expected) {
            Assert.areEqual(
                Label.Core_Automation_UnexpectedError,
                expected.getMessage(),
                'Maria must see the friendly message.'
            );
        }
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Error_Log__c WHERE Context__c = :HANDLER_NAME],
            'The failure is logged exactly once.'
        );
    }

    @IsTest
    static void nothingHappensWithoutAHandlerOrAContext() {
        TriggerDispatcher.run(
            (TriggerHandler) null,
            contextFor(System.TriggerOperation.BEFORE_INSERT)
        );
        TriggerDispatcher.run(new RecordingHandler(), null);
        TriggerDispatcher.run(
            new RecordingHandler(),
            new TriggerDispatcher.Context(null, null, null, null, null)
        );
        // Called outside a trigger, the one argument entry point does nothing at all.
        TriggerDispatcher.run(new RecordingHandler());

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Error_Log__c WHERE Context__c = :HANDLER_NAME],
            'Nothing ran, so nothing failed.'
        );
    }

    @IsTest
    static void theRegistryDecidesWhichHandlersRunForAnObject() {
        TestRegisteredHandler.reset();
        Automation_Registry__mdt registered = TestDataFactory.registryEntry(
            'Registered_Test',
            true
        );
        registered.Handler_Class__c = 'TestRegisteredHandler';
        registered.Object_Name__c = 'Error_Log__c';
        AutomationRegistrySelector.registryOverride = new List<Automation_Registry__mdt>{
            registered
        };

        Test.startTest();
        TriggerDispatcher.run('Error_Log__c', contextFor(System.TriggerOperation.AFTER_INSERT));
        Test.stopTest();

        Assert.areEqual(1, TestRegisteredHandler.runCount, 'The registered handler ran.');
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Error_Log__c WHERE Severity__c = 'Warning'],
            'And nothing was skipped.'
        );
    }

    @IsTest
    static void aRegisteredAutomationRespectsItsOwnSwitch() {
        TestRegisteredHandler.reset();
        TestDataFactory.insertAutomationSettings(
            new Map<String, Boolean>{ 'Registered_Test' => false }
        );
        Automation_Registry__mdt registered = TestDataFactory.registryEntry(
            'Registered_Test',
            true
        );
        registered.Handler_Class__c = 'TestRegisteredHandler';
        AutomationRegistrySelector.registryOverride = new List<Automation_Registry__mdt>{
            registered
        };

        Test.startTest();
        TriggerDispatcher.run('Error_Log__c', contextFor(System.TriggerOperation.AFTER_INSERT));
        Test.stopTest();

        Assert.areEqual(
            0,
            TestRegisteredHandler.runCount,
            'The switch is keyed by the name in the registry, not by the class name.'
        );
    }

    @IsTest
    static void aHandlerThatCannotBeStartedIsSkippedWithAWarning() {
        Automation_Registry__mdt missing = TestDataFactory.registryEntry('Missing_Test', true);
        missing.Handler_Class__c = 'NoSuchHandlerClass';
        Automation_Registry__mdt notAHandler = TestDataFactory.registryEntry('Wrong_Test', true);
        notAHandler.Handler_Class__c = 'ErrorLogger';
        notAHandler.Execution_Order__c = 30;
        Automation_Registry__mdt noClass = TestDataFactory.registryEntry('Blank_Test', true);
        noClass.Handler_Class__c = null;
        noClass.Execution_Order__c = 40;
        AutomationRegistrySelector.registryOverride = new List<Automation_Registry__mdt>{
            missing,
            notAHandler,
            noClass
        };

        Test.startTest();
        TriggerDispatcher.run('Error_Log__c', contextFor(System.TriggerOperation.AFTER_INSERT));
        Test.stopTest();

        Assert.areEqual(
            3,
            [SELECT COUNT() FROM Error_Log__c WHERE Severity__c = 'Warning'],
            'Each automation that could not be started is recorded as a warning.'
        );
    }

    @IsTest
    static void anObjectWithNoRegisteredAutomationDoesNothing() {
        AutomationRegistrySelector.registryOverride = new List<Automation_Registry__mdt>();

        TriggerDispatcher.run('Error_Log__c', contextFor(System.TriggerOperation.AFTER_INSERT));
        TriggerDispatcher.run('   ', contextFor(System.TriggerOperation.AFTER_INSERT));
        TriggerDispatcher.run('Error_Log__c', (TriggerDispatcher.Context) null);
        // Called outside a trigger, the one argument entry point does nothing at all.
        TriggerDispatcher.run('Error_Log__c');

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Error_Log__c WHERE Severity__c = 'Warning'],
            'Nothing ran, so nothing was skipped.'
        );
    }

    @IsTest
    static void theRecursionGuardClaimsEachRecordOnce() {
        RecordingHandler handler = new RecordingHandler();
        List<Error_Log__c> records = TestDataFactory.insertErrorLogs(3, ErrorLogger.STATUS_NEW);
        Set<Id> first = new Set<Id>{ records[0].Id, records[1].Id };
        Set<Id> overlapping = new Set<Id>{ records[1].Id, records[2].Id };

        Assert.areEqual(
            first,
            handler.claimRunFor('afterUpdate', first),
            'The first claim hands back everything.'
        );
        Assert.areEqual(
            new Set<Id>{ records[2].Id },
            handler.claimRunFor('afterUpdate', overlapping),
            'A second claim hands back only what this handler has not seen.'
        );
        Assert.isTrue(handler.hasRunFor('afterUpdate', records[0].Id), 'That record is claimed.');
        Assert.isTrue(
            handler.claimRunFor('afterUpdate', new Set<Id>()).isEmpty(),
            'Claiming nothing claims nothing.'
        );
        Assert.isTrue(
            handler.claimRunFor('afterUpdate', null).isEmpty(),
            'And neither does claiming null.'
        );
        Assert.isFalse(
            handler.hasRunFor('beforeUpdate', records[0].Id),
            'A claim is per phase, so another phase is untouched.'
        );

        handler.releaseRunFor('afterUpdate');
        Assert.isFalse(handler.hasRunFor('afterUpdate', records[0].Id), 'Releasing clears it.');

        handler.claimRunFor('afterUpdate', first);
        TriggerHandler.clearRunClaims();
        Assert.isFalse(handler.hasRunFor('afterUpdate', records[0].Id), 'So does clearing all.');
    }

    @IsTest
    static void aFourHundredRecordLoadIsHandledInFull() {
        TestRegisteredHandler.reset();
        Automation_Registry__mdt registered = TestDataFactory.registryEntry('Bulk_Test', true);
        registered.Handler_Class__c = 'TestRegisteredHandler';
        AutomationRegistrySelector.registryOverride = new List<Automation_Registry__mdt>{
            registered
        };
        // One DML of 400 records fires the trigger twice, in one transaction, with statics kept.
        List<Error_Log__c> loaded = TestDataFactory.insertErrorLogs(400, ErrorLogger.STATUS_NEW);
        Map<Id, SObject> firstChunk = new Map<Id, SObject>();
        Map<Id, SObject> secondChunk = new Map<Id, SObject>();
        for (Integer i = 0; i < loaded.size(); i++) {
            if (i < 200) {
                firstChunk.put(loaded[i].Id, loaded[i]);
            } else {
                secondChunk.put(loaded[i].Id, loaded[i]);
            }
        }

        Test.startTest();
        for (Map<Id, SObject> chunk : new List<Map<Id, SObject>>{ firstChunk, secondChunk }) {
            TriggerDispatcher.run(
                'Error_Log__c',
                new TriggerDispatcher.Context(
                    System.TriggerOperation.AFTER_INSERT,
                    chunk.values(),
                    chunk,
                    null,
                    null
                )
            );
        }
        Test.stopTest();

        Assert.areEqual(2, TestRegisteredHandler.runCount, 'The handler ran once per chunk.');
        Assert.areEqual(
            400,
            TestRegisteredHandler.handledIds.size(),
            'Every record was handled: the guard is per record, not per phase.'
        );
    }

    @IsTest
    static void aHandlerNamesItselfAfterItsClass() {
        Assert.areEqual(
            HANDLER_NAME,
            new RecordingHandler().getName(),
            'A handler may override its name.'
        );
        Assert.areEqual(
            'TriggerHandler',
            new TriggerHandler().getName(),
            'By default a handler is named after its class.'
        );
        Assert.isFalse(
            new TestRegisteredHandler().getName().contains('.'),
            'The name never carries a namespace: every consumer keys on the bare name.'
        );
        Assert.areEqual(
            'TestRegisteredHandler',
            new TestRegisteredHandler().getName(),
            'Which is the class name, whatever namespace the package runs under.'
        );
    }

    @IsTest
    static void theBaseHandlerDoesNothingInEveryContext() {
        TriggerHandler handler = new TriggerHandler();
        List<SObject> records = new List<SObject>();
        Map<Id, SObject> byId = new Map<Id, SObject>();

        handler.beforeInsert(records);
        handler.afterInsert(records, byId);
        handler.beforeUpdate(records, byId, records, byId);
        handler.afterUpdate(records, byId, records, byId);
        handler.beforeDelete(records, byId);
        handler.afterDelete(records, byId);
        handler.afterUndelete(records, byId);

        Assert.areEqual(0, [SELECT COUNT() FROM Error_Log__c], 'The base handler does nothing.');
    }
}

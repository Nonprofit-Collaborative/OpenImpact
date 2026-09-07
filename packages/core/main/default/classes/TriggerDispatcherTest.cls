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
        try {
            TriggerDispatcher.run(handler, contextFor(System.TriggerOperation.BEFORE_INSERT));
        } catch (TriggerDispatcher.TriggerDispatcherException expected) {
            Assert.areEqual(
                Label.Core_Automation_UnexpectedError,
                expected.getMessage(),
                'Maria must see the friendly message.'
            );
        }

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Error_Log__c WHERE Context__c = :HANDLER_NAME],
            'The failure is logged exactly once.'
        );
    }

    @IsTest
    static void nothingHappensWithoutAHandlerOrAContext() {
        TriggerDispatcher.run(null, contextFor(System.TriggerOperation.BEFORE_INSERT));
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
    static void theRecursionGuardClaimsAPhaseOnce() {
        RecordingHandler handler = new RecordingHandler();

        Assert.isTrue(handler.claimRunFor('afterUpdate'), 'The first claim succeeds.');
        Assert.isFalse(handler.claimRunFor('afterUpdate'), 'The second claim does not.');
        Assert.isTrue(handler.hasRunFor('afterUpdate'), 'The phase is marked as run.');

        handler.releaseRunFor('afterUpdate');
        Assert.isFalse(handler.hasRunFor('afterUpdate'), 'Releasing clears the claim.');

        handler.claimRunFor('afterUpdate');
        TriggerHandler.clearRunClaims();
        Assert.isFalse(handler.hasRunFor('afterUpdate'), 'Clearing all claims clears this one.');
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

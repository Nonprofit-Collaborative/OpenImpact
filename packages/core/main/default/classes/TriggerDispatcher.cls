/**
 * The single entry point every packaged trigger uses.
 *
 * A trigger contains one line:
 *
 *     trigger ContactTrigger on Contact (before insert, after insert) {
 *         TriggerDispatcher.run(new ContactTriggerHandler());
 *     }
 *
 * Before it invokes anything, the dispatcher asks three questions in order: is this handler
 * bypassed for this transaction, is all automation paused for the org, and is this automation
 * switched on. Any "no" and the handler simply does not run.
 *
 * Failure handling is a deliberate choice. Whatever a handler throws is logged to the Error Log
 * first, so R-E1 holds even when the user never sees the failure. Then:
 *
 *   - in a before context the dispatcher calls addError on the records, so the save is refused
 *     with a message Maria can act on rather than with a stack trace, and the transaction is
 *     left in the user's hands;
 *   - in an after context there is nothing useful to attach a message to, so the dispatcher
 *     rethrows with the same friendly message, which rolls the transaction back.
 *
 * Either way the original exception is already recorded, so nothing is swallowed.
 */
public with sharing class TriggerDispatcher {
    public class TriggerDispatcherException extends Exception {
    }

    /**
     * The trigger context, passed explicitly so that a handler can be dispatched from a test or
     * from a bulk operation without a real trigger.
     */
    public class Context {
        public System.TriggerOperation operation { get; private set; }
        public List<SObject> newRecords { get; private set; }
        public Map<Id, SObject> newRecordsById { get; private set; }
        public List<SObject> oldRecords { get; private set; }
        public Map<Id, SObject> oldRecordsById { get; private set; }

        public Context(
            System.TriggerOperation operation,
            List<SObject> newRecords,
            Map<Id, SObject> newRecordsById,
            List<SObject> oldRecords,
            Map<Id, SObject> oldRecordsById
        ) {
            this.operation = operation;
            this.newRecords = newRecords;
            this.newRecordsById = newRecordsById;
            this.oldRecords = oldRecords;
            this.oldRecordsById = oldRecordsById;
        }

        public Boolean isBefore() {
            return operation == System.TriggerOperation.BEFORE_INSERT ||
                operation == System.TriggerOperation.BEFORE_UPDATE ||
                operation == System.TriggerOperation.BEFORE_DELETE;
        }
    }

    public static void run(TriggerHandler handler) {
        if (!Trigger.isExecuting) {
            return;
        }
        run(
            handler,
            new Context(
                Trigger.operationType,
                Trigger.new,
                Trigger.newMap,
                Trigger.old,
                Trigger.oldMap
            )
        );
    }

    public static void run(TriggerHandler handler, Context context) {
        if (handler == null || context == null || context.operation == null) {
            return;
        }
        String automationName = handler.getName();
        if (AutomationControl.isBypassed(automationName)) {
            return;
        }
        if (AutomationControl.isPaused()) {
            return;
        }
        if (!AutomationControl.isEnabled(automationName)) {
            return;
        }
        try {
            dispatch(handler, context);
        } catch (Exception caught) {
            ErrorLogger.log(caught, automationName, firstRecordId(context));
            reportToUser(context, caught);
        }
    }

    private static void dispatch(TriggerHandler handler, Context context) {
        switch on context.operation {
            when BEFORE_INSERT {
                handler.beforeInsert(context.newRecords);
            }
            when AFTER_INSERT {
                handler.afterInsert(context.newRecords, context.newRecordsById);
            }
            when BEFORE_UPDATE {
                handler.beforeUpdate(
                    context.newRecords,
                    context.newRecordsById,
                    context.oldRecords,
                    context.oldRecordsById
                );
            }
            when AFTER_UPDATE {
                handler.afterUpdate(
                    context.newRecords,
                    context.newRecordsById,
                    context.oldRecords,
                    context.oldRecordsById
                );
            }
            when BEFORE_DELETE {
                handler.beforeDelete(context.oldRecords, context.oldRecordsById);
            }
            when AFTER_DELETE {
                handler.afterDelete(context.oldRecords, context.oldRecordsById);
            }
            when AFTER_UNDELETE {
                handler.afterUndelete(context.newRecords, context.newRecordsById);
            }
            when else {
                return;
            }
        }
    }

    private static void reportToUser(Context context, Exception caught) {
        List<SObject> targets = null;
        if (context.isBefore()) {
            targets = context.newRecords == null ? context.oldRecords : context.newRecords;
        }
        if (targets != null && !targets.isEmpty() && Trigger.isExecuting) {
            for (SObject record : targets) {
                record.addError(Label.Core_Automation_UnexpectedError);
            }
            return;
        }
        throw new TriggerDispatcherException(Label.Core_Automation_UnexpectedError, caught);
    }

    private static Id firstRecordId(Context context) {
        if (context.newRecordsById != null && !context.newRecordsById.isEmpty()) {
            return new List<Id>(context.newRecordsById.keySet())[0];
        }
        if (context.oldRecordsById != null && !context.oldRecordsById.isEmpty()) {
            return new List<Id>(context.oldRecordsById.keySet())[0];
        }
        return null;
    }
}

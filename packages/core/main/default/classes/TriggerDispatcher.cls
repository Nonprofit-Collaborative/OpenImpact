/**
 * The single entry point every packaged trigger uses.
 *
 * A trigger contains one line, naming its object:
 *
 *     trigger ContactTrigger on Contact (before insert, after insert) {
 *         TriggerDispatcher.run('Contact');
 *     }
 *
 * The dispatcher reads the shipped registry for that object, in execution order, and runs each
 * handler it names (ADR-0017). A module ships its handler class and its registry record and
 * never edits another feature's trigger. The `run(TriggerHandler)` overload stays for tests and
 * for an object with exactly one handler.
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
@NamespaceAccessible
public with sharing class TriggerDispatcher {
    private static String resolvedNamespace;
    private static Boolean namespaceResolved = false;

    @NamespaceAccessible
    public class TriggerDispatcherException extends Exception {
    }

    /**
     * The trigger context, passed explicitly so that a handler can be dispatched from a test or
     * from a bulk operation without a real trigger.
     */
    @NamespaceAccessible
    public class Context {
        public System.TriggerOperation operation { get; private set; }
        public List<SObject> newRecords { get; private set; }
        public Map<Id, SObject> newRecordsById { get; private set; }
        public List<SObject> oldRecords { get; private set; }
        public Map<Id, SObject> oldRecordsById { get; private set; }

        @NamespaceAccessible
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

        @NamespaceAccessible
        public Boolean isBefore() {
            return operation == System.TriggerOperation.BEFORE_INSERT ||
                operation == System.TriggerOperation.BEFORE_UPDATE ||
                operation == System.TriggerOperation.BEFORE_DELETE;
        }
    }

    /**
     * The line a packaged trigger contains: run every automation the registry lists for this
     * object, in execution order.
     */
    @NamespaceAccessible
    public static void run(String objectApiName) {
        if (!Trigger.isExecuting) {
            return;
        }
        run(objectApiName, currentContext());
    }

    @NamespaceAccessible
    public static void run(String objectApiName, Context context) {
        if (String.isBlank(objectApiName) || context == null) {
            return;
        }
        for (
            Automation_Registry__mdt entry : AutomationRegistrySelector.selectForObject(
                objectApiName
            )
        ) {
            TriggerHandler handler = instantiate(entry, objectApiName);
            if (handler != null) {
                run(handler, context, entry.DeveloperName);
            }
        }
    }

    @NamespaceAccessible
    public static void run(TriggerHandler handler) {
        if (!Trigger.isExecuting) {
            return;
        }
        run(handler, currentContext());
    }

    @NamespaceAccessible
    public static void run(TriggerHandler handler, Context context) {
        if (handler == null) {
            return;
        }
        run(handler, context, handler.getName());
    }

    private static Context currentContext() {
        return new Context(
            Trigger.operationType,
            Trigger.new,
            Trigger.newMap,
            Trigger.old,
            Trigger.oldMap
        );
    }

    private static void run(TriggerHandler handler, Context context, String registeredName) {
        if (handler == null || context == null || context.operation == null) {
            return;
        }
        String automationName = String.isBlank(registeredName) ? handler.getName() : registeredName;
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

    /**
     * Builds the handler a registry record names. A handler that cannot be built is skipped with
     * a warning in the Error Log rather than failing the save: one broken automation must not
     * stop a person entering data.
     */
    private static TriggerHandler instantiate(
        Automation_Registry__mdt entry,
        String objectApiName
    ) {
        String className = entry.Handler_Class__c;
        if (String.isBlank(className)) {
            skip(className, objectApiName);
            return null;
        }
        Type handlerType = Type.forName(packageNamespace(), className);
        if (handlerType == null) {
            handlerType = Type.forName(className);
        }
        if (handlerType == null) {
            skip(className, objectApiName);
            return null;
        }
        Object handler;
        try {
            handler = handlerType.newInstance();
        } catch (Exception cannotBuild) {
            skip(className, objectApiName);
            return null;
        }
        if (!(handler instanceof TriggerHandler)) {
            skip(className, objectApiName);
            return null;
        }
        return (TriggerHandler) handler;
    }

    private static void skip(String className, String objectApiName) {
        ErrorLogger.logMessage(
            String.format(
                Label.Core_Automation_HandlerUnavailable,
                new List<String>{ className == null ? '' : className }
            ),
            'Trigger dispatch: ' + objectApiName,
            ErrorLogger.SEVERITY_WARNING
        );
    }

    /**
     * The namespace this package is running under, so that a handler in another package under
     * the same namespace can be found by name. Empty while the namespace is deferred.
     */
    private static String packageNamespace() {
        if (namespaceResolved) {
            return resolvedNamespace;
        }
        String qualifiedName = String.valueOf(new TriggerDispatcher()).substringBefore(':');
        resolvedNamespace = qualifiedName.contains('.') ? qualifiedName.substringBefore('.') : null;
        namespaceResolved = true;
        return resolvedNamespace;
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

/**
 * Relationship__c trigger handler, registered as "Keep both sides of a relationship in step"
 * in the automation registry and dispatched by TriggerDispatcher, so an administrator can
 * switch it off from Nonprofit Settings without touching Setup.
 *
 * Before insert and before update it fills in the reciprocal type and settles the status
 * against the dates, then refuses a relationship that names one person twice or that already
 * exists. After insert and after undelete it gives the relationship its other side. After
 * update it keeps that other side equal to this one. After delete it takes the other side
 * with it.
 *
 * The service stands this automation down by name while it writes the other side, so nothing
 * here runs against the package's own writes. That is the whole recursion story: there is no
 * flag to reason about and no depth counter, because the write never reaches the trigger.
 *
 * Every context method takes no arguments and reads the trigger collections through the
 * accessors on TriggerHandler, which is the contract every packaged handler is written to.
 */
public with sharing class RelationshipTriggerHandler extends TriggerHandler {
    public override void beforeInsert() {
        applyAndValidate((List<Relationship__c>) newRecords(), null);
    }

    public override void beforeUpdate() {
        applyAndValidate((List<Relationship__c>) newRecords(), oldRecordsById());
    }

    public override void afterInsert() {
        ensure((List<Relationship__c>) newRecords(), 'RelationshipTriggerHandler.afterInsert');
    }

    public override void afterUpdate() {
        List<Relationship__c> records = (List<Relationship__c>) newRecords();
        if (records == null || records.isEmpty()) {
            return;
        }
        try {
            RelationshipService.syncReciprocals(records, oldRecordsById());
        } catch (Exception thrown) {
            report(thrown, records, 'RelationshipTriggerHandler.afterUpdate');
        }
    }

    public override void afterDelete() {
        List<Relationship__c> deleted = (List<Relationship__c>) oldRecords();
        if (deleted == null || deleted.isEmpty()) {
            return;
        }
        try {
            RelationshipService.deleteReciprocals(deleted);
        } catch (Exception thrown) {
            report(thrown, deleted, 'RelationshipTriggerHandler.afterDelete');
        }
    }

    public override void afterUndelete() {
        ensure((List<Relationship__c>) newRecords(), 'RelationshipTriggerHandler.afterUndelete');
    }

    private void applyAndValidate(List<Relationship__c> records, Map<Id, SObject> previousById) {
        if (records == null || records.isEmpty()) {
            return;
        }
        try {
            RelationshipDomain.applyDefaults(records, previousById);
            RelationshipDomain.validate(records, previousById);
        } catch (Exception thrown) {
            report(thrown, records, 'RelationshipTriggerHandler.applyAndValidate');
        }
    }

    private void ensure(List<Relationship__c> records, String context) {
        if (records == null || records.isEmpty()) {
            return;
        }
        try {
            RelationshipService.ensureReciprocals(records);
        } catch (Exception thrown) {
            report(thrown, records, context);
        }
    }

    /**
     * The relationship specific message, rather than the dispatcher's general one, so a person
     * reading the error knows which part of the save failed. The exception is recorded in the
     * Error Log first (R-E1).
     *
     * A record that has already been refused by the domain rules is left alone: it carries the
     * message that tells the person what to change, and a second message on the same record
     * would bury it.
     */
    private void report(Exception thrown, List<Relationship__c> records, String context) {
        ErrorLogger.log(thrown, context);
        for (Relationship__c record : records) {
            if (!record.hasErrors()) {
                record.addError(Label.Core_Relationship_SyncFailed);
            }
        }
    }
}

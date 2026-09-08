/**
 * The rules a relationship has to pass, registered as "Check relationships before they are
 * saved" in the automation registry at execution order 10, so it runs before the automation
 * that maintains the other side.
 *
 * It is a separate registry row from the maintenance one on purpose. An administrator who
 * switches the reciprocal maintenance off before a bulk import still gets the duplicate check,
 * the same person check, and the status and date rules, which are the checks that matter most
 * at exactly that moment.
 *
 * Before insert and before update it fills in the reciprocal type and settles the status
 * against the dates, then refuses a relationship that names one person twice, that does not
 * name a person on both sides, or that already exists.
 *
 * The defaults sit here rather than with the maintenance automation because the status and date
 * rule (R-RL5) is one of the rules that has to survive the maintenance being switched off, and
 * because the reciprocal type is a field on the record in front of the person saving it, not
 * something that happens to the other side afterwards.
 *
 * The reciprocal service stands this automation down along with its own while it writes the
 * other side, so the mirror is built already valid rather than validated on the way in, which
 * is the behaviour that held when both halves lived in one handler.
 *
 * Every context method takes no arguments and reads the trigger collections through the
 * accessors on TriggerHandler, which is the contract every packaged handler is written to.
 */
public with sharing class RelationshipValidationHandler extends TriggerHandler {
    public override void beforeInsert() {
        applyAndValidate((List<Relationship__c>) newRecords(), null);
    }

    public override void beforeUpdate() {
        applyAndValidate((List<Relationship__c>) newRecords(), oldRecordsById());
    }

    private void applyAndValidate(List<Relationship__c> records, Map<Id, SObject> previousById) {
        if (records == null || records.isEmpty()) {
            return;
        }
        try {
            RelationshipDomain.applyDefaults(records, previousById);
            RelationshipDomain.validate(records, previousById);
        } catch (Exception thrown) {
            report(thrown, records, 'RelationshipValidationHandler.applyAndValidate');
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

/**
 * Affiliation__c trigger handler, registered as "Keep one primary affiliation per person" in
 * the automation registry and dispatched by TriggerDispatcher, so an administrator can switch
 * it off from Nonprofit Settings without touching Setup.
 *
 * Before insert and before update it settles the status against the dates, takes the primary
 * flag off anything that has ended, and refuses an affiliation that does not name one person
 * and one organization or that covers dates another one already covers. After every context
 * that can change who is primary, including delete and undelete, it settles the primary
 * affiliation of every person involved.
 *
 * Every context method takes no arguments and reads the trigger collections through the
 * accessors on TriggerHandler, which is the contract every packaged handler is written to.
 */
public with sharing class AffiliationTriggerHandler extends TriggerHandler {
    public override void beforeInsert() {
        applyAndValidate((List<Affiliation__c>) newRecords(), null);
    }

    public override void beforeUpdate() {
        applyAndValidate((List<Affiliation__c>) newRecords(), oldRecordsById());
    }

    public override void afterInsert() {
        refresh((List<Affiliation__c>) newRecords(), null, 'AffiliationTriggerHandler.afterInsert');
    }

    public override void afterUpdate() {
        refresh(
            (List<Affiliation__c>) newRecords(),
            (List<Affiliation__c>) oldRecords(),
            'AffiliationTriggerHandler.afterUpdate'
        );
    }

    public override void afterDelete() {
        refresh(null, (List<Affiliation__c>) oldRecords(), 'AffiliationTriggerHandler.afterDelete');
    }

    public override void afterUndelete() {
        refresh(
            (List<Affiliation__c>) newRecords(),
            null,
            'AffiliationTriggerHandler.afterUndelete'
        );
    }

    private void applyAndValidate(List<Affiliation__c> records, Map<Id, SObject> previousById) {
        if (records == null || records.isEmpty()) {
            return;
        }
        try {
            AffiliationDomain.applyDefaults(records, previousById);
            AffiliationDomain.validate(records, previousById);
        } catch (Exception thrown) {
            report(thrown, records, 'AffiliationTriggerHandler.applyAndValidate');
        }
    }

    private void refresh(
        List<Affiliation__c> records,
        List<Affiliation__c> previous,
        String context
    ) {
        Boolean nothingToDo =
            (records == null || records.isEmpty()) && (previous == null || previous.isEmpty());
        if (nothingToDo) {
            return;
        }
        try {
            AffiliationService.refreshPrimaries(records, previous);
        } catch (Exception thrown) {
            report(thrown, records == null || records.isEmpty() ? previous : records, context);
        }
    }

    /**
     * The affiliation specific message, rather than the dispatcher's general one, so a person
     * reading the error knows which part of the save failed. The exception is recorded in the
     * Error Log first (R-E1), and a record already carrying a message that tells the person
     * what to change is left alone.
     */
    private void report(Exception thrown, List<Affiliation__c> records, String context) {
        ErrorLogger.log(thrown, context);
        if (records == null) {
            return;
        }
        for (Affiliation__c record : records) {
            if (!record.hasErrors()) {
                record.addError(Label.Core_Affiliation_PrimaryFailed);
            }
        }
    }
}

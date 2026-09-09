/**
 * Household upkeep when a person changes.
 *
 * A person with no household gets one: before insert in contact mode, where the household
 * is a reference on the contact, and after insert in junction mode, where it is a
 * membership row that needs the person's id. After every change the households the person
 * came from and went to are recounted, renamed, and, when they have been left empty and
 * the org asks for it, deleted.
 */
public with sharing class ContactTriggerHandler extends TriggerHandler {
    public override void beforeInsert() {
        HouseholdService.ensureHouseholds((List<Contact>) Trigger.new);
    }

    public override void afterInsert() {
        // Junction mode first: a person saved into it with no household gets one here,
        // because the membership row that joins them to it needs an id the contact did not
        // have before insert (R-H2, ADR-NEXT). Contact mode did its half before insert.
        HouseholdService.createHouseholdsForNewContacts((List<Contact>) Trigger.new);
        refresh(householdIds((List<Contact>) Trigger.new), false);
    }

    public override void afterUpdate() {
        Map<Id, Contact> previousById = (Map<Id, Contact>) Trigger.oldMap;
        Set<Id> affected = new Set<Id>();
        for (Contact record : (List<Contact>) Trigger.new) {
            Contact previous = previousById.get(record.Id);
            Boolean moved = record.AccountId != previous.AccountId;
            if (moved) {
                add(affected, previous.AccountId);
                add(affected, record.AccountId);
            } else if (namingChanged(record, previous)) {
                add(affected, record.AccountId);
            }
        }
        refresh(affected, true);
    }

    public override void afterDelete() {
        refresh(householdIds((List<Contact>) Trigger.old), true);
    }

    public override void afterUndelete() {
        refresh(householdIds((List<Contact>) Trigger.new), false);
    }

    private static Boolean namingChanged(Contact record, Contact previous) {
        return record.FirstName != previous.FirstName ||
            record.LastName != previous.LastName ||
            record.Salutation != previous.Salutation ||
            record.Preferred_Name__c != previous.Preferred_Name__c ||
            record.Deceased__c != previous.Deceased__c ||
            record.Household_Role__c != previous.Household_Role__c ||
            record.Exclude_From_Household_Name__c != previous.Exclude_From_Household_Name__c ||
            record.Exclude_From_Greetings__c != previous.Exclude_From_Greetings__c;
    }

    private static Set<Id> householdIds(List<Contact> records) {
        Set<Id> result = new Set<Id>();
        for (Contact record : records) {
            add(result, record.AccountId);
        }
        return result;
    }

    private static void add(Set<Id> target, Id value) {
        if (value != null) {
            target.add(value);
        }
    }

    /**
     * One pass over the affected households, done in the one place that upkeep lives.
     */
    private static void refresh(Set<Id> householdIds, Boolean mayDelete) {
        HouseholdService.afterMembershipChange(householdIds, mayDelete);
    }
}

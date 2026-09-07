/**
 * Household upkeep when a person changes.
 *
 * Before insert a person with no household gets one. After every change the households the
 * person came from and went to are recounted, renamed, and, when they have been left empty
 * and the org asks for it, deleted.
 */
public with sharing class ContactTriggerHandler extends TriggerHandler {
    private static Boolean running = false;

    public override void beforeInsert() {
        HouseholdService.ensureHouseholds((List<Contact>) Trigger.new);
    }

    public override void afterInsert() {
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
     * One pass over the affected households. The guard stops the saves this makes from
     * coming back round through another trigger and starting again.
     */
    private static void refresh(Set<Id> householdIds, Boolean mayDelete) {
        if (running || householdIds.isEmpty()) {
            return;
        }
        running = true;
        try {
            HouseholdService.recalculateMemberCounts(householdIds);
            HouseholdNamingService.applyNaming(householdIds);
            if (mayDelete) {
                HouseholdService.deleteEmptyHouseholds(householdIds);
            }
        } finally {
            running = false;
        }
    }
}

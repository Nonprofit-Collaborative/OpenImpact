/**
 * Household upkeep when a household or a person record changes.
 *
 * A new household is never left without a name. When someone clears the custom name box,
 * the household goes back to being named from the org's patterns. In an org that stores
 * people as accounts, a new person gets a household and a membership of it.
 */
public with sharing class AccountTriggerHandler extends TriggerHandler {
    private static Boolean running = false;

    public override void beforeInsert() {
        nameNewHouseholds((List<Account>) Trigger.new);
    }

    public override void beforeUpdate() {
        nameNewHouseholds((List<Account>) Trigger.new);
    }

    public override void afterInsert() {
        createHouseholdsForNewPeople((List<Account>) Trigger.new);
    }

    public override void afterUpdate() {
        Map<Id, Account> previousById = (Map<Id, Account>) Trigger.oldMap;
        Set<Id> released = new Set<Id>();
        for (Account record : (List<Account>) Trigger.new) {
            Account previous = previousById.get(record.Id);
            Boolean wasCustom = previous != null && previous.Custom_Name__c == true;
            if (wasCustom && record.Custom_Name__c != true) {
                released.add(record.Id);
            }
        }
        if (!released.isEmpty()) {
            HouseholdNamingService.applyNaming(released);
        }
    }

    /**
     * A household saved with no name gets a placeholder rather than a save error. The
     * naming service replaces it as soon as the household has a member.
     */
    private static void nameNewHouseholds(List<Account> records) {
        Id recordTypeId = HouseholdService.householdRecordTypeId();
        if (recordTypeId == null) {
            return;
        }
        for (Account record : records) {
            Boolean isHousehold = record.RecordTypeId == recordTypeId;
            if (isHousehold && record.Custom_Name__c != true && String.isBlank(record.Name)) {
                record.Name = Label.Core_Households_NamePlaceholder;
            }
        }
    }

    /**
     * R-H2. Only in an org that stores people as accounts, only in junction mode, and only
     * when automatic household creation is on.
     *
     * That is the same setting a person stored as a contact is given a household by
     * (ADR-NEXT). The separate person account setting this used to read is retired: it
     * shipped off, so an org that took the recommended setup got no households at all and
     * was told nothing about it.
     */
    private static void createHouseholdsForNewPeople(List<Account> records) {
        if (running || records == null || records.isEmpty()) {
            return;
        }
        if (!HouseholdService.isPersonAccountOrg() || !HouseholdService.isJunctionMode()) {
            return;
        }
        Nonprofit_Settings__c settings = SettingsService.getSettings();
        if (settings == null || settings.Auto_Create_Households__c != true) {
            return;
        }
        List<SObject> people = PersonRecordSelector.filterPeople(records);
        if (people.isEmpty()) {
            return;
        }
        running = true;
        try {
            HouseholdService.createHouseholdsForPersonAccounts(people);
        } finally {
            running = false;
        }
    }
}

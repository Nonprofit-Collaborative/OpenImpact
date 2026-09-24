/**
 * The one way a system mode writer saves keys on the org-level Nonprofit Settings record.
 *
 * ADR-0021 and ADR-0027 name the writers that may write this protected setting in system mode
 * (the automation pause, the seasonal swap's run record, the error digest's run record). Each
 * of them used to start from `Nonprofit_Settings__c.getOrgDefaults()` and upsert the whole
 * record, which went wrong in three ways this class exists to prevent:
 *
 * 1. On an org that has never saved its settings, `getOrgDefaults()` reads every checkbox as
 *    false, so the first save stored the features that ship on (ADR-0035) as switched off.
 * 2. Creating the record fills every text default, which confirms a coexistence mode and a
 *    household membership mode nobody chose (SettingsService.blanksKeptBlank).
 * 3. Upserting the whole record wrote back every other key as this transaction first read it,
 *    so a change another person saved in the meantime could be undone.
 *
 * So: when a record exists it is locked and only the given keys are updated; when none exists
 * one is created from the shipped defaults and the blanks are put back. Every value comes from
 * the calling writer, which carries its own authorization (see each writer's header). The class
 * adds no permission of its own and elevates nothing else.
 */
public without sharing class OrgSettingsSystemWriter {
    public static void save(Map<Schema.SObjectField, Object> values) {
        Nonprofit_Settings__c stored = lockStored();
        if (stored != null) {
            Nonprofit_Settings__c changes = new Nonprofit_Settings__c(Id = stored.Id);
            putAll(changes, values);
            Database.update(changes, AccessLevel.SYSTEM_MODE);
        } else {
            Nonprofit_Settings__c created = SettingsService.firstSaveRecord();
            putAll(created, values);
            Database.insert(created, AccessLevel.SYSTEM_MODE);
            Database.update(SettingsService.blanksAfterFirstSave(created), AccessLevel.SYSTEM_MODE);
        }
        SettingsService.clearCache();
    }

    /**
     * The stored org-level record, locked until the transaction ends, or null when the org has
     * never saved one. Read what a decision depends on through this, then `save`, and a second
     * run waits for the first to finish instead of acting on the same stale value.
     */
    public static Nonprofit_Settings__c lockStored() {
        return (Nonprofit_Settings__c) SettingsRecordSelector.lockOrgDefault(
            Nonprofit_Settings__c.SObjectType
        );
    }

    private static void putAll(
        Nonprofit_Settings__c target,
        Map<Schema.SObjectField, Object> values
    ) {
        for (Schema.SObjectField field : values.keySet()) {
            target.put(field, values.get(field));
        }
    }
}

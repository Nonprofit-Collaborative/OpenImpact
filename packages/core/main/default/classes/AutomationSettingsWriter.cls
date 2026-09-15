/**
 * Writes the org default `Nonprofit_Settings__c` record for the automation pause.
 *
 * ADR-0021 (system mode writes for package owned data) is the authority for this class and
 * names it as one of its writers. A protected hierarchy custom setting takes no object or field
 * permissions in a subscriber org: there is no way to grant a Nonprofit Admin field access to
 * it. Writing the pause setting in user mode therefore fails for everyone who is not a system
 * administrator, which is most of the people this feature is for. Running in system mode is what
 * allows `AutomationControl` to honor this choice by a user who holds only the packaged
 * permission sets.
 *
 * It is deliberately small and does one thing. Nothing is read here and nothing is returned, one
 * field is written, and no user input reaches it: the caller passes a datetime it computed from a
 * number of hours it has already validated. The permission is enforced before this class is
 * reached: `AutomationControl` calls it only after `FeatureManagement.checkPermission('Manage_Nonprofit_Settings')` passes. C-03 adds the general settings writer for the rest of
 * the console.
 */
public without sharing class AutomationSettingsWriter {
    public static void savePausedUntil(Datetime pausedUntil) {
        Nonprofit_Settings__c settings = Nonprofit_Settings__c.getOrgDefaults();
        settings.Automation_Paused_Until__c = pausedUntil;
        if (settings.Id == null) {
            Database.insert(settings, AccessLevel.SYSTEM_MODE);
        } else {
            Database.update(settings, AccessLevel.SYSTEM_MODE);
        }
    }
}

/**
 * Writes the org default `Nonprofit_Settings__c` record for the automation pause.
 *
 * DOCUMENTED EXCEPTION to the "user mode DML" rule (plan Section 4.13). A protected hierarchy
 * custom setting takes no object or field permissions in a subscriber org: there is no way to
 * grant a Nonprofit Admin field access to it, so a user mode write fails for everyone who is not a
 * system administrator, which is most of the people this feature is for. The write therefore runs
 * in system mode, and the permission is enforced before this class is reached: `AutomationControl`
 * calls it only after `FeatureManagement.checkPermission('Manage_Nonprofit_Settings')` passes.
 *
 * It is deliberately small and does one thing. Nothing is read here and nothing is returned, one
 * field is written, and no user input reaches it: the caller passes a datetime it computed from a
 * number of hours it has already validated. C-03 adds the general settings writer for the rest of
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

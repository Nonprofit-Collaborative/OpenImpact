/**
 * Records what an error digest run did, on the org-level Nonprofit Settings record (C-23).
 *
 * DOCUMENTED EXCEPTION to the user-mode DML rule (plan Section 7.2), of the kind ADR-0027 added
 * under ADR-0021: a scheduled job's record of its own run. The digest runs as whoever scheduled
 * it, and a protected custom setting takes no field permissions, so no user-mode write can be
 * relied on. The permission gate is where the job starts: `ErrorDigestController` requires
 * `Manage_Nonprofit_Settings` before scheduling the job or sending a digest now.
 *
 * The conditions of ADR-0021 that still apply are met: only three package owned keys are
 * written, every value is produced by `ErrorDigestService` about its own run (two times and one
 * sentence built from labels and counts), and nothing else is elevated. The Setting Change
 * audit is not written for these: they are the job's run record, like the seasonal swap's, not
 * a setting anybody changed.
 */
public without sharing class ErrorDigestWriter {
    public static void recordRun(Datetime ranAt, String summary, Datetime coveredUntil) {
        Nonprofit_Settings__c settings = Nonprofit_Settings__c.getOrgDefaults();
        settings.Error_Digest_Last_Run__c = ranAt;
        settings.Error_Digest_Last_Run_Summary__c = summary == null ? null : summary.left(255);
        settings.Error_Digest_Covered_Until__c = coveredUntil;
        Boolean firstSave = settings.Id == null;
        if (firstSave) {
            settings.SetupOwnerId = UserInfo.getOrganizationId();
        }
        Database.upsert(settings, AccessLevel.SYSTEM_MODE);
        if (firstSave) {
            // Creating the record fills every text default, which would confirm a coexistence
            // mode nobody chose; SettingsService explains why those have to stay blank.
            Database.update(
                SettingsService.blanksAfterFirstSave(settings),
                AccessLevel.SYSTEM_MODE
            );
        }
    }
}

/**
 * The two system mode writes donor levels need, and nothing else (ADR-0021).
 *
 * Both meet that ADR's conditions. The values are computed by package code from a giving total the
 * rollup engine wrote, no user typed text reaches them, and only fields this package owns are
 * written. The reason the writes are elevated is the reason the rollup engine's are: a nightly
 * recalculation must place every donor on the right rung whether or not the user the job happens
 * to run as can see them, and a level that silently stopped being maintained for some records
 * would be worse than no levels at all.
 *
 * Real time assignment is not here. It happens in a before trigger, where the platform writes the
 * values with the save the user already authorized, so it needs no elevation and no second DML.
 */
public without sharing class DonorLevelWriter {
    /** Saves records a recalculation moved between levels. */
    public static void save(List<SObject> moved) {
        if (moved == null || moved.isEmpty()) {
            return;
        }
        Database.update(moved, true, AccessLevel.SYSTEM_MODE);
    }

    /**
     * Stamps when a recalculation finished, the freshness promise the rollups make (Principle 2).
     */
    public static void stampRecalculation(Datetime completedAt) {
        Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
        settings.Donor_Levels_Last_Recalculated__c = completedAt;
        List<Giving_Settings__c> records = new List<Giving_Settings__c>{ settings };
        if (settings.Id == null) {
            settings.SetupOwnerId = UserInfo.getOrganizationId();
            Database.insert(records, true, AccessLevel.SYSTEM_MODE);
        } else {
            Database.update(records, true, AccessLevel.SYSTEM_MODE);
        }
        SettingsService.clearCaches();
    }
}

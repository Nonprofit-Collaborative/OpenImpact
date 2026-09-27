/**
 * The one way Connect saves a run record on its protected org-level settings in system mode: the
 * last completed run and its summary of the Opportunity mirror (R-OM8) and of the Gift
 * Transaction mirror (R-GT5), in the shape of ADR-0038 point 4, read by each mirror's page and by
 * Health Check.
 *
 * A run executes as the administrator who started or scheduled it, and Connect Settings is a
 * protected setting nobody edits outside the Nonprofit Settings console, so the run cannot save
 * it in user mode. Only the two run keys of the one mirror are written: when a record exists it is
 * locked and only they are updated, so a direction or start date saved meanwhile, or the other
 * mirror's run, is never undone; when none exists one is created from the field defaults. The
 * caller carries the authorization (a run it started); this class adds no permission of its own.
 */
public without sharing class ConnectSettingsWriter {
    public static void recordOpportunityMirrorRun(Datetime ranAt, String summary) {
        record(
            Connect_Settings__c.Opportunity_Mirror_Last_Run__c,
            Connect_Settings__c.Opportunity_Mirror_Last_Summary__c,
            ranAt,
            summary
        );
    }

    public static void recordGiftTransactionMirrorRun(Datetime ranAt, String summary) {
        record(
            Connect_Settings__c.Gift_Transaction_Mirror_Last_Run__c,
            Connect_Settings__c.Gift_Transaction_Mirror_Last_Summary__c,
            ranAt,
            summary
        );
    }

    private static void record(
        Schema.SObjectField runField,
        Schema.SObjectField summaryField,
        Datetime ranAt,
        String summary
    ) {
        String kept = summary == null ? null : summary.left(255);
        Id stored = lockStored();
        if (stored == null) {
            Connect_Settings__c created = (Connect_Settings__c) Connect_Settings__c.SObjectType.newSObject(
                null,
                true
            );
            created.SetupOwnerId = UserInfo.getOrganizationId();
            created.put(runField, ranAt);
            created.put(summaryField, kept);
            try {
                Database.insert(created, AccessLevel.SYSTEM_MODE);
                return;
            } catch (DmlException collided) {
                if (collided.getDmlType(0) != StatusCode.DUPLICATE_VALUE) {
                    throw collided;
                }
                // Someone saved the settings for the first time in the meantime: update theirs.
                stored = lockStored();
            }
        }
        Connect_Settings__c keys = new Connect_Settings__c(Id = stored);
        keys.put(runField, ranAt);
        keys.put(summaryField, kept);
        Database.update(keys, AccessLevel.SYSTEM_MODE);
    }

    /** The org-level record's Id, locked until the transaction ends, or null when none exists. */
    private static Id lockStored() {
        Id org = UserInfo.getOrganizationId();
        List<Connect_Settings__c> stored = [
            SELECT Id
            FROM Connect_Settings__c
            WHERE SetupOwnerId = :org
            WITH SYSTEM_MODE
            LIMIT 1
            FOR UPDATE
        ];
        return stored.isEmpty() ? null : stored[0].Id;
    }
}

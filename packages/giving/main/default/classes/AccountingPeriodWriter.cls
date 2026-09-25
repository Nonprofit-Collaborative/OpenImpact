/**
 * The one write that sets Books Closed Through, and nothing else.
 *
 * DOCUMENTED EXCEPTION to the "user mode DML" rule (plan Section 4.13), under ADR-0021 and for
 * the reason `SettingsWriter` gives (ADR-0006, ADR-0017): `Giving_Settings__c` is a protected
 * custom setting, so no packaged permission set can grant a subscriber user access to it and a
 * user mode write is refused for everyone who is not a system administrator.
 *
 * The four ADR-0021 conditions:
 *
 * 1. **Permission enforced before this class is reached.** `AccountingPeriodController` checks
 *    Manage Nonprofit Settings, and Override Posting Lock for a date that reopens a period,
 *    before its only call here.
 * 2. **Inputs validated by the caller.** The date is typed as a Date and checked to be before
 *    today; no text reaches this class.
 * 3. **Only package owned fields.** One field on the Giving settings org default.
 * 4. **Reads that reach a user stay in user mode.** There are no reads here beyond the org
 *    default this class writes back.
 */
public with sharing class AccountingPeriodWriter {
    public static void saveClosedThrough(Date closeDate) {
        Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
        settings.Books_Closed_Through__c = closeDate;
        if (settings.Id == null) {
            settings.SetupOwnerId = UserInfo.getOrganizationId();
        }
        Database.upsert(settings, true, AccessLevel.SYSTEM_MODE);
        SettingsService.clearCaches();
    }
}

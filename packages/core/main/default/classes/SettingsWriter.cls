/**
 * Writes the org-level record of a protected hierarchy custom setting.
 *
 * DOCUMENTED EXCEPTION to the user-mode DML rule (plan Section 7.2, and the reason is recorded
 * in ADR-0006 decision 1 and ADR-0017). Settings objects are protected components of a managed
 * package. Protected components are not visible in a subscriber org, so a packaged permission
 * set cannot grant a subscriber user object or field access on them, and a user-mode write is
 * refused for every user who is not an administrator. That contradicts plan Section 2.3, which
 * says any user with the `Manage Nonprofit Settings` custom permission may change settings.
 *
 * So the write runs in system mode, and the permission is the gate instead of the object
 * permission. Three things hold at every call:
 *
 * 1. `FeatureManagement.checkPermission` is re-checked here, not only in the controller, so no
 *    caller can reach the write without the permission.
 * 2. Only fields that exist on the settings object and are named by a shipped Setting Definition
 *    row have been put on the record, and their values have already been coerced and range
 *    checked by `SettingsService`.
 * 3. Nothing else is written in system mode. The `Setting_Change__c` audit records are a normal
 *    custom object and stay in user mode, so an org that has locked audit records down keeps
 *    that control.
 *
 * Reads are unaffected and stay as they were.
 */
public with sharing class SettingsWriter {
    @TestVisible
    private static final String EDIT_PERMISSION = 'Manage_Nonprofit_Settings';

    /** Raised when a caller reaches the write without the Manage Nonprofit Settings permission. */
    public class PermissionException extends Exception {
    }

    /**
     * Saves the org-level settings record. The caller has already validated every value on it.
     */
    public static void saveOrgDefault(SObject record) {
        if (record == null) {
            return;
        }
        if (!FeatureManagement.checkPermission(EDIT_PERMISSION)) {
            throw new PermissionException(System.Label.Core_Settings_PermissionRequiredError);
        }
        Database.upsert(record, AccessLevel.SYSTEM_MODE);
    }
}

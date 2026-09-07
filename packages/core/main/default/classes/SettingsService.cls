/**
 * Reads the org's Nonprofit Settings and records every change to a setting.
 *
 * This is the minimal v0.1 accessor that C-04 needs. Feature C-03 extends it with the settings
 * console's write path, platform cache invalidation, and the rest of the keys.
 *
 * The two mode keys are text rather than picklists, because the platform does not allow a
 * picklist on a custom setting (ADR-0014). This class holds their allowed values, validates a
 * write, and treats an unrecognized stored value as the shipped default rather than failing.
 */
@NamespaceAccessible
public with sharing class SettingsService {
    @NamespaceAccessible
    public static final String COEXISTENCE_MODE_DEFAULT = 'Standalone';
    @NamespaceAccessible
    public static final String MEMBERSHIP_MODE_DEFAULT = 'Contact';

    private static final Set<String> COEXISTENCE_MODES = new Set<String>{
        'Standalone',
        'NPSP',
        'AgentforceNonprofit'
    };
    private static final Set<String> MEMBERSHIP_MODES = new Set<String>{ 'Contact', 'Junction' };

    private static Nonprofit_Settings__c cachedSettings;

    @NamespaceAccessible
    public class SettingsServiceException extends Exception {
    }

    /**
     * The org level settings, read once per transaction.
     */
    @NamespaceAccessible
    public static Nonprofit_Settings__c getSettings() {
        if (cachedSettings == null) {
            cachedSettings = Nonprofit_Settings__c.getOrgDefaults();
        }
        return cachedSettings;
    }

    /**
     * A fresh copy of the org level settings to write to. Never the cached instance, so that a
     * failed write cannot leave a half-changed value in this transaction's cache.
     */
    @NamespaceAccessible
    public static Nonprofit_Settings__c getSettingsForUpdate() {
        return Nonprofit_Settings__c.getOrgDefaults();
    }

    @NamespaceAccessible
    public static void clearCache() {
        cachedSettings = null;
    }

    @NamespaceAccessible
    public static Set<String> coexistenceModes() {
        return COEXISTENCE_MODES.clone();
    }

    @NamespaceAccessible
    public static Set<String> membershipModes() {
        return MEMBERSHIP_MODES.clone();
    }

    @NamespaceAccessible
    public static String coexistenceMode() {
        return storedOrDefault(
            getSettings().Coexistence_Mode__c,
            COEXISTENCE_MODES,
            COEXISTENCE_MODE_DEFAULT
        );
    }

    @NamespaceAccessible
    public static String householdMembershipMode() {
        return storedOrDefault(
            getSettings().Household_Membership_Mode__c,
            MEMBERSHIP_MODES,
            MEMBERSHIP_MODE_DEFAULT
        );
    }

    /**
     * Checks a value on its way in. Anything outside the allowed list is refused with a message
     * the console can show.
     */
    @NamespaceAccessible
    public static String validated(String value, Set<String> allowed) {
        if (allowed == null || String.isBlank(value) || !allowed.contains(value)) {
            throw new SettingsServiceException(Label.Core_Settings_ModeValueInvalid);
        }
        return value;
    }

    /**
     * Writes one audit row. Callers write a row only when a value actually changed (rule R-S1).
     */
    @NamespaceAccessible
    public static void logChange(String settingName, String oldValue, String newValue) {
        if (String.isBlank(settingName)) {
            return;
        }
        Setting_Change__c change = new Setting_Change__c(
            Setting_Name__c = settingName.left(255),
            Old_Value__c = oldValue,
            New_Value__c = newValue,
            Changed_By__c = UserInfo.getUserId(),
            Changed_At__c = System.now()
        );
        Database.insert(change, AccessLevel.USER_MODE);
    }

    private static String storedOrDefault(String stored, Set<String> allowed, String fallback) {
        return String.isNotBlank(stored) && allowed.contains(stored) ? stored : fallback;
    }
}

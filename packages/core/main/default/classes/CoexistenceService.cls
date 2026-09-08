/**
 * The org's coexistence mode: how Open Impact behaves next to whatever is already installed
 * (plan Section 4.5). One org-level setting, proposed by detection and confirmed by an
 * administrator, changeable at any time.
 *
 * Every write goes through SettingsService so that it is cached, invalidated, and audited
 * the same way as every other setting (canonical model Section 12).
 */
@NamespaceAccessible
public with sharing class CoexistenceService {
    public static final String MODE_STANDALONE = 'Standalone';
    public static final String MODE_NPSP = 'NPSP';
    public static final String MODE_AGENTFORCE_NONPROFIT = 'AgentforceNonprofit';

    public static final String MEMBERSHIP_CONTACT = 'Contact';
    public static final String MEMBERSHIP_JUNCTION = 'Junction';

    public static final String KEY_COEXISTENCE_MODE = 'Coexistence_Mode__c';
    public static final String KEY_MEMBERSHIP_MODE = 'Household_Membership_Mode__c';

    /** The custom permission that gates changing the mode. */
    public static final String MANAGE_SETTINGS = 'Manage_Nonprofit_Settings';

    private static final Set<String> VALID_MODES = new Set<String>{
        MODE_STANDALONE,
        MODE_NPSP,
        MODE_AGENTFORCE_NONPROFIT
    };

    /**
     * The mode this org is running in, or null when nobody has confirmed one yet.
     */
    public static String getCurrentMode() {
        Nonprofit_Settings__c settings = SettingsService.getSettings();
        String mode = settings == null ? null : settings.Coexistence_Mode__c;
        return String.isBlank(mode) ? null : mode;
    }

    /**
     * How household membership is stored, defaulting to contact mode when unset.
     */
    public static String getMembershipMode() {
        Nonprofit_Settings__c settings = SettingsService.getSettings();
        String mode = settings == null ? null : settings.Household_Membership_Mode__c;
        return String.isBlank(mode) ? MEMBERSHIP_CONTACT : mode;
    }

    /**
     * Set the mode from detection, but only when the org has not chosen one. An
     * administrator's choice is never overwritten. Returns the mode in force afterward.
     *
     * Agentforce Nonprofit implies junction membership: in a Person Accounts org the person
     * is an account, so contact mode cannot express a household. The two values are written
     * together, in one save, so the org is never briefly in an impossible state.
     */
    public static String applyRecommendedIfUnset() {
        String current = getCurrentMode();
        if (String.isNotBlank(current)) {
            return current;
        }

        String recommended = OrgShapeDetector.recommendedCoexistenceMode();
        Map<String, Object> values = new Map<String, Object>{ KEY_COEXISTENCE_MODE => recommended };
        if (MODE_AGENTFORCE_NONPROFIT.equals(recommended)) {
            values.put(KEY_MEMBERSHIP_MODE, MEMBERSHIP_JUNCTION);
        }
        SettingsService.saveValues(values);
        return recommended;
    }

    /**
     * Set the mode explicitly, as the settings console and Health Check do.
     */
    public static void setMode(String mode) {
        if (String.isBlank(mode) || !VALID_MODES.contains(mode)) {
            throw new CoexistenceException(
                String.format(
                    System.Label.Core_CoexistenceMode_InvalidMode,
                    new List<Object>{ mode }
                )
            );
        }

        Map<String, Object> values = new Map<String, Object>{ KEY_COEXISTENCE_MODE => mode };
        if (MODE_AGENTFORCE_NONPROFIT.equals(mode)) {
            values.put(KEY_MEMBERSHIP_MODE, MEMBERSHIP_JUNCTION);
        }
        SettingsService.saveValues(values);
    }

    /**
     * Move household membership to the junction, which is what Person Accounts require.
     * Existing households are not touched: this changes how the next one is built.
     */
    public static void applyJunctionMembership() {
        SettingsService.saveValues(
            new Map<String, Object>{ KEY_MEMBERSHIP_MODE => MEMBERSHIP_JUNCTION }
        );
    }

    /**
     * Change the mode on behalf of the person asking, which is what the settings console and
     * Health Check do. Unlike setMode, this refuses anyone without the Manage Nonprofit
     * Settings permission: the coexistence mode governs how the whole package behaves, so it
     * is an administrator's decision even where the calling code forgot to say so.
     *
     * Agentforce Nonprofit brings junction household membership with it, in the same audited
     * save, because in a Person Accounts org the person is an account and contact membership
     * cannot express a household.
     */
    @NamespaceAccessible
    public static void applyMode(String mode) {
        if (!FeatureManagement.checkPermission(MANAGE_SETTINGS)) {
            throw new CoexistenceException(System.Label.Core_HealthCheck_PermissionRequired);
        }
        setMode(mode);
    }

    /** Raised when a value that is not a coexistence mode is offered as one. */
    public class CoexistenceException extends Exception {
    }
}

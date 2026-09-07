/**
 * The on and off switches behind the Automation page of the Nonprofit Settings console.
 *
 * Three separate mechanisms, in the order the dispatcher applies them:
 *
 *   1. a per transaction bypass, for tests and for internal bulk operations that deliberately
 *      run without a handler;
 *   2. the org wide pause, held as a datetime on Nonprofit Settings, so it expires by itself;
 *   3. the per automation switch, held as a row per automation on Automation Setting.
 *
 * An automation with no row yet still runs. That matters on upgrade: a newly shipped automation
 * works from the moment it is installed, and `ensureDefaults` materializes its row without ever
 * touching a row the administrator already has (Decision D-06, rule R-A2).
 */
public with sharing class AutomationControl {
    public static final String PAUSE_SETTING_NAME = 'Automation Paused Until';

    private static final Set<Integer> ALLOWED_PAUSE_HOURS = new Set<Integer>{ 1, 2, 4, 8, 24 };
    private static final Set<String> BYPASSED_NAMES = new Set<String>();

    private static Map<String, Boolean> enabledByName;

    @TestVisible
    private static List<Automation_Registry__mdt> registryOverride;

    public class AutomationControlException extends Exception {
    }

    public static Set<Integer> allowedPauseHours() {
        return ALLOWED_PAUSE_HOURS.clone();
    }

    // ------------------------------------------------------------------ per automation switch

    public static Boolean isEnabled(String automationName) {
        if (String.isBlank(automationName)) {
            return false;
        }
        if (enabledByName == null) {
            loadEnabledCache();
        }
        Boolean enabled = enabledByName.get(automationName.toLowerCase());
        return enabled == null ? true : enabled;
    }

    /**
     * Switches one automation on or off and records the change. Saving the value it already has
     * writes nothing (rule R-S1).
     */
    public static void setEnabled(String automationName, Boolean enabled) {
        if (String.isBlank(automationName)) {
            throw new AutomationControlException(Label.Core_Automation_NameRequired);
        }
        List<Automation_Setting__c> matches = AutomationSettingSelector.selectByNames(
            new Set<String>{ automationName }
        );
        if (matches.isEmpty()) {
            throw new AutomationControlException(Label.Core_Automation_NotFound);
        }
        Boolean target = enabled == true;
        Automation_Setting__c setting = matches[0];
        Boolean previous = setting.Enabled__c;
        if (previous == target) {
            return;
        }
        setting.Enabled__c = target;
        Database.update(setting, AccessLevel.USER_MODE);
        clearCache();
        SettingsService.logChange(
            'Automation: ' + setting.Automation_Name__c,
            String.valueOf(previous),
            String.valueOf(target)
        );
    }

    public static void clearCache() {
        enabledByName = null;
    }

    // -------------------------------------------------------------------------- global pause

    public static Boolean isPaused() {
        return pausedUntil() != null;
    }

    /**
     * When the current pause ends, or null when automation is running.
     */
    public static Datetime pausedUntil() {
        Nonprofit_Settings__c settings = SettingsService.getSettings();
        if (settings == null || settings.Automation_Paused_Until__c == null) {
            return null;
        }
        return settings.Automation_Paused_Until__c > System.now()
            ? settings.Automation_Paused_Until__c
            : null;
    }

    public static Datetime pauseAll(Integer hours) {
        if (hours == null || !ALLOWED_PAUSE_HOURS.contains(hours)) {
            throw new AutomationControlException(Label.Core_Automation_PauseHoursInvalid);
        }
        return writePausedUntil(System.now().addHours(hours));
    }

    public static void resumeAll() {
        writePausedUntil(null);
    }

    private static Datetime writePausedUntil(Datetime until) {
        Nonprofit_Settings__c settings = SettingsService.getSettingsForUpdate();
        Datetime previous = settings.Automation_Paused_Until__c;
        settings.Automation_Paused_Until__c = until;
        if (settings.Id == null) {
            Database.insert(settings, AccessLevel.USER_MODE);
        } else {
            Database.update(settings, AccessLevel.USER_MODE);
        }
        SettingsService.clearCache();
        SettingsService.logChange(
            PAUSE_SETTING_NAME,
            previous == null ? '' : String.valueOf(previous),
            until == null ? '' : String.valueOf(until)
        );
        return until;
    }

    // -------------------------------------------------------------------- per transaction bypass

    public static void bypass(String automationName) {
        if (String.isNotBlank(automationName)) {
            BYPASSED_NAMES.add(automationName.toLowerCase());
        }
    }

    public static void clearBypass(String automationName) {
        if (String.isNotBlank(automationName)) {
            BYPASSED_NAMES.remove(automationName.toLowerCase());
        }
    }

    public static void clearAllBypasses() {
        BYPASSED_NAMES.clear();
    }

    public static Boolean isBypassed(String automationName) {
        return String.isNotBlank(automationName) &&
            BYPASSED_NAMES.contains(automationName.toLowerCase());
    }

    // ------------------------------------------------------------------------ materialization

    /**
     * Creates an Automation Setting row for every shipped automation that does not have one yet,
     * and leaves every existing row exactly as the administrator left it. Safe to call on every
     * install, every upgrade, and twice in a row. Returns how many rows it created.
     */
    public static Integer ensureDefaults() {
        List<Automation_Registry__mdt> registry = shippedRegistry();
        if (registry.isEmpty()) {
            return 0;
        }
        Set<String> existingNames = new Set<String>();
        for (Automation_Setting__c setting : AutomationSettingSelector.selectAllForFramework()) {
            if (String.isNotBlank(setting.Automation_Name__c)) {
                existingNames.add(setting.Automation_Name__c.toLowerCase());
            }
        }
        List<Automation_Setting__c> toCreate = new List<Automation_Setting__c>();
        for (Automation_Registry__mdt entry : registry) {
            if (
                String.isBlank(entry.DeveloperName) ||
                existingNames.contains(entry.DeveloperName.toLowerCase())
            ) {
                continue;
            }
            existingNames.add(entry.DeveloperName.toLowerCase());
            toCreate.add(
                new Automation_Setting__c(
                    Name = String.isBlank(entry.MasterLabel)
                        ? entry.DeveloperName
                        : entry.MasterLabel,
                    Automation_Name__c = entry.DeveloperName,
                    Description__c = entry.Description__c,
                    Enabled__c = entry.Enabled_By_Default__c == true,
                    Handler_Class__c = entry.Handler_Class__c,
                    Object_Name__c = entry.Object_Name__c,
                    Execution_Order__c = entry.Execution_Order__c,
                    Is_Package_Default__c = true
                )
            );
        }
        if (toCreate.isEmpty()) {
            return 0;
        }
        Database.insert(toCreate, AccessLevel.USER_MODE);
        clearCache();
        return toCreate.size();
    }

    private static List<Automation_Registry__mdt> shippedRegistry() {
        return registryOverride == null ? AutomationRegistrySelector.selectAll() : registryOverride;
    }

    private static void loadEnabledCache() {
        enabledByName = new Map<String, Boolean>();
        for (Automation_Setting__c setting : AutomationSettingSelector.selectAllForFramework()) {
            if (String.isNotBlank(setting.Automation_Name__c)) {
                enabledByName.put(setting.Automation_Name__c.toLowerCase(), setting.Enabled__c);
            }
        }
    }
}

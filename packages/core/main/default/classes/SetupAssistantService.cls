/**
 * The eight step setup checklist Maria works through on the Hub home page (plan Section
 * 4.8). It defines the steps, says whether each one can be done in this org yet, how each
 * one finishes, and remembers where Maria got to, so that closing the browser in the middle
 * of step four opens on step four tomorrow.
 *
 * A step is finished when the administrator finishes it, or when the setting that step
 * exists to fill in already has a value. A step can also be skipped, which moves it out of
 * the way without counting as done, so that step three can wait for the Giving module.
 */
public with sharing class SetupAssistantService {
    /** Where a step is carried out: a section of the settings console, or Salesforce Setup. */
    public static final String TARGET_SETTINGS = 'Settings';
    public static final String TARGET_SETUP = 'Setup';

    /** How a step finishes: by a setting getting a value, or by Maria finishing the panel. */
    public static final String RULE_SETTING = 'Setting';
    public static final String RULE_ACTION = 'Action';

    /** The coexistence modes, as plan Section 4.5 names them. */
    public static final String MODE_STANDALONE = 'Standalone';
    public static final String MODE_NPSP = 'NPSP';
    public static final String MODE_AGENTFORCE = 'AgentforceNonprofit';

    /** What detection found, in the order the assistant leads with. */
    public static final String SHAPE_PERSON_ACCOUNTS = 'PersonAccounts';
    public static final String SHAPE_NPSP = 'Npsp';
    public static final String SHAPE_FRESH = 'Fresh';

    private static final String PROGRESS_KEY = 'Setup_Steps_Completed__c';
    private static final String SKIPPED_KEY = 'Setup_Steps_Skipped__c';
    private static final String STARTED_KEY = 'Setup_Started_At__c';
    private static final Integer PROGRESS_LENGTH = 255;

    /** The org shape used instead of detection, so that tests can run the Person Accounts path. */
    @TestVisible
    private static OrgShapeDetector.OrgShape stubbedShape;

    /** Raised when a step key is not one of the eight the package ships. */
    public class SetupStepException extends Exception {
    }

    /** One step of the setup checklist, as the Hub home page renders it. */
    public class Step {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public Integer position;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public String targetType;
        @AuraEnabled
        public String target;
        @AuraEnabled
        public String setupPath;
        @AuraEnabled
        public String completionSettingKey;
        @AuraEnabled
        public String completionRule;
        @AuraEnabled
        public Boolean isAvailable;
        @AuraEnabled
        public Boolean skipped;
        /** True when the step is finished. The Hub checklist has called this `completed` since C-03. */
        @AuraEnabled
        public Boolean completed;
    }

    /** The shipped steps, in order, each carrying whether it is finished, skipped, and possible yet. */
    public static List<Step> getSteps() {
        Set<String> marked = keysIn(PROGRESS_KEY);
        Set<String> skipped = keysIn(SKIPPED_KEY);
        Boolean givingPresent = ModuleDetectionService.isGivingPresent();
        List<Step> steps = definitions();
        for (Step step : steps) {
            step.completed = marked.contains(step.key) || hasValue(step.completionSettingKey);
            step.skipped = skipped.contains(step.key) && !step.completed;
            step.isAvailable = step.key == 'funddefaults' ? givingPresent : true;
        }
        return steps;
    }

    /** How many of the steps are finished. */
    public static Integer countCompleted(List<Step> steps) {
        Integer done = 0;
        for (Step step : steps) {
            if (step.completed == true) {
                done++;
            }
        }
        return done;
    }

    public static List<Step> markComplete(String stepKey) {
        ensureStarted();
        return setMembership(PROGRESS_KEY, stepKey, true);
    }

    public static List<Step> markIncomplete(String stepKey) {
        return setMembership(PROGRESS_KEY, stepKey, false);
    }

    /** Moves a step out of the way without counting it done, so the assistant offers it again. */
    public static List<Step> markSkipped(String stepKey) {
        ensureStarted();
        return setMembership(SKIPPED_KEY, stepKey, true);
    }

    /** Puts every step back on the list and forgets when setup started, so it can be run again. */
    public static List<Step> reset() {
        SettingsService.saveSystemValue(PROGRESS_KEY, '');
        SettingsService.saveSystemValue(SKIPPED_KEY, '');
        SettingsService.saveSystemValue(STARTED_KEY, null);
        return getSteps();
    }

    /** Records when Maria first changed something, so the completion screen can say how long setup took. */
    public static void ensureStarted() {
        if (getStartedAt() == null) {
            SettingsService.saveSystemValue(STARTED_KEY, System.now());
        }
    }

    /** When setup was first touched, or null when nothing has been done yet. */
    public static Datetime getStartedAt() {
        if (!SettingsService.hasKey(STARTED_KEY)) {
            return null;
        }
        Object value = SettingsService.getValue(STARTED_KEY);
        return value instanceof Datetime ? (Datetime) value : null;
    }

    /** How many whole minutes setup has taken so far, or null when it has not started. */
    public static Integer elapsedMinutes() {
        Datetime startedAt = getStartedAt();
        if (startedAt == null) {
            return null;
        }
        Long milliseconds = System.now().getTime() - startedAt.getTime();
        return milliseconds < 0 ? 0 : (Integer) (milliseconds / 60000);
    }

    /** What detection found in this org, as one of the shape constants. */
    public static String detectedShape() {
        OrgShapeDetector.OrgShape shape = orgShape();
        if (shape == null) {
            return SHAPE_FRESH;
        }
        if (shape.hasPersonAccounts == true || shape.hasIndustriesNonprofit == true) {
            return SHAPE_PERSON_ACCOUNTS;
        }
        return shape.hasNpsp == true ? SHAPE_NPSP : SHAPE_FRESH;
    }

    /** The coexistence mode the assistant recommends for what detection found (plan Section 4.5). */
    public static String recommendedMode() {
        String shape = detectedShape();
        if (shape == SHAPE_PERSON_ACCOUNTS) {
            return MODE_AGENTFORCE;
        }
        return shape == SHAPE_NPSP ? MODE_NPSP : MODE_STANDALONE;
    }

    /** The three modes, so the page can offer a different one than the recommendation. */
    public static List<String> modes() {
        return new List<String>{ MODE_STANDALONE, MODE_NPSP, MODE_AGENTFORCE };
    }

    private static OrgShapeDetector.OrgShape orgShape() {
        if (stubbedShape != null) {
            return stubbedShape;
        }
        try {
            return OrgShapeDetector.detect();
        } catch (Exception e) {
            ErrorLogger.log(e, 'Setup Assistant org shape');
            return null;
        }
    }

    private static List<Step> setMembership(String settingKey, String stepKey, Boolean member) {
        String key = stepKey == null ? '' : stepKey.trim();
        if (!keys().contains(key)) {
            throw new SetupStepException(System.Label.Core_SetupAssistant_UnknownStepError);
        }
        Set<String> current = keysIn(settingKey);
        if (member) {
            current.add(key);
        } else {
            current.remove(key);
        }
        List<String> ordered = new List<String>();
        for (Step step : definitions()) {
            if (current.contains(step.key)) {
                ordered.add(step.key);
            }
        }
        String joined = String.join(ordered, ',');
        if (joined.length() > PROGRESS_LENGTH) {
            joined = joined.substring(0, PROGRESS_LENGTH);
        }
        SettingsService.saveSystemValue(settingKey, joined);
        return getSteps();
    }

    private static Set<String> keysIn(String settingKey) {
        Set<String> stored = new Set<String>();
        if (!SettingsService.hasKey(settingKey)) {
            return stored;
        }
        String value = SettingsService.asText(SettingsService.getValue(settingKey));
        for (String part : value.split(',')) {
            String trimmed = part.trim();
            if (String.isNotBlank(trimmed)) {
                stored.add(trimmed);
            }
        }
        return stored;
    }

    private static Boolean hasValue(String settingKey) {
        if (String.isBlank(settingKey) || !SettingsService.hasKey(settingKey)) {
            return false;
        }
        return String.isNotBlank(SettingsService.asText(SettingsService.getValue(settingKey)));
    }

    private static Set<String> keys() {
        Set<String> keys = new Set<String>();
        for (Step step : definitions()) {
            keys.add(step.key);
        }
        return keys;
    }

    private static List<Step> definitions() {
        List<Step> steps = new List<Step>();
        steps.add(
            build(
                'coexistence',
                1,
                System.Label.Core_SetupAssistant_Step1Label,
                System.Label.Core_SetupAssistant_Step1Description,
                TARGET_SETTINGS,
                SettingSections.GENERAL,
                null,
                'Coexistence_Mode__c',
                RULE_SETTING
            )
        );
        steps.add(
            build(
                'naming',
                2,
                System.Label.Core_SetupAssistant_Step2Label,
                System.Label.Core_SetupAssistant_Step2Description,
                TARGET_SETTINGS,
                SettingSections.HOUSEHOLDS,
                null,
                'Household_Name_Pattern__c',
                RULE_SETTING
            )
        );
        steps.add(
            build(
                'funddefaults',
                3,
                System.Label.Core_SetupAssistant_Step3Label,
                System.Label.Core_SetupAssistant_Step3Description,
                TARGET_SETTINGS,
                SettingSections.GIVING,
                null,
                'Default_Fund__c',
                RULE_SETTING
            )
        );
        steps.add(
            build(
                'access',
                4,
                System.Label.Core_SetupAssistant_Step4Label,
                System.Label.Core_SetupAssistant_Step4Description,
                TARGET_SETTINGS,
                SettingSections.ACCESS,
                '/lightning/setup/ManageUsers/home',
                null,
                RULE_ACTION
            )
        );
        steps.add(
            build(
                'identity',
                5,
                System.Label.Core_SetupAssistant_Step5Label,
                System.Label.Core_SetupAssistant_Step5Description,
                TARGET_SETTINGS,
                SettingSections.ORGANIZATION,
                null,
                'Organization_Legal_Name__c',
                RULE_SETTING
            )
        );
        steps.add(
            build(
                'modules',
                6,
                System.Label.Core_SetupAssistant_Step6Label,
                System.Label.Core_SetupAssistant_Step6Description,
                TARGET_SETTINGS,
                SettingSections.GENERAL,
                null,
                null,
                RULE_ACTION
            )
        );
        steps.add(
            build(
                'data',
                7,
                System.Label.Core_SetupAssistant_Step7Label,
                System.Label.Core_SetupAssistant_Step7Description,
                TARGET_SETTINGS,
                SettingSections.IMPORTING,
                null,
                null,
                RULE_ACTION
            )
        );
        steps.add(
            build(
                'verify',
                8,
                System.Label.Core_SetupAssistant_Step8Label,
                System.Label.Core_SetupAssistant_Step8Description,
                TARGET_SETTINGS,
                SettingSections.HEALTH,
                null,
                null,
                RULE_ACTION
            )
        );
        return steps;
    }

    private static Step build(
        String key,
        Integer position,
        String label,
        String description,
        String targetType,
        String target,
        String setupPath,
        String completionSettingKey,
        String completionRule
    ) {
        Step step = new Step();
        step.key = key;
        step.position = position;
        step.label = label;
        step.description = description;
        step.targetType = targetType;
        step.target = target;
        step.setupPath = setupPath;
        step.completionSettingKey = completionSettingKey;
        step.completionRule = completionRule;
        step.isAvailable = true;
        step.skipped = false;
        step.completed = false;
        return step;
    }
}

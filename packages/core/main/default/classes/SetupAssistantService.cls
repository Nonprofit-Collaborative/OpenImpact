/**
 * The eight step setup checklist Maria works through on the Hub home page (plan Section
 * 4.8). This is the skeleton: it defines the steps, says where each one is done, and
 * remembers which are finished. The screens the steps open belong to their own features.
 *
 * A step is finished when the administrator marks it done, or when the setting that step
 * exists to fill in already has a value.
 */
public with sharing class SetupAssistantService {
    /** Where a step is carried out: a section of the settings console, or Salesforce Setup. */
    public static final String TARGET_SETTINGS = 'Settings';
    public static final String TARGET_SETUP = 'Setup';

    private static final String PROGRESS_KEY = 'Setup_Steps_Completed__c';
    private static final Integer PROGRESS_LENGTH = 255;

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
        public Boolean completed;
    }

    /** The shipped steps, in order, each carrying whether it is finished. */
    public static List<Step> getSteps() {
        Set<String> marked = markedKeys();
        List<Step> steps = definitions();
        for (Step step : steps) {
            step.completed = marked.contains(step.key) || hasValue(step.completionSettingKey);
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
        return setCompletion(stepKey, true);
    }

    public static List<Step> markIncomplete(String stepKey) {
        return setCompletion(stepKey, false);
    }

    private static List<Step> setCompletion(String stepKey, Boolean completed) {
        String key = stepKey == null ? '' : stepKey.trim();
        if (!keys().contains(key)) {
            throw new SetupStepException(System.Label.Core_SetupAssistant_UnknownStepError);
        }
        Set<String> marked = markedKeys();
        if (completed) {
            marked.add(key);
        } else {
            marked.remove(key);
        }
        List<String> ordered = new List<String>();
        for (Step step : definitions()) {
            if (marked.contains(step.key)) {
                ordered.add(step.key);
            }
        }
        String joined = String.join(ordered, ',');
        if (joined.length() > PROGRESS_LENGTH) {
            joined = joined.substring(0, PROGRESS_LENGTH);
        }
        SettingsService.saveSystemValue(PROGRESS_KEY, joined);
        return getSteps();
    }

    private static Set<String> markedKeys() {
        Set<String> marked = new Set<String>();
        if (!SettingsService.hasKey(PROGRESS_KEY)) {
            return marked;
        }
        String stored = SettingsService.asText(SettingsService.getValue(PROGRESS_KEY));
        for (String part : stored.split(',')) {
            String trimmed = part.trim();
            if (String.isNotBlank(trimmed)) {
                marked.add(trimmed);
            }
        }
        return marked;
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
                'Coexistence_Mode__c'
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
                'Household_Name_Pattern__c'
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
                null
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
                null
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
                null
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
                null
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
                null
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
                null
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
        String completionSettingKey
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
        step.completed = false;
        return step;
    }
}

/**
 * The guided Setup Assistant's Apex surface: what the eight panels show, and the four
 * things they save. Everything a panel needs to render is in one call, so the assistant
 * opens on the step Maria stopped at without a chain of round trips.
 *
 * Every method that changes something checks the `Manage_Nonprofit_Settings` custom
 * permission first, logs what went wrong, and returns a message Maria can act on.
 */
public with sharing class SetupAssistantController {
    private static final String EDIT_PERMISSION = 'Manage_Nonprofit_Settings';
    private static final String ERROR_CONTEXT = 'Setup Assistant';

    private static final String KEY_FUND = 'Default_Fund__c';
    private static final String KEY_APPEAL = 'Default_Appeal__c';

    private static final Set<String> IDENTITY_KEYS = new Set<String>{
        'Organization_Legal_Name__c',
        'Organization_EIN__c',
        'Organization_Address__c',
        'Receipt_Logo_Document_Id__c',
        'Receipt_Signature_Document_Id__c',
        'Receipt_Signer_Name__c',
        'Receipt_Signer_Title__c'
    };

    /** Everything the assistant needs to draw itself. */
    public class SetupState {
        @AuraEnabled
        public Boolean canEdit;
        @AuraEnabled
        public List<SetupAssistantService.Step> steps;
        @AuraEnabled
        public Integer stepsCompleted;
        @AuraEnabled
        public Integer stepsTotal;
        @AuraEnabled
        public Boolean isComplete;
        @AuraEnabled
        public Integer elapsedMinutes;
        @AuraEnabled
        public CoexistenceModel coexistence;
        @AuraEnabled
        public GivingModel giving;
        @AuraEnabled
        public Map<String, String> identity;
        @AuraEnabled
        public List<ModuleDetectionService.ModuleInfo> modules;
        @AuraEnabled
        public List<String> roles;
        @AuraEnabled
        public Boolean importAvailable;
    }

    /** What step one shows: what was detected, what is recommended, what is in force. */
    public class CoexistenceModel {
        @AuraEnabled
        public String detectedShape;
        @AuraEnabled
        public String recommendedMode;
        @AuraEnabled
        public String currentMode;
        @AuraEnabled
        public List<String> modes;
    }

    /** What step three and step eight need to know about the optional Giving package. */
    public class GivingModel {
        @AuraEnabled
        public Boolean isPresent;
        @AuraEnabled
        public String fundObject;
        @AuraEnabled
        public String appealObject;
        @AuraEnabled
        public String defaultFundId;
        @AuraEnabled
        public String defaultAppealId;
    }

    @AuraEnabled
    public static SetupState getState() {
        try {
            return buildState();
        } catch (Exception e) {
            throw logged(e, System.Label.Core_SetupAssistant_LoadErrorMessage);
        }
    }

    @AuraEnabled
    public static SetupState completeStep(String stepKey) {
        requireEdit();
        try {
            SetupAssistantService.markComplete(stepKey);
            return buildState();
        } catch (Exception e) {
            throw logged(e, System.Label.Core_SetupAssistant_LoadErrorMessage);
        }
    }

    @AuraEnabled
    public static SetupState skipStep(String stepKey) {
        requireEdit();
        try {
            SetupAssistantService.markSkipped(stepKey);
            return buildState();
        } catch (Exception e) {
            throw logged(e, System.Label.Core_SetupAssistant_LoadErrorMessage);
        }
    }

    @AuraEnabled
    public static SetupState reset() {
        requireEdit();
        try {
            SetupAssistantService.reset();
            return buildState();
        } catch (Exception e) {
            throw logged(e, System.Label.Core_SetupAssistant_LoadErrorMessage);
        }
    }

    /** Step one: put the confirmed coexistence mode in force and record the step as done. */
    @AuraEnabled
    public static SetupState applyCoexistence(String mode) {
        requireEdit();
        String chosen = mode == null ? '' : mode.trim();
        if (!new Set<String>(SetupAssistantService.modes()).contains(chosen)) {
            throw asAuraException(System.Label.Core_SetupAssistant_UnknownModeError);
        }
        try {
            SetupAssistantService.ensureStarted();
            CoexistenceService.applyMode(chosen);
            SetupAssistantService.markComplete('coexistence');
            return buildState();
        } catch (Exception e) {
            throw logged(e, System.Label.Core_SetupAssistant_SaveErrorMessage);
        }
    }

    /** Step five: the name, tax number, address, signer, and files that receipts are printed with. */
    @AuraEnabled
    public static SetupState saveOrganizationIdentity(Map<String, Object> values) {
        requireEdit();
        Map<String, Object> accepted = new Map<String, Object>();
        if (values != null) {
            for (String key : values.keySet()) {
                if (IDENTITY_KEYS.contains(key)) {
                    accepted.put(key, values.get(key));
                }
            }
        }
        if (accepted.isEmpty()) {
            throw asAuraException(System.Label.Core_SetupAssistant_NothingToSaveError);
        }
        try {
            SetupAssistantService.ensureStarted();
            SettingsService.saveValues(accepted);
            if (String.isNotBlank(String.valueOf(accepted.get('Organization_Legal_Name__c')))) {
                SetupAssistantService.markComplete('identity');
            }
            return buildState();
        } catch (Exception e) {
            throw logged(e, System.Label.Core_SetupAssistant_SaveErrorMessage);
        }
    }

    /**
     * Step three: the fund and appeal a gift falls back to. Refused when the Giving package
     * is not in this org, because there is nothing for the identifiers to point at.
     */
    @AuraEnabled
    public static SetupState saveDefaults(Id fundId, Id appealId) {
        requireEdit();
        if (!ModuleDetectionService.isGivingPresent()) {
            throw asAuraException(System.Label.Core_SetupAssistant_GivingRequiredError);
        }
        requireType(fundId, ModuleDetectionService.fundObjectName());
        requireType(appealId, ModuleDetectionService.appealObjectName());
        try {
            SetupAssistantService.ensureStarted();
            SettingsService.saveSystemValue(
                KEY_FUND,
                fundId == null ? null : String.valueOf(fundId)
            );
            SettingsService.saveSystemValue(
                KEY_APPEAL,
                appealId == null ? null : String.valueOf(appealId)
            );
            if (fundId != null) {
                SetupAssistantService.markComplete('funddefaults');
            }
            return buildState();
        } catch (Exception e) {
            throw logged(e, System.Label.Core_SetupAssistant_SaveErrorMessage);
        }
    }

    /** Step four: give one colleague one packaged role, without leaving the assistant. */
    @AuraEnabled
    public static SetupState assignAccess(Id userId, String roleDeveloperName) {
        requireEdit();
        if (userId == null || String.isBlank(roleDeveloperName)) {
            throw asAuraException(System.Label.Core_SetupAssistant_NothingToSaveError);
        }
        try {
            SetupAssistantService.ensureStarted();
            AccessService.assignRole(userId, roleDeveloperName);
            SetupAssistantService.markComplete('access');
            return buildState();
        } catch (Exception e) {
            throw logged(e, System.Label.Core_SetupAssistant_AccessErrorMessage);
        }
    }

    private static SetupState buildState() {
        SetupState state = new SetupState();
        state.canEdit = FeatureManagement.checkPermission(EDIT_PERMISSION);
        state.steps = SetupAssistantService.getSteps();
        state.stepsTotal = state.steps.size();
        state.stepsCompleted = SetupAssistantService.countCompleted(state.steps);
        state.isComplete = state.stepsCompleted == state.stepsTotal;
        state.elapsedMinutes = SetupAssistantService.elapsedMinutes();
        state.coexistence = coexistence();
        state.giving = giving();
        state.identity = identity();
        state.modules = ModuleDetectionService.getModules();
        state.roles = roles();
        state.importAvailable = ModuleDetectionService.isImportPresent();
        return state;
    }

    private static CoexistenceModel coexistence() {
        CoexistenceModel model = new CoexistenceModel();
        model.detectedShape = SetupAssistantService.detectedShape();
        model.recommendedMode = SetupAssistantService.recommendedMode();
        model.modes = SetupAssistantService.modes();
        try {
            model.currentMode = CoexistenceService.getCurrentMode();
        } catch (Exception e) {
            ErrorLogger.log(e, ERROR_CONTEXT);
            model.currentMode = null;
        }
        return model;
    }

    private static GivingModel giving() {
        GivingModel model = new GivingModel();
        model.isPresent = ModuleDetectionService.isGivingPresent();
        model.fundObject = ModuleDetectionService.fundObjectName();
        model.appealObject = ModuleDetectionService.appealObjectName();
        model.defaultFundId = settingText(KEY_FUND);
        model.defaultAppealId = settingText(KEY_APPEAL);
        return model;
    }

    private static Map<String, String> identity() {
        Map<String, String> values = new Map<String, String>();
        for (String key : IDENTITY_KEYS) {
            values.put(key, settingText(key));
        }
        return values;
    }

    private static List<String> roles() {
        try {
            List<String> roles = AccessService.getRoles();
            return roles == null ? new List<String>() : roles;
        } catch (Exception e) {
            ErrorLogger.log(e, ERROR_CONTEXT);
            return new List<String>();
        }
    }

    private static String settingText(String key) {
        if (!SettingsService.hasKey(key)) {
            return null;
        }
        String value = SettingsService.asText(SettingsService.getValue(key));
        return String.isBlank(value) ? null : value;
    }

    /**
     * Refuses a record identifier that does not point at the object the step is choosing
     * from. The expected object is resolved by describe, so no Giving object is ever named
     * here, and a client that sends any other identifier is turned away rather than storing
     * a default that Giving would fail to read later.
     */
    private static void requireType(Id recordId, String expectedObject) {
        if (recordId == null) {
            return;
        }
        String actual = recordId.getSObjectType()
            .getDescribe(SObjectDescribeOptions.DEFERRED)
            .getName();
        if (String.isBlank(expectedObject) || !expectedObject.equalsIgnoreCase(actual)) {
            throw asAuraException(System.Label.Core_SetupAssistant_WrongRecordTypeError);
        }
    }

    /** Logs what went wrong and gives the page one message Maria can act on. */
    private static AuraHandledException logged(Exception e, String fallback) {
        ErrorLogger.log(e, ERROR_CONTEXT);
        Boolean speaksForItself =
            e instanceof SetupAssistantService.SetupStepException ||
            e instanceof SettingsService.SettingsException;
        return asAuraException(speaksForItself ? e.getMessage() : fallback);
    }

    private static void requireEdit() {
        if (!FeatureManagement.checkPermission(EDIT_PERMISSION)) {
            throw asAuraException(System.Label.Core_Settings_PermissionRequiredError);
        }
    }

    private static AuraHandledException asAuraException(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}

/**
 * The Nonprofit Hub home page's Apex surface: the setup checklist, whether automation is
 * paused, and how many errors nobody has looked at.
 *
 * Everything except the checklist is optional: automation control and the Error Log belong
 * to other features, so each call is wrapped and a failure costs the page a number, not the
 * page.
 */
public with sharing class HubController {
    private static final String EDIT_PERMISSION = 'Manage_Nonprofit_Settings';
    private static final String ERROR_CONTEXT = 'Nonprofit Hub home';

    public class HomeModel {
        @AuraEnabled
        public Boolean canEdit;
        @AuraEnabled
        public Boolean automationPaused;
        @AuraEnabled
        public Integer newErrorCount;
        @AuraEnabled
        public Integer stepsCompleted;
        @AuraEnabled
        public Integer stepsTotal;
        @AuraEnabled
        public List<SetupAssistantService.Step> steps;
    }

    @AuraEnabled(cacheable=true)
    public static HomeModel getHomeModel() {
        try {
            return buildModel();
        } catch (Exception e) {
            ErrorLogger.log(e, ERROR_CONTEXT);
            throw asAuraException(System.Label.Core_HubHome_LoadErrorMessage);
        }
    }

    @AuraEnabled
    public static HomeModel markStepDone(String stepKey) {
        return setStep(stepKey, true);
    }

    @AuraEnabled
    public static HomeModel markStepNotDone(String stepKey) {
        return setStep(stepKey, false);
    }

    private static HomeModel setStep(String stepKey, Boolean completed) {
        if (!FeatureManagement.checkPermission(EDIT_PERMISSION)) {
            throw asAuraException(System.Label.Core_Settings_PermissionRequiredError);
        }
        try {
            if (completed) {
                SetupAssistantService.markComplete(stepKey);
            } else {
                SetupAssistantService.markIncomplete(stepKey);
            }
            return buildModel();
        } catch (SetupAssistantService.SetupStepException e) {
            ErrorLogger.log(e, ERROR_CONTEXT);
            throw asAuraException(e.getMessage());
        } catch (Exception e) {
            ErrorLogger.log(e, ERROR_CONTEXT);
            throw asAuraException(System.Label.Core_HubHome_LoadErrorMessage);
        }
    }

    private static HomeModel buildModel() {
        HomeModel model = new HomeModel();
        model.canEdit = FeatureManagement.checkPermission(EDIT_PERMISSION);
        model.steps = SetupAssistantService.getSteps();
        model.stepsTotal = model.steps.size();
        model.stepsCompleted = SetupAssistantService.countCompleted(model.steps);
        model.automationPaused = readAutomationPaused();
        model.newErrorCount = readNewErrorCount();
        return model;
    }

    private static Boolean readAutomationPaused() {
        try {
            return AutomationControl.isPaused();
        } catch (Exception e) {
            ErrorLogger.log(e, ERROR_CONTEXT);
            return false;
        }
    }

    private static Integer readNewErrorCount() {
        try {
            return HubErrorCountSelector.countNewErrors();
        } catch (Exception e) {
            ErrorLogger.log(e, ERROR_CONTEXT);
            return 0;
        }
    }

    private static AuraHandledException asAuraException(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}

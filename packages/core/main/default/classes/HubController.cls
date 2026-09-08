/**
 * The Nonprofit Hub home page's Apex surface: how far setup has got, whether automation is
 * paused, and how many errors nobody has looked at.
 *
 * The steps themselves belong to the Setup Assistant, which loads them itself, so the home
 * page asks only for the two counters it uses to decide whether the assistant is still the
 * main panel.
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
        public Datetime rollupsLastCalculated;
        @AuraEnabled
        public Boolean rollupsStale;
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

    private static HomeModel buildModel() {
        HomeModel model = new HomeModel();
        model.canEdit = FeatureManagement.checkPermission(EDIT_PERMISSION);
        List<SetupAssistantService.Step> steps = SetupAssistantService.getSteps();
        model.stepsTotal = steps.size();
        model.stepsCompleted = SetupAssistantService.countCompleted(steps);
        model.automationPaused = readAutomationPaused();
        model.newErrorCount = readNewErrorCount();
        readRollupFreshness(model);
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

    /**
     * "Rollups last completed", and whether the nightly run is overdue (plan Section 4.10).
     * Optional like the rest: an org where the rollup engine cannot answer loses a tile, not the
     * page.
     */
    private static void readRollupFreshness(HomeModel model) {
        try {
            model.rollupsLastCalculated = RollupService.lastCalculated();
            model.rollupsStale = RollupService.isStale();
        } catch (Exception e) {
            ErrorLogger.log(e, ERROR_CONTEXT);
            model.rollupsStale = false;
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

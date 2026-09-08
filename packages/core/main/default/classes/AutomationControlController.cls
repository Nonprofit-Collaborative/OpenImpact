/**
 * What the Automation page of the Nonprofit Settings console reads and writes.
 *
 * Every method returns the whole page, so the component never has to work out what changed, and
 * every write is refused for a user without the Manage Nonprofit Settings permission with a
 * message that names the permission.
 */
public with sharing class AutomationControlController {
    /**
     * One row in the list: what it does, and whether it is running.
     */
    public class AutomationView {
        @AuraEnabled
        public String recordId { get; set; }
        @AuraEnabled
        public String automationName { get; set; }
        @AuraEnabled
        public String label { get; set; }
        @AuraEnabled
        public String description { get; set; }
        @AuraEnabled
        public String objectName { get; set; }
        @AuraEnabled
        public Boolean enabled { get; set; }
    }

    /**
     * The whole page: the pause, the permission, and the list.
     */
    public class AutomationPageView {
        @AuraEnabled
        public Boolean paused { get; set; }
        @AuraEnabled
        public Datetime pausedUntil { get; set; }
        @AuraEnabled
        public Boolean canManage { get; set; }
        @AuraEnabled
        public List<Integer> pauseHourOptions { get; set; }
        @AuraEnabled
        public List<AutomationView> automations { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static AutomationPageView getPage() {
        try {
            return currentPage();
        } catch (Exception caught) {
            throw asUserError(caught, 'Automation page');
        }
    }

    @AuraEnabled
    public static AutomationPageView pauseAll(Integer hours) {
        try {
            requirePermission();
            AutomationControl.pauseAll(hours);
            return currentPage();
        } catch (Exception caught) {
            throw asUserError(caught, 'Pause all automation');
        }
    }

    @AuraEnabled
    public static AutomationPageView resumeAll() {
        try {
            requirePermission();
            AutomationControl.resumeAll();
            return currentPage();
        } catch (Exception caught) {
            throw asUserError(caught, 'Resume automation');
        }
    }

    @AuraEnabled
    public static AutomationPageView setEnabled(String automationName, Boolean enabled) {
        try {
            requirePermission();
            if (String.isBlank(automationName)) {
                throw new AutomationControl.AutomationControlException(
                    Label.Core_Automation_NameRequired
                );
            }
            AutomationControl.setEnabled(automationName, enabled == true);
            return currentPage();
        } catch (Exception caught) {
            throw asUserError(caught, 'Switch an automation');
        }
    }

    private static AutomationPageView currentPage() {
        AutomationPageView page = new AutomationPageView();
        page.pausedUntil = AutomationControl.pausedUntil();
        page.paused = page.pausedUntil != null;
        page.canManage = canManage();
        page.pauseHourOptions = new List<Integer>(AutomationControl.allowedPauseHours());
        page.pauseHourOptions.sort();
        page.automations = new List<AutomationView>();
        for (Automation_Setting__c setting : AutomationSettingSelector.selectAllForConsole()) {
            AutomationView view = new AutomationView();
            view.recordId = setting.Id;
            view.automationName = setting.Automation_Name__c;
            view.label = setting.Name;
            view.description = setting.Description__c;
            view.objectName = setting.Object_Name__c;
            view.enabled = setting.Enabled__c;
            page.automations.add(view);
        }
        return page;
    }

    private static Boolean canManage() {
        // Bare, and correctly so: a custom permission defined in the same package resolves without
        // a namespace prefix, so this is not the B5 problem that TriggerHandler.getName had.
        return FeatureManagement.checkPermission('Manage_Nonprofit_Settings');
    }

    private static void requirePermission() {
        if (!canManage()) {
            throw new AutomationControl.AutomationControlException(
                Label.Core_Automation_NoPermission
            );
        }
    }

    /**
     * Turns anything that went wrong into a message the page can show, and records the ones the
     * page cannot explain.
     */
    private static AuraHandledException asUserError(Exception caught, String context) {
        String message = caught.getMessage();
        if (!(caught instanceof AutomationControl.AutomationControlException)) {
            ErrorLogger.log(caught, context);
            message = Label.Core_Automation_UnexpectedError;
        }
        AuraHandledException reported = new AuraHandledException(message);
        reported.setMessage(message);
        return reported;
    }
}

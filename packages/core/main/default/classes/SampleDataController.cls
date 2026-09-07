/**
 * LWC-facing entry points for the sampleDataManager component (C-10). Every method
 * checks the Manage_Nonprofit_Settings custom permission before doing anything; status()
 * is readable by anyone so the card can show read-only counts.
 */
public with sharing class SampleDataController {
    @AuraEnabled
    public static void loadSampleData() {
        try {
            enforcePermission();
            SampleDataLoader.load();
        } catch (Exception e) {
            ErrorLogger.log(e, 'SampleDataController.loadSampleData');
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static SampleDataLoader.Counts removeSampleData() {
        try {
            enforcePermission();
            return SampleDataLoader.remove();
        } catch (Exception e) {
            ErrorLogger.log(e, 'SampleDataController.removeSampleData');
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static SampleDataLoader.Counts getStatus() {
        try {
            return SampleDataLoader.status();
        } catch (Exception e) {
            ErrorLogger.log(e, 'SampleDataController.getStatus');
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static Boolean canManageSampleData() {
        return FeatureManagement.checkPermission('Manage_Nonprofit_Settings');
    }

    private static void enforcePermission() {
        if (!FeatureManagement.checkPermission('Manage_Nonprofit_Settings')) {
            throw new SampleDataException(Label.Core_SampleData_NoPermission);
        }
    }
}

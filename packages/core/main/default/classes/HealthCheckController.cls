/**
 * The healthCheckPanel component's entry point (feature C-11).
 *
 * Reading the report needs no permission: anyone who can open the Nonprofit Hub can look at
 * it and tell an administrator what it says. Acting on a finding needs the
 * Manage_Nonprofit_Settings custom permission, checked here rather than trusted from the
 * component.
 */
public with sharing class HealthCheckController {
    /**
     * The whole report: findings, org shape, current and recommended mode.
     */
    @AuraEnabled
    public static HealthCheckService.Report getReport() {
        try {
            return HealthCheckService.buildReport();
        } catch (Exception e) {
            ErrorLogger.log(e, System.Label.Core_HealthCheck_ErrorContext);
            throw new AuraHandledException(System.Label.Core_HealthCheck_LoadFailed);
        }
    }

    /**
     * Take the recommendation: set the coexistence mode detection proposes, and return the
     * re-run report so the panel shows the result of what it just did.
     */
    @AuraEnabled
    public static HealthCheckService.Report applyRecommendedMode() {
        requireManageSettings();
        try {
            CoexistenceService.applyMode(OrgShapeDetector.recommendedCoexistenceMode());
            return HealthCheckService.buildReport();
        } catch (AuraHandledException e) {
            throw e;
        } catch (CoexistenceService.CoexistenceException e) {
            throw new AuraHandledException(e.getMessage());
        } catch (Exception e) {
            ErrorLogger.log(e, System.Label.Core_HealthCheck_ErrorContext);
            throw new AuraHandledException(System.Label.Core_HealthCheck_FixFailed);
        }
    }

    /**
     * Move household membership to the junction, which is what a Person Accounts org needs.
     */
    @AuraEnabled
    public static HealthCheckService.Report applyJunctionMembership() {
        requireManageSettings();
        try {
            CoexistenceService.applyJunctionMembership();
            return HealthCheckService.buildReport();
        } catch (AuraHandledException e) {
            throw e;
        } catch (CoexistenceService.CoexistenceException e) {
            throw new AuraHandledException(e.getMessage());
        } catch (Exception e) {
            ErrorLogger.log(e, System.Label.Core_HealthCheck_ErrorContext);
            throw new AuraHandledException(System.Label.Core_HealthCheck_FixFailed);
        }
    }

    /**
     * Turn automatic household creation on, which is what the org needs when household
     * membership is on the junction and no new person is getting a household (ADR-NEXT).
     */
    @AuraEnabled
    public static HealthCheckService.Report enableAutomaticHouseholds() {
        requireManageSettings();
        try {
            HouseholdService.enableAutomaticHouseholds();
            return HealthCheckService.buildReport();
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            ErrorLogger.log(e, System.Label.Core_HealthCheck_ErrorContext);
            throw new AuraHandledException(System.Label.Core_HealthCheck_FixFailed);
        }
    }

    private static void requireManageSettings() {
        if (!HealthCheckService.canManageSettings()) {
            throw new AuraHandledException(System.Label.Core_HealthCheck_PermissionRequired);
        }
    }
}

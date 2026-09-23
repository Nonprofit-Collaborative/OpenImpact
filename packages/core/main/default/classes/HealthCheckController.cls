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
     * membership is on the junction and no new person is getting a household (ADR-0037).
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

    /**
     * Run one of the fixes ADR-NEXT allows, by its key, and return the re-run report. Each fix
     * calls a service that only creates what is missing or schedules what is not scheduled,
     * inside one savepoint, so a failure leaves the org as it was and says so.
     */
    @AuraEnabled
    public static HealthCheckService.Report applyFix(String fixKey) {
        requireManageSettings();
        Savepoint beforeFix = Database.setSavepoint();
        try {
            runFix(fixKey);
            return HealthCheckService.buildReport();
        } catch (AuraHandledException e) {
            Database.rollback(beforeFix);
            throw e;
        } catch (Exception e) {
            Database.rollback(beforeFix);
            ErrorLogger.log(e, System.Label.Core_HealthCheck_ErrorContext);
            throw new AuraHandledException(System.Label.Core_HealthCheck_FixFailed);
        }
    }

    private static void runFix(String fixKey) {
        if (HealthCheckService.FIX_KEY_RESTORE_ROLLUPS.equals(fixKey)) {
            RollupService.ensureDefaults();
        } else if (HealthCheckService.FIX_KEY_RESTORE_AUTOMATION_SWITCHES.equals(fixKey)) {
            AutomationControl.ensureDefaults();
        } else if (HealthCheckService.FIX_KEY_RESTORE_IMPORT_TEMPLATES.equals(fixKey)) {
            ImportTemplateService.materializeDefaults();
        } else if (HealthCheckService.FIX_KEY_SCHEDULE_NIGHTLY_ROLLUPS.equals(fixKey)) {
            RollupScheduler.start();
        } else {
            throw new AuraHandledException(System.Label.Core_HealthCheck_FixUnknown);
        }
    }

    private static void requireManageSettings() {
        if (!HealthCheckService.canManageSettings()) {
            throw new AuraHandledException(System.Label.Core_HealthCheck_PermissionRequired);
        }
    }
}

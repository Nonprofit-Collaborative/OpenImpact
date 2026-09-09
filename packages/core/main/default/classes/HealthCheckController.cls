/**
 * The healthCheckPanel component's entry point (features C-11 and C-21).
 *
 * Reading the report needs no permission: anyone who can open the Nonprofit Hub can look at
 * it and tell an administrator what it says. Acting on a finding needs the
 * Manage_Nonprofit_Settings custom permission, checked here rather than trusted from the
 * component, and checked on the preview as well as on the apply: a preview counts things a
 * person without that permission is not allowed to count.
 *
 * C-21 replaced the two fix methods C-11 had with one pair, `previewFix` and `applyFix`, so
 * that a new fix is a class in `HealthCheckFixCatalog` rather than another method here and
 * another branch in the component. The guarantees every fix gets, and the rule that decides
 * which findings may have one at all, are in `HealthCheckFix` and ADR-0029.
 */
public with sharing class HealthCheckController {
    /** What a fix did, and the report re-run underneath it, in one round trip. */
    public class FixOutcome {
        @AuraEnabled
        public HealthCheckFix.Result result;
        @AuraEnabled
        public HealthCheckService.Report report;

        public FixOutcome(HealthCheckFix.Result result, HealthCheckService.Report report) {
            this.result = result;
            this.report = report;
        }
    }

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
     * What one fix would change in this org, so that the person sees it before they decide.
     * Writes nothing.
     */
    @AuraEnabled
    public static HealthCheckFix.Preview previewFix(String fixKey) {
        requireManageSettings();
        try {
            return HealthCheckFix.preview(fixKey);
        } catch (HealthCheckFix.HealthCheckFixException e) {
            throw userError(e.getMessage());
        } catch (Exception e) {
            ErrorLogger.log(e, System.Label.Core_HealthCheck_ErrorContext);
            throw userError(System.Label.Core_HealthCheckFix_PreviewFailed);
        }
    }

    /**
     * Applies one fix and returns what it did together with the re-run report, so the panel
     * shows the result of what it has just done rather than what it knew a moment ago.
     */
    @AuraEnabled
    public static FixOutcome applyFix(String fixKey) {
        requireManageSettings();
        try {
            HealthCheckFix.Result result = HealthCheckFix.apply(fixKey);
            return new FixOutcome(result, HealthCheckService.buildReport());
        } catch (HealthCheckFix.HealthCheckFixException e) {
            throw userError(e.getMessage());
        } catch (CoexistenceService.CoexistenceException e) {
            throw userError(e.getMessage());
        } catch (Exception e) {
            ErrorLogger.log(e, System.Label.Core_HealthCheck_ErrorContext);
            throw userError(System.Label.Core_HealthCheck_FixFailed);
        }
    }

    private static void requireManageSettings() {
        if (!HealthCheckService.canManageSettings()) {
            throw userError(System.Label.Core_HealthCheck_PermissionRequired);
        }
    }

    /**
     * An exception the page can show. The message is set as well as passed to the
     * constructor, because an AuraHandledException built only from the constructor reports
     * itself to the client as "Script-thrown exception".
     */
    private static AuraHandledException userError(String message) {
        AuraHandledException reported = new AuraHandledException(message);
        reported.setMessage(message);
        return reported;
    }
}

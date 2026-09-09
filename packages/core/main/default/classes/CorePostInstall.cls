/**
 * What Open Impact Core does for itself at install and at every upgrade.
 *
 * Two things. The first is to make sure the person who installed the package can open
 * Nonprofit Settings. Without it nobody in the org holds the Manage Nonprofit Settings
 * custom permission, so the console opens read only for everyone, including the System
 * Administrator who installed it, because a custom permission is not implied by Modify All
 * Data. The only way out would be Salesforce Setup, which Principle 1 does not allow.
 *
 * That takes two steps, because the platform makes the obvious one unreliable:
 *
 * 1. Assign the Nonprofit Admin permission set. A permission set has no calculation
 *    status, so this works the moment the install finishes. This is the step that matters:
 *    after it, the installer can use the app.
 * 2. Assign the Nonprofit Admin role, which is a permission set group. The platform
 *    recalculates packaged groups in the background after an install and refuses to assign
 *    one while that is running, which is the usual state in the first minutes. So this is
 *    attempted, and if the group is not ready a queueable waits and tries again a few
 *    times. Either way the person is already working, thanks to step 1.
 *
 * The second is to create the Rollup Definitions the packages ship, so that a fresh org has
 * its totals without anybody being told to press a button (R-R6, ADR-0029). Core sees only
 * the shipped defaults whose source and target entities are in the org, so on a Core-only
 * install this creates Core's own rows and none of a module's; each module that ships
 * rollups calls the same method from its own post-install script, because Core installs
 * first and cannot see a module that is not there yet.
 *
 * The whole thing runs twice safely: a person who already holds a permission set or a role
 * is left alone, and a rollup that already exists is left exactly as the administrator left
 * it, so an upgrade is a no-op for an org that is already set up. Nothing here throws: an
 * install must never fail because of a bootstrap step, so every failure is written to the
 * Error Log instead.
 */
public with sharing class CorePostInstall implements InstallHandler {
    private static final String PERMISSION_SET_CONTEXT = 'CorePostInstall.assignPermissionSet';
    private static final String ROLE_CONTEXT = 'CorePostInstall.assignRole';
    private static final String ROLLUP_CONTEXT = 'CorePostInstall.ensureRollupDefaults';

    /**
     * Called by the platform after the package is installed or upgraded.
     *
     * @param context what the platform knows about this install
     */
    public void onInstall(InstallContext context) {
        if (context == null) {
            return;
        }
        ensureRollupDefaults();
        Id installerId = context.installerId();
        if (installerId == null) {
            return;
        }
        assignAdminPermissionSet(installerId);
        assignAdminRole(installerId);
    }

    /**
     * Creates the shipped Rollup Definitions this org does not have yet, and leaves every
     * definition that is already here exactly as the administrator left it (R-R6).
     *
     * This runs on every install and every upgrade of Core. It is deliberately not tied to the
     * installing person: the definitions belong to the org, not to whoever pressed Install.
     */
    private void ensureRollupDefaults() {
        // The catch is inside RollupService, so that every module's post-install script gets the
        // same guarantee from one place: an org with blank totals is two clicks from being right,
        // and an install the platform rolled back is not.
        RollupService.ensureDefaultsDuringInstall(ROLLUP_CONTEXT);
    }

    /**
     * Step one: give the installer the Nonprofit Admin permission set, so that they can
     * open Nonprofit Settings straight away.
     *
     * @param installerId the person who installed or upgraded the package
     */
    private void assignAdminPermissionSet(Id installerId) {
        try {
            AccessService.assignPermissionSetDuringInstall(
                installerId,
                AccessService.ADMIN_PERMISSION_SET
            );
        } catch (Exception e) {
            ErrorLogger.log(e, PERMISSION_SET_CONTEXT);
        }
    }

    /**
     * Step two: give the installer the Nonprofit Admin role, waiting in the background if
     * the platform is still calculating it.
     *
     * @param installerId the person who installed or upgraded the package
     */
    private void assignAdminRole(Id installerId) {
        try {
            if (AccessService.tryAssignRoleDuringInstall(installerId, AccessService.ADMIN_ROLE)) {
                return;
            }
            System.enqueueJob(new CorePostInstallRetryQueueable(installerId));
        } catch (Exception e) {
            ErrorLogger.log(e, ROLE_CONTEXT);
        }
    }
}

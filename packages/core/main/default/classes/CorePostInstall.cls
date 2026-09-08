/**
 * What Open Impact Core does for itself at install and at every upgrade.
 *
 * Today that is one thing: make sure the person who installed the package can open
 * Nonprofit Settings. Without it nobody in the org holds the Manage Nonprofit Settings
 * custom permission, so the console opens read only for everyone, including the System
 * Administrator who installed it, because a custom permission is not implied by Modify All
 * Data. The only way out would be Salesforce Setup, which Principle 1 does not allow.
 *
 * It does that in two steps, because the platform makes the obvious one unreliable:
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
 * The whole thing runs twice safely: a person who already holds a permission set or a role
 * is left alone, so an upgrade is a no-op for an org that is already set up. Nothing here
 * throws: an install must never fail because of a bootstrap step, so every failure is
 * written to the Error Log instead.
 */
public with sharing class CorePostInstall implements InstallHandler {
    private static final String PERMISSION_SET_CONTEXT = 'CorePostInstall.assignPermissionSet';
    private static final String ROLE_CONTEXT = 'CorePostInstall.assignRole';

    /**
     * Called by the platform after the package is installed or upgraded.
     *
     * @param context what the platform knows about this install
     */
    public void onInstall(InstallContext context) {
        if (context == null) {
            return;
        }
        Id installerId = context.installerId();
        if (installerId == null) {
            return;
        }
        assignAdminPermissionSet(installerId);
        assignAdminRole(installerId);
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

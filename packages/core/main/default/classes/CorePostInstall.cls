/**
 * What Open Impact Core does for itself at install and at every upgrade.
 *
 * Today that is one thing: give the person who installed the package the Nonprofit Admin
 * role. Without it nobody in the org holds the Manage Nonprofit Settings custom
 * permission, so Nonprofit Settings opens read only for everyone and the only way out is
 * Salesforce Setup, which Principle 1 does not allow.
 *
 * This runs twice safely. Assigning a role the installer already holds changes nothing,
 * so an upgrade is a no-op for an org that is already set up, and a second install after
 * an uninstall works the same as the first.
 */
public with sharing class CorePostInstall implements InstallHandler {
    private static final String CONTEXT = 'CorePostInstall.onInstall';

    /**
     * Called by the platform after the package is installed or upgraded.
     *
     * @param context what the platform knows about this install
     */
    public void onInstall(InstallContext context) {
        if (context == null) {
            return;
        }
        assignAdminRoleToInstaller(context.installerId());
    }

    /**
     * Gives the installing user the Nonprofit Admin role, if they do not already hold it.
     *
     * Documented exception to the user mode rule (plan Section 7.2): a post-install script
     * runs as a platform user with no session and no permission set of its own, so the
     * assignment cannot be made in the installer's user mode. It is made in system mode,
     * it is the one thing this class does, and the record it creates is exactly the one
     * the installer would have created by hand in Setup.
     *
     * @param installerId the person who installed or upgraded the package
     */
    private void assignAdminRoleToInstaller(Id installerId) {
        if (installerId == null) {
            return;
        }
        try {
            AccessService.assignRoleDuringInstall(installerId, AccessService.ADMIN_ROLE);
        } catch (Exception e) {
            // An install must never fail because of this. The org is still usable: a
            // System Administrator can assign the role in Setup, and the Error Log says so.
            ErrorLogger.log(e, CONTEXT);
        }
    }
}

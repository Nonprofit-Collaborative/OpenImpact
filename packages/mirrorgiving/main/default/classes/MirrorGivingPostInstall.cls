/**
 * What BarnCRM Mirror for Giving does for itself at install and at every upgrade: create the
 * Automation page's switch rows for the automations it registers (Campaign sync, the Opportunity
 * mirror and the Gift Transaction mirror; ADR-0056 on Campaign sync). Core's, Giving's and
 * Mirror's scripts run before these registry rows exist, so they cannot create them, and Health
 * Check would otherwise report the switches as missing on every fresh install. It does not create
 * `Mirror_Settings__c`: every gift mirror setting's field default already reads as off.
 *
 * The work is Core's `AutomationControl.ensureDefaultsDuringInstall`, which leaves every
 * existing row as the administrator left it and never throws, so an install is never aborted
 * by this step.
 *
 * The step is `runSetup`, which also adds the module to Core's setup marker and is what Finish
 * Setup runs for a module copied into an org by hand (FS1, `ModuleSetups` finds this class by
 * the module key `MirrorGiving` followed by `PostInstall`).
 */
@NamespaceAccessible
public with sharing class MirrorGivingPostInstall implements InstallHandler, ModuleSetup {
	/** The module's key in the module catalog and the setup marker. */
	private static final String MODULE_KEY = 'MirrorGiving';
	private static final String SWITCH_CONTEXT = 'MirrorGivingPostInstall.ensureAutomationSwitches';

	/**
	 * Called by the platform after the package is installed or upgraded.
	 *
	 * @param context what the platform knows about this install, unused here because the
	 *        switches belong to the org rather than to whoever pressed Install
	 */
	public void onInstall(InstallContext context) {
		runSetup(null);
	}

	/** Built by name from Core (`ModuleSetups`) for Finish Setup, so it needs a public constructor. */
	@NamespaceAccessible
	public MirrorGivingPostInstall() {
		// Nothing to set up: the step runs in runSetup.
	}

	/**
	 * The install's step, then the module's key added to the setup marker. Never throws.
	 *
	 * @param installerId unused: the switches belong to the org, not to a person
	 */
	public void runSetup(Id installerId) {
		AutomationControl.ensureDefaultsDuringInstall(SWITCH_CONTEXT);
		ModuleSetups.markRan(MODULE_KEY);
	}
}

/**
 * What Open Impact Giving does for itself at install and at every upgrade.
 *
 * One thing: create the Rollup Definitions this package ships, so that a fresh install has
 * the giving totals on donors, funds, appeals, commitments and installments rather than a
 * page of blank currency attributes and a button labelled Restore that has never had
 * anything to restore (ADR-0029).
 *
 * Core cannot do this on Giving's behalf. Core installs first, and a package that is not
 * installed yet has no objects to describe, so `RollupService.ensureDefaults` correctly
 * skips every giving row when Core's own script runs (R-R6). Giving's script is the first
 * moment the org contains both the shipped rows and the objects they name.
 *
 * The work itself is Core's, which is deliberate: `Rollup_Definition__c` and the shipped
 * defaults are Core's, and a module that materialized its own rows would be a second
 * mechanism to keep in step with the Restore shipped rollups button.
 *
 * Safe on every install, every upgrade, and twice in a row: a definition that exists is
 * matched by Definition Key and left exactly as the administrator left it, including one
 * that has been edited or switched off. Nothing here throws: an install must never fail
 * because of a bootstrap step, so a failure is written to the Error Log instead, and the
 * Rollups page still offers the same button.
 */
public with sharing class GivingPostInstall implements InstallHandler {
    private static final String ROLLUP_CONTEXT = 'GivingPostInstall.ensureRollupDefaults';

    /**
     * Called by the platform after the package is installed or upgraded.
     *
     * @param context what the platform knows about this install, unused here because the
     *        definitions belong to the org rather than to whoever pressed Install
     */
    public void onInstall(InstallContext context) {
        // Nothing is caught here because nothing can be thrown: the entry point records its own
        // failure in the Error Log and returns, so an install is never aborted by this step, and
        // the Rollups page can still create the rows on demand.
        RollupService.ensureDefaultsDuringInstall(ROLLUP_CONTEXT);
    }
}

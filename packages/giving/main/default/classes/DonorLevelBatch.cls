/**
 * Re-places every donor on the ladder: the nightly pass, and the Recalculate now button on the
 * Donor Levels page, which are the same job (R-DL6).
 *
 * A save announces a changed giving total, so real time assignment covers almost everything. Two
 * things announce nothing and are the whole reason this batch exists: a fiscal year turning over,
 * which changes what "giving this year" means without touching a single record, and a ladder an
 * administrator edited yesterday, which changes what every total earns.
 *
 * It runs over accounts first and chains to contacts, so one run covers households, organizations,
 * people held as accounts, and people held as contacts. Only the records that actually move are
 * written, so a normal night reads broadly and writes very little.
 */
public with sharing class DonorLevelBatch implements Database.Batchable<SObject>, Database.Stateful {
    @TestVisible
    private static final String ACCOUNTS = 'Account';
    @TestVisible
    private static final String CONTACTS = 'Contact';

    private final String scopeObject;
    private Integer moved = 0;

    /** A run that starts with accounts and chains to contacts. */
    public DonorLevelBatch() {
        this(ACCOUNTS);
    }

    @TestVisible
    private DonorLevelBatch(String scopeObject) {
        this.scopeObject = scopeObject;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        return ACCOUNTS.equals(scopeObject)
            ? DonorLevelSelector.accountLocator()
            : DonorLevelSelector.contactLocator();
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        try {
            DonorLevelService.clearCache();
            List<SObject> changed = DonorLevelService.assignAll(scope);
            DonorLevelWriter.save(changed);
            moved += changed.size();
        } catch (Exception chunkFailure) {
            // One bad chunk must not stop the rest of the org being re-placed.
            ErrorLogger.log(chunkFailure, 'DonorLevelBatch.' + scopeObject);
        }
    }

    public void finish(Database.BatchableContext context) {
        try {
            if (ACCOUNTS.equals(scopeObject)) {
                if (!Test.isRunningTest()) {
                    Database.executeBatch(new DonorLevelBatch(CONTACTS), 200);
                }
                return;
            }
            DonorLevelService.recordRecalculation(System.now());
        } catch (Exception finishFailure) {
            ErrorLogger.log(finishFailure, 'DonorLevelBatch.finish');
        }
    }

    /** How many donors this run moved between levels, for a test or a caller that wants to know. */
    public Integer donorsMoved() {
        return moved;
    }
}

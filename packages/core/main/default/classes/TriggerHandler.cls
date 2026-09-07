/**
 * Base class for every packaged trigger handler.
 *
 * A handler subclasses this, overrides only the contexts it cares about, and is invoked by
 * `TriggerDispatcher`. Nothing else calls a handler directly, so every packaged automation is
 * bypassable and pausable (plan Section 7.2, canonical model rule R-A1).
 *
 * The recursion guard is deliberately per transaction and per handler: `claimRunFor` returns
 * true the first time a phase is claimed and false afterwards, so a handler that causes its own
 * object to be updated again does its work once.
 */
@NamespaceAccessible
public virtual with sharing class TriggerHandler {
    private static final Set<String> CLAIMED_PHASES = new Set<String>();

    @NamespaceAccessible
    public virtual void beforeInsert(List<SObject> newRecords) {
        return;
    }

    @NamespaceAccessible
    public virtual void afterInsert(List<SObject> newRecords, Map<Id, SObject> newRecordsById) {
        return;
    }

    @NamespaceAccessible
    public virtual void beforeUpdate(
        List<SObject> newRecords,
        Map<Id, SObject> newRecordsById,
        List<SObject> oldRecords,
        Map<Id, SObject> oldRecordsById
    ) {
        return;
    }

    @NamespaceAccessible
    public virtual void afterUpdate(
        List<SObject> newRecords,
        Map<Id, SObject> newRecordsById,
        List<SObject> oldRecords,
        Map<Id, SObject> oldRecordsById
    ) {
        return;
    }

    @NamespaceAccessible
    public virtual void beforeDelete(List<SObject> oldRecords, Map<Id, SObject> oldRecordsById) {
        return;
    }

    @NamespaceAccessible
    public virtual void afterDelete(List<SObject> oldRecords, Map<Id, SObject> oldRecordsById) {
        return;
    }

    @NamespaceAccessible
    public virtual void afterUndelete(List<SObject> newRecords, Map<Id, SObject> newRecordsById) {
        return;
    }

    /**
     * The stable name of this automation, matching its Automation Setting row and its entry in
     * the shipped registry. A handler may override it; by default it is the class name.
     */
    @NamespaceAccessible
    public virtual String getName() {
        return String.valueOf(this).substringBefore(':');
    }

    /**
     * Claims a phase for this transaction. Returns true the first time, false every time after.
     */
    @NamespaceAccessible
    public Boolean claimRunFor(String phase) {
        String key = phaseKey(phase);
        if (CLAIMED_PHASES.contains(key)) {
            return false;
        }
        CLAIMED_PHASES.add(key);
        return true;
    }

    @NamespaceAccessible
    public Boolean hasRunFor(String phase) {
        return CLAIMED_PHASES.contains(phaseKey(phase));
    }

    @NamespaceAccessible
    public void releaseRunFor(String phase) {
        CLAIMED_PHASES.remove(phaseKey(phase));
    }

    /**
     * Clears every claim. Used by tests and by bulk operations that deliberately re-run a
     * handler in the same transaction.
     */
    @NamespaceAccessible
    public static void clearRunClaims() {
        CLAIMED_PHASES.clear();
    }

    private String phaseKey(String phase) {
        return getName() + '.' + (phase == null ? '' : phase);
    }
}

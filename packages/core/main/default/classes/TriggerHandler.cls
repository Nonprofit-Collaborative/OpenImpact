/**
 * Base class for every packaged trigger handler.
 *
 * A handler subclasses this, overrides only the contexts it cares about, and is invoked by
 * `TriggerDispatcher`. Nothing else calls a handler directly, so every packaged automation is
 * bypassable and pausable (plan Section 7.2, canonical model rule R-A1).
 *
 * The recursion guard is per transaction, per handler, per phase, and per record: `claimRunFor`
 * takes the record ids in front of it and hands back the ones this handler has not already
 * processed, so a handler that causes its own object to be updated again does its work once per
 * record while a 400 record load still gets all 400 processed.
 */
@NamespaceAccessible
public virtual with sharing class TriggerHandler {
    private static final Map<String, Set<Id>> CLAIMED_RECORDS = new Map<String, Set<Id>>();

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
     *
     * The namespace is stripped. Inside a managed package the class reports itself as
     * `Namespace.ContactTriggerHandler`, while every consumer of this value (the automation row,
     * the bypass, the recursion guard) keys on the bare name the registry ships.
     */
    @NamespaceAccessible
    public virtual String getName() {
        String qualifiedName = String.valueOf(this).substringBefore(':');
        return qualifiedName.contains('.') ? qualifiedName.substringAfterLast('.') : qualifiedName;
    }

    /**
     * Claims records for a phase and returns the ones this handler has not seen yet in this
     * transaction.
     *
     * The guard is per record, not per phase, and that matters: one DML of 400 records fires the
     * trigger twice in the same transaction with statics preserved, so a guard that claimed the
     * whole phase would let a handler process the first 200 records and silently skip the rest
     * (plan Principle 2). Records already claimed come back out of the set, everything else is
     * claimed and returned.
     */
    @NamespaceAccessible
    public Set<Id> claimRunFor(String phase, Set<Id> recordIds) {
        Set<Id> unclaimed = new Set<Id>();
        if (recordIds == null || recordIds.isEmpty()) {
            return unclaimed;
        }
        Set<Id> claimed = claimedFor(phase);
        for (Id recordId : recordIds) {
            if (recordId != null && !claimed.contains(recordId)) {
                unclaimed.add(recordId);
            }
        }
        claimed.addAll(unclaimed);
        return unclaimed;
    }

    @NamespaceAccessible
    public Boolean hasRunFor(String phase, Id recordId) {
        return recordId != null && claimedFor(phase).contains(recordId);
    }

    /**
     * Forgets what this handler has claimed for a phase, for the rare operation that means to run
     * it again over the same records in one transaction.
     */
    @NamespaceAccessible
    public void releaseRunFor(String phase) {
        CLAIMED_RECORDS.remove(phaseKey(phase));
    }

    /**
     * Clears every claim. Used by tests and by bulk operations that deliberately re-run a
     * handler in the same transaction.
     */
    @NamespaceAccessible
    public static void clearRunClaims() {
        CLAIMED_RECORDS.clear();
    }

    private Set<Id> claimedFor(String phase) {
        String key = phaseKey(phase);
        if (!CLAIMED_RECORDS.containsKey(key)) {
            CLAIMED_RECORDS.put(key, new Set<Id>());
        }
        return CLAIMED_RECORDS.get(key);
    }

    private String phaseKey(String phase) {
        return getName() + '.' + (phase == null ? '' : phase);
    }
}

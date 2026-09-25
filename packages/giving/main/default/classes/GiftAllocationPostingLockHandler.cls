/**
 * The posting and closed period lock on allocations (G-20, R-GA5): the funds of a gift in the
 * books stay what the books hold. Always Runs, like the gift lock it belongs to (ADR-0024).
 */
public with sharing class GiftAllocationPostingLockHandler extends TriggerHandler {
    public override String getName() {
        return 'GiftAllocationPostingLockHandler';
    }

    public override void beforeInsert() {
        GiftPostingLock.enforceOnAllocations((List<Gift_Allocation__c>) Trigger.new, null, 'added');
    }

    public override void beforeUpdate() {
        GiftPostingLock.enforceOnAllocations(
            (List<Gift_Allocation__c>) Trigger.new,
            (Map<Id, Gift_Allocation__c>) Trigger.oldMap,
            'changed'
        );
    }

    public override void beforeDelete() {
        GiftPostingLock.enforceOnAllocations(
            (List<Gift_Allocation__c>) Trigger.old,
            null,
            'deleted'
        );
    }

    /** A restored allocation is an allocation added to its gift. */
    public override void afterUndelete() {
        GiftPostingLock.enforceOnAllocations(
            (List<Gift_Allocation__c>) Trigger.new,
            null,
            'restored'
        );
    }
}

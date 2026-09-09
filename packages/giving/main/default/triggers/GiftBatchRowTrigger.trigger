/**
 * One trigger for Gift_Batch_Row__c. It does nothing itself: the Core dispatcher reads the
 * automation registry and runs the handlers registered for this object, in order.
 */
trigger GiftBatchRowTrigger on Gift_Batch_Row__c(
    before insert,
    before update,
    before delete
) {
    TriggerDispatcher.run('Gift_Batch_Row__c');
}

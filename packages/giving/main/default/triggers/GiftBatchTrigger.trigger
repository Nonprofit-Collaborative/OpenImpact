/**
 * One trigger for Gift_Batch__c. It does nothing itself: the Core dispatcher reads the
 * automation registry and runs the handlers registered for this object, in order.
 */
trigger GiftBatchTrigger on Gift_Batch__c(before update, before delete) {
    TriggerDispatcher.run('Gift_Batch__c');
}

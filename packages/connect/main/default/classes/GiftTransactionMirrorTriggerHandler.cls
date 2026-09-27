/**
 * The `Gift_Transaction_Mirror` automation on Gift (feature X-07). It copies nothing: both
 * directions of the Gift Transaction mirror are runs (R-GT5). Before a gift is written it checks
 * a typed or changed Gift Transaction ID (R-GT9); after a delete it reports the Gift Transactions
 * the deleted gifts leave behind (R-GT8). Neither reads a Nonprofit Cloud record, and an ordinary
 * save that does not touch the link reads nothing at all. Its switch on the Automation page also
 * stops the runs.
 */
public with sharing class GiftTransactionMirrorTriggerHandler extends TriggerHandler {
    public override String getName() {
        return GiftTransactionMirrorService.AUTOMATION_NAME;
    }

    public override void beforeInsert() {
        GiftTransactionMirrorService.checkLinks((List<Gift__c>) Trigger.new, null);
    }

    public override void beforeUpdate() {
        GiftTransactionMirrorService.checkLinks(
            (List<Gift__c>) Trigger.new,
            (Map<Id, Gift__c>) Trigger.oldMap
        );
    }

    public override void afterDelete() {
        GiftTransactionMirrorService.warnDeleted((List<Gift__c>) Trigger.old);
    }
}

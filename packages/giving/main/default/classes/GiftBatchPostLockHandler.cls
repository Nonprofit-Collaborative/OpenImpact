/**
 * The post lock, on an automation that always runs.
 *
 * A batch that could be posted twice is a batch that can double a deposit, and a posted batch
 * that could be edited is not an audit trail. Those are rules rather than conveniences, so this
 * handler's two registry rows carry `Always_Runs__c` and neither the switch, the bypass nor the
 * global pause reaches them (R-A4, following ADR-0024, and R-GB4, R-GR4).
 *
 * One class serves both objects, because it is one rule seen from two sides: it is registered
 * against `Gift_Batch__c` as `Gift_Batch_Post_Lock` and against `Gift_Batch_Row__c` as
 * `Gift_Batch_Row_Post_Lock`, and it reads the trigger context to tell which it is running for.
 *
 * The single legitimate move from Open to Posted is the one `GiftBatchService.post` makes, inside
 * the transaction that creates the gifts. It announces itself with a transaction flag, so typing
 * the word Posted into the field by hand, which would close a batch without producing a single
 * gift, is refused like any other edit.
 */
public with sharing class GiftBatchPostLockHandler extends TriggerHandler {
    public override String getName() {
        return 'GiftBatchPostLockHandler';
    }

    public override void beforeInsert() {
        if (isRowContext(Trigger.new)) {
            refuseRowsBelongingToPostedBatches(
                (List<Gift_Batch_Row__c>) Trigger.new,
                Label.Giving_GiftBatch_ErrorRowAddedToPosted
            );
        }
    }

    public override void beforeUpdate() {
        if (isRowContext(Trigger.new)) {
            lockPostedRows();
            return;
        }
        lockPostedBatches();
    }

    public override void beforeDelete() {
        if (isRowContext(Trigger.old)) {
            refuseRowsBelongingToPostedBatches(
                (List<Gift_Batch_Row__c>) Trigger.old,
                Label.Giving_GiftBatch_ErrorRowDeleteAfterPost
            );
            return;
        }
        for (Gift_Batch__c batch : (List<Gift_Batch__c>) Trigger.old) {
            if (GiftBatchService.STATUS_POSTED.equals(batch.Status__c)) {
                batch.addError(Label.Giving_GiftBatch_ErrorDeleteAfterPost);
            }
        }
    }

    /**
     * A batch that has posted is finished: nothing on it changes again, including the status,
     * which is what stops a reopen and a second post. A batch that has not posted may only become
     * Posted through the posting service.
     */
    private void lockPostedBatches() {
        Map<Id, Gift_Batch__c> previous = (Map<Id, Gift_Batch__c>) Trigger.oldMap;
        for (Gift_Batch__c batch : (List<Gift_Batch__c>) Trigger.new) {
            Gift_Batch__c before = previous.get(batch.Id);
            if (GiftBatchService.STATUS_POSTED.equals(before.Status__c)) {
                batch.addError(Label.Giving_GiftBatch_ErrorEditAfterPost);
            } else if (
                GiftBatchService.STATUS_POSTED.equals(batch.Status__c) &&
                GiftBatchService.posting != true
            ) {
                batch.addError(Label.Giving_GiftBatch_ErrorPostByHand);
            }
        }
    }

    /**
     * A line of a posted batch is closed (R-GR4), with one exception the platform forces: a
     * lookup clears itself when the record it points at is deleted, so a posted row whose gift is
     * deleted has to be allowed to lose that reference. Refusing it would let a posted batch stop
     * a gift from ever being deleted. What the line says was typed does not change either way.
     */
    private void lockPostedRows() {
        List<Gift_Batch_Row__c> rows = (List<Gift_Batch_Row__c>) Trigger.new;
        Map<Id, Gift_Batch_Row__c> previous = (Map<Id, Gift_Batch_Row__c>) Trigger.oldMap;
        Set<Id> postedBatchIds = postedBatchIdsFor(rows);
        for (Gift_Batch_Row__c row : rows) {
            if (!postedBatchIds.contains(row.Gift_Batch__c)) {
                continue;
            }
            if (!onlyTheGiftWasCleared(row, previous.get(row.Id))) {
                row.addError(Label.Giving_GiftBatch_ErrorRowEditAfterPost);
            }
        }
    }

    private void refuseRowsBelongingToPostedBatches(
        List<Gift_Batch_Row__c> rows,
        String message
    ) {
        Set<Id> postedBatchIds = postedBatchIdsFor(rows);
        for (Gift_Batch_Row__c row : rows) {
            if (postedBatchIds.contains(row.Gift_Batch__c)) {
                row.addError(message);
            }
        }
    }

    private Set<Id> postedBatchIdsFor(List<Gift_Batch_Row__c> rows) {
        Set<Id> batchIds = new Set<Id>();
        for (Gift_Batch_Row__c row : rows) {
            if (row.Gift_Batch__c != null) {
                batchIds.add(row.Gift_Batch__c);
            }
        }
        Set<Id> posted = new Set<Id>();
        if (batchIds.isEmpty()) {
            return posted;
        }
        for (Gift_Batch__c batch : GiftBatchSelector.selectBatchesForRows(batchIds).values()) {
            if (GiftBatchService.STATUS_POSTED.equals(batch.Status__c)) {
                posted.add(batch.Id);
            }
        }
        return posted;
    }

    private Boolean onlyTheGiftWasCleared(Gift_Batch_Row__c row, Gift_Batch_Row__c before) {
        if (before == null || before.Gift__c == null || row.Gift__c != null) {
            return false;
        }
        return row.Gift_Batch__c == before.Gift_Batch__c &&
            row.Row_Number__c == before.Row_Number__c &&
            row.Donor_Contact__c == before.Donor_Contact__c &&
            row.Donor_Account__c == before.Donor_Account__c &&
            row.Amount__c == before.Amount__c &&
            row.Gift_Date__c == before.Gift_Date__c &&
            row.Fund__c == before.Fund__c &&
            row.Appeal__c == before.Appeal__c &&
            row.Payment_Method__c == before.Payment_Method__c &&
            row.Payment_Reference__c == before.Payment_Reference__c;
    }

    private Boolean isRowContext(List<SObject> records) {
        return records != null &&
            !records.isEmpty() &&
            records[0].getSObjectType() == Gift_Batch_Row__c.SObjectType;
    }
}

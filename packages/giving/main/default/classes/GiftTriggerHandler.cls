/**
 * Record-level rules for Gift__c, run by the Core trigger dispatcher through the automation
 * registry, so an administrator can switch it off from the console (ADR-0017).
 */
public with sharing class GiftTriggerHandler extends TriggerHandler {
    public override String getName() {
        return 'GiftTriggerHandler';
    }

    public override void beforeInsert() {
        List<Gift__c> gifts = (List<Gift__c>) Trigger.new;
        GiftService.defaultGiftDates(gifts);
        GiftService.deriveHouseholds(gifts);
    }

    public override void beforeUpdate() {
        List<Gift__c> gifts = (List<Gift__c>) Trigger.new;
        Map<Id, Gift__c> oldGifts = (Map<Id, Gift__c>) Trigger.oldMap;
        GiftService.defaultGiftDates(gifts);
        GiftService.enforceReceiptLock(gifts, oldGifts);

        List<Gift__c> donorChanged = new List<Gift__c>();
        for (Gift__c gift : gifts) {
            Gift__c previous = oldGifts.get(gift.Id);
            if (
                gift.Donor_Contact__c != previous.Donor_Contact__c ||
                gift.Donor_Account__c != previous.Donor_Account__c
            ) {
                donorChanged.add(gift);
            }
        }
        if (!donorChanged.isEmpty()) {
            GiftService.deriveHouseholds(donorChanged);
        }
    }

    public override void afterInsert() {
        GiftService.applyDefaultAllocations((List<Gift__c>) Trigger.new);
    }

    public override void afterUpdate() {
        GiftService.synchronizeAllocationsToAmount(
            (List<Gift__c>) Trigger.new,
            (Map<Id, Gift__c>) Trigger.oldMap
        );
    }
}

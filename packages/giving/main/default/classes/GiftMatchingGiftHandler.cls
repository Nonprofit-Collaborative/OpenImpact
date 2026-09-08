/**
 * Keeps the two halves of a matching gift pair in step (feature G-10).
 *
 * Registered on Gift with execution order 40, after the soft credit handler, because linking a
 * gift creates a soft credit of its own and the two must not race.
 *
 * David links a match by setting Matched Gift on the employer's gift, so the rules have to live
 * where that edit lands. The handler validates the pair, writes the other side of the link, and
 * maintains the matched donor credit. A link the rules refuse is reported on the record being
 * saved, in the same words the service uses.
 */
@NamespaceAccessible
public with sharing class GiftMatchingGiftHandler extends TriggerHandler {
    @NamespaceAccessible
    public GiftMatchingGiftHandler() {
        return;
    }

    public override void afterInsert() {
        MatchingGiftService.applyLinkChanges(asGifts(newRecords()), new Map<Id, Gift__c>());
    }

    public override void afterUpdate() {
        MatchingGiftService.applyLinkChanges(asGifts(newRecords()), priorById(oldRecordsById()));
    }

    public override void beforeDelete() {
        List<Gift__c> cleared = new List<Gift__c>();
        for (Gift__c gift : asGifts(oldRecords())) {
            if (gift.Matched_Gift__c != null) {
                cleared.add(new Gift__c(Id = gift.Id, Matched_Gift__c = null));
            }
        }
        MatchingGiftService.applyLinkChanges(cleared, priorById(oldRecordsById()));
    }

    private static Map<Id, Gift__c> priorById(Map<Id, SObject> oldRecordsById) {
        Map<Id, Gift__c> prior = new Map<Id, Gift__c>();
        if (oldRecordsById == null) {
            return prior;
        }
        for (Id recordId : oldRecordsById.keySet()) {
            prior.put(recordId, (Gift__c) oldRecordsById.get(recordId));
        }
        return prior;
    }

    private static List<Gift__c> asGifts(List<SObject> records) {
        List<Gift__c> gifts = new List<Gift__c>();
        if (records == null) {
            return gifts;
        }
        for (SObject record : records) {
            gifts.add((Gift__c) record);
        }
        return gifts;
    }
}

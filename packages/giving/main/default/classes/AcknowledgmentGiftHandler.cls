/**
 * The acknowledgment rules, on the gift save.
 *
 * Registered as `Acknowledgment_Rules` on `Gift__c` at order 50, after the core gift rules have
 * filled in the household and the dates the rules read, and after the soft credit and matching
 * gift work, so that nothing this handler does is undone by a later one.
 *
 * It is an ordinary switchable automation. An organization that would rather decide who to thank
 * by hand switches it off in the settings console and every gift simply stays at To acknowledge.
 *
 * The handler is the three line wrapper every other one is: the rules themselves are
 * `AcknowledgmentService` methods that take explicit lists and are tested without a trigger.
 */
public with sharing class AcknowledgmentGiftHandler extends TriggerHandler {
    public override String getName() {
        return 'AcknowledgmentGiftHandler';
    }

    public override void beforeInsert() {
        AcknowledgmentService.applyRules((List<Gift__c>) Trigger.new, null);
        AcknowledgmentService.stampAcknowledgmentDate((List<Gift__c>) Trigger.new);
    }

    public override void beforeUpdate() {
        AcknowledgmentService.applyRules(
            (List<Gift__c>) Trigger.new,
            (Map<Id, Gift__c>) Trigger.oldMap
        );
        AcknowledgmentService.stampAcknowledgmentDate((List<Gift__c>) Trigger.new);
    }

    public override void afterInsert() {
        AcknowledgmentService.recordAcknowledgments((List<Gift__c>) Trigger.new, null);
    }

    public override void afterUpdate() {
        AcknowledgmentService.recordAcknowledgments(
            (List<Gift__c>) Trigger.new,
            (Map<Id, Gift__c>) Trigger.oldMap
        );
    }
}

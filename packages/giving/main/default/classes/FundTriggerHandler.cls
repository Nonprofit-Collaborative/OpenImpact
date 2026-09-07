/**
 * Record-level rules for Fund__c: at most one fund is the default, and marking a new one
 * clears the old one rather than asking an administrator to remember (R-F1).
 */
public with sharing class FundTriggerHandler extends TriggerHandler {
    public override String getName() {
        return 'FundTriggerHandler';
    }

    public override void beforeInsert() {
        rejectSeveralDefaults((List<Fund__c>) Trigger.new);
    }

    public override void beforeUpdate() {
        rejectSeveralDefaults((List<Fund__c>) Trigger.new);
    }

    public override void afterInsert() {
        clearOtherDefaults((List<Fund__c>) Trigger.new, null);
    }

    public override void afterUpdate() {
        clearOtherDefaults((List<Fund__c>) Trigger.new, (Map<Id, Fund__c>) Trigger.oldMap);
    }

    /**
     * One save that marks two funds as the default has no defensible answer, so it is refused
     * rather than guessed at.
     */
    private void rejectSeveralDefaults(List<Fund__c> funds) {
        Integer defaults = 0;
        for (Fund__c fund : funds) {
            if (fund.Is_Default__c == true) {
                defaults++;
            }
        }
        if (defaults > 1) {
            for (Fund__c fund : funds) {
                if (fund.Is_Default__c == true) {
                    fund.addError(Label.Giving_Fund_OneDefaultAtATime);
                }
            }
        }
    }

    private void clearOtherDefaults(List<Fund__c> funds, Map<Id, Fund__c> oldFunds) {
        Set<Id> newDefaults = new Set<Id>();
        for (Fund__c fund : funds) {
            Fund__c previous = oldFunds == null ? null : oldFunds.get(fund.Id);
            Boolean becameDefault =
                fund.Is_Default__c == true && (previous == null || previous.Is_Default__c != true);
            if (becameDefault) {
                newDefaults.add(fund.Id);
            }
        }
        if (newDefaults.isEmpty()) {
            return;
        }

        List<Fund__c> toClear = FundSelector.selectOtherDefaults(newDefaults);
        if (toClear.isEmpty()) {
            return;
        }
        for (Fund__c fund : toClear) {
            fund.Is_Default__c = false;
        }
        Database.update(toClear, AccessLevel.USER_MODE);
    }
}

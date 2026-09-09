/**
 * What the rules do to a gift, and what a gift being thanked leaves behind.
 *
 * Three jobs, in the order a save meets them.
 *
 *   1. `applyRules`, before the save. A gift whose matching rule says no thank you is needed
 *      becomes Not required, so the list of gifts waiting to be thanked is only the gifts the
 *      organization means to thank (R-AK6). Nothing else is touched: a gift somebody set by hand
 *      is left alone, and a gift no rule matched keeps the status it has (R-AK5, R-AK7).
 *   2. `stampAcknowledgmentDate`, before the save. A gift marked Acknowledged with no date gets
 *      today's, so the gift and the record of it always agree (R-AC1).
 *   3. `recordAcknowledgments`, after the save. A gift that has just become Acknowledged gets one
 *      Acknowledgment record naming the rule, the wording and the channel, with the letter merged
 *      and frozen (R-AC1, R-AC3).
 *
 * **Deciding is not sending.** Nothing in this class sends an email, produces a mailing file, or
 * asks anything else to (R-AK8). A person or an integration sends the thank you and marks the gift
 * acknowledged; the package notices and writes it down. That is why step 3 keys on the status
 * changing rather than on a button: the change can arrive from a record page, a list view, an
 * import, or the API, and all four are recorded the same way.
 *
 * Every path here reports its failures to the Error Log and lets the save stand. A rule that has
 * been misconfigured, or an organization whose users cannot create Acknowledgment records, is a
 * problem for an administrator to see in the log; it is not a reason David cannot enter a gift.
 */
public with sharing class AcknowledgmentService {
    public static final String STATUS_NOT_REQUIRED = 'Not required';
    public static final String STATUS_TO_ACKNOWLEDGE = 'To acknowledge';
    public static final String STATUS_ACKNOWLEDGED = 'Acknowledged';

    private static final String LOG_CONTEXT = 'Acknowledgment rules';

    /**
     * Step 1. `previousById` is null on insert. On update a gift is re-read only when something a
     * rule can look at has changed, so an unrelated edit does not spend a query (R-AK7).
     */
    public static void applyRules(List<Gift__c> gifts, Map<Id, Gift__c> previousById) {
        if (gifts == null || gifts.isEmpty()) {
            return;
        }
        try {
            List<Gift__c> undecided = new List<Gift__c>();
            for (Gift__c gift : gifts) {
                if (gift.Acknowledgment_Status__c != STATUS_TO_ACKNOWLEDGE) {
                    continue;
                }
                if (gift.Acknowledgment_Date__c != null) {
                    continue;
                }
                Gift__c previous = previousById == null ? null : previousById.get(gift.Id);
                if (previous != null && !criteriaChanged(gift, previous)) {
                    continue;
                }
                undecided.add(gift);
            }
            if (undecided.isEmpty()) {
                return;
            }
            List<AcknowledgmentRuleEngine.Decision> decisions = AcknowledgmentRuleEngine.decide(
                undecided
            );
            for (Integer index = 0; index < undecided.size(); index++) {
                AcknowledgmentRuleEngine.Decision decision = decisions[index];
                if (decision != null && decision.channel == AcknowledgmentRuleEngine.CHANNEL_NONE) {
                    undecided[index].Acknowledgment_Status__c = STATUS_NOT_REQUIRED;
                }
            }
        } catch (Exception failed) {
            ErrorLogger.log(failed, LOG_CONTEXT);
        }
    }

    /** Step 2. Never overwrites a date somebody typed. */
    public static void stampAcknowledgmentDate(List<Gift__c> gifts) {
        if (gifts == null) {
            return;
        }
        for (Gift__c gift : gifts) {
            if (
                gift.Acknowledgment_Status__c == STATUS_ACKNOWLEDGED &&
                gift.Acknowledgment_Date__c == null
            ) {
                gift.Acknowledgment_Date__c = Date.today();
            }
        }
    }

    /**
     * Step 3. One record per gift that has just become Acknowledged, and none for a gift that was
     * already Acknowledged before this save, so an edit to an acknowledged gift does not invent a
     * second thank you.
     */
    public static void recordAcknowledgments(List<Gift__c> gifts, Map<Id, Gift__c> previousById) {
        if (gifts == null || gifts.isEmpty()) {
            return;
        }
        try {
            Set<Id> newlyAcknowledged = new Set<Id>();
            for (Gift__c gift : gifts) {
                if (gift.Acknowledgment_Status__c != STATUS_ACKNOWLEDGED) {
                    continue;
                }
                Gift__c previous = previousById == null ? null : previousById.get(gift.Id);
                if (previous != null && previous.Acknowledgment_Status__c == STATUS_ACKNOWLEDGED) {
                    continue;
                }
                newlyAcknowledged.add(gift.Id);
            }
            if (newlyAcknowledged.isEmpty()) {
                return;
            }
            write(build(AcknowledgmentSelector.giftsToAcknowledge(newlyAcknowledged)));
        } catch (Exception failed) {
            ErrorLogger.log(failed, LOG_CONTEXT);
        }
    }

    /**
     * The records, and the problems worth telling an administrator about. A rule whose wording
     * cannot be used still produces a record naming the rule: the thank you was sent by a person,
     * and losing the record of it to a configuration mistake would be the worse outcome (R-AT4).
     */
    private static List<Acknowledgment__c> build(List<Gift__c> gifts) {
        List<Acknowledgment__c> rows = new List<Acknowledgment__c>();
        if (gifts.isEmpty()) {
            return rows;
        }
        List<AcknowledgmentRuleEngine.Decision> decisions = AcknowledgmentRuleEngine.decide(gifts);
        AcknowledgmentTemplateService.OrganizationIdentity identity = AcknowledgmentTemplateService.organizationIdentity();
        List<String> problems = new List<String>();

        for (Integer index = 0; index < gifts.size(); index++) {
            Gift__c gift = gifts[index];
            AcknowledgmentRuleEngine.Decision decision = decisions[index];
            Acknowledgment__c row = new Acknowledgment__c(
                Gift__c = gift.Id,
                Acknowledged_Date__c = gift.Acknowledgment_Date__c == null
                    ? Date.today()
                    : gift.Acknowledgment_Date__c
            );
            if (decision != null) {
                row.Rule__c = decision.rule.Id;
                if (decision.channel != AcknowledgmentRuleEngine.CHANNEL_NONE) {
                    row.Channel__c = decision.channel;
                }
                if (decision.problem != null) {
                    problems.add(decision.problem);
                } else if (decision.template != null) {
                    row.Template__c = decision.template.Id;
                    if (decision.channel == AcknowledgmentRuleEngine.CHANNEL_LETTER) {
                        row.Letter__c = AcknowledgmentTemplateService.mergeBody(
                            decision.template.Body__c,
                            gift,
                            identity
                        );
                    } else {
                        row.Email_Template_Developer_Name__c = decision.template.Email_Template_Developer_Name__c;
                    }
                }
            }
            rows.add(row);
        }
        if (!problems.isEmpty()) {
            ErrorLogger.logMessages(problems, LOG_CONTEXT, ErrorLogger.SEVERITY_WARNING);
        }
        return rows;
    }

    /**
     * Written in user mode, like the automatic soft credits a gift produces, and with all or none
     * off so that one unwritable record does not lose the rest. What could not be written is
     * reported rather than thrown: the gift is acknowledged either way, and refusing the save
     * would punish the person doing the thanking for a permission they do not control.
     */
    private static void write(List<Acknowledgment__c> rows) {
        if (rows.isEmpty()) {
            return;
        }
        List<String> failures = new List<String>();
        List<Database.SaveResult> results = Database.insert(rows, false, AccessLevel.USER_MODE);
        for (Integer index = 0; index < results.size(); index++) {
            if (results[index].isSuccess()) {
                continue;
            }
            failures.add(
                String.format(
                    Label.Giving_Acknowledgment_NotRecorded,
                    new List<String>{
                        String.valueOf(rows[index].Gift__c),
                        firstMessage(results[index])
                    }
                )
            );
        }
        if (!failures.isEmpty()) {
            ErrorLogger.logMessages(failures, LOG_CONTEXT, ErrorLogger.SEVERITY_WARNING);
        }
    }

    private static String firstMessage(Database.SaveResult result) {
        List<Database.Error> errors = result.getErrors();
        return errors.isEmpty() ? '' : errors[0].getMessage();
    }

    /** The attributes a rule can look at. Anything else changing is not worth a re-evaluation. */
    private static Boolean criteriaChanged(Gift__c gift, Gift__c previous) {
        return gift.Amount__c != previous.Amount__c ||
            gift.Type__c != previous.Type__c ||
            gift.Appeal__c != previous.Appeal__c ||
            gift.Gift_Date__c != previous.Gift_Date__c ||
            gift.Status__c != previous.Status__c ||
            gift.Donor_Contact__c != previous.Donor_Contact__c ||
            gift.Donor_Account__c != previous.Donor_Account__c;
    }
}

/**
 * Which rule is about this gift, and therefore how the donor is thanked.
 *
 * The whole of R-AK1 to R-AK4 lives here and nowhere else: active rules in evaluation order, then
 * name, first match wins, an empty criterion matches everything, amounts inclusive at the bottom
 * and exclusive at the top, and a first gift is one with no earlier gift from the same donor.
 *
 * Decisions come back positionally rather than by record id, because the before insert pass asks
 * this question about gifts that do not have an id yet. One call, one list in, one list of the same
 * length out.
 *
 * Nothing here writes anything, and nothing here sends anything (R-AK8).
 */
public with sharing class AcknowledgmentRuleEngine {
    public static final String CHANNEL_EMAIL = 'Email';
    public static final String CHANNEL_LETTER = 'Letter';
    public static final String CHANNEL_NONE = 'None';

    /** What the rules say about one gift, or null when no rule matched it (R-AK5). */
    public class Decision {
        public Acknowledgment_Rule__c rule;
        public Acknowledgment_Template__c template;
        public String channel;

        /**
         * Why the wording could not be used, ready for the Error Log, or null when it could
         * (R-AT4). The before save pass ignores this, because at that point no wording is needed
         * yet and reporting a configuration mistake on every gift entry would bury it.
         */
        public String problem;
    }

    /**
     * The rule for each gift, in the order the gifts were given. An organization that has written
     * no rules gets a list of nulls and no queries beyond the first.
     */
    public static List<Decision> decide(List<Gift__c> gifts) {
        List<Decision> decisions = new List<Decision>();
        if (gifts == null || gifts.isEmpty()) {
            return decisions;
        }
        List<Acknowledgment_Rule__c> rules = AcknowledgmentSelector.activeRules();
        if (rules.isEmpty()) {
            for (Integer index = 0; index < gifts.size(); index++) {
                decisions.add(null);
            }
            return decisions;
        }

        Map<Id, Date> earliestByDonor = anyRuleAsksAboutFirstGifts(rules)
            ? AcknowledgmentSelector.earliestGiftDateByDonor(donorIds(gifts))
            : new Map<Id, Date>();

        for (Gift__c gift : gifts) {
            decisions.add(decideOne(gift, rules, earliestByDonor));
        }
        return decisions;
    }

    private static Decision decideOne(
        Gift__c gift,
        List<Acknowledgment_Rule__c> rules,
        Map<Id, Date> earliestByDonor
    ) {
        for (Acknowledgment_Rule__c rule : rules) {
            if (!matches(rule, gift, earliestByDonor)) {
                continue;
            }
            Decision decision = new Decision();
            decision.rule = rule;
            decision.channel = rule.Channel__c;
            resolveTemplate(decision);
            return decision;
        }
        return null;
    }

    /** R-AK2: every criterion an administrator left empty is a criterion that matches. */
    private static Boolean matches(
        Acknowledgment_Rule__c rule,
        Gift__c gift,
        Map<Id, Date> earliestByDonor
    ) {
        if (!amountInRange(rule, gift.Amount__c)) {
            return false;
        }
        if (String.isNotBlank(rule.Gift_Type__c) && rule.Gift_Type__c != gift.Type__c) {
            return false;
        }
        if (rule.Appeal__c != null && rule.Appeal__c != gift.Appeal__c) {
            return false;
        }
        if (rule.First_Gift_Only__c == true && !isFirstGift(gift, earliestByDonor)) {
            return false;
        }
        return true;
    }

    /**
     * R-AK3: a gift of exactly the minimum matches, a gift of exactly the maximum belongs to the
     * next rule up. A gift with no amount matches only a rule that asked about no amounts.
     */
    private static Boolean amountInRange(Acknowledgment_Rule__c rule, Decimal amount) {
        Boolean bounded = rule.Minimum_Amount__c != null || rule.Maximum_Amount__c != null;
        if (!bounded) {
            return true;
        }
        if (amount == null) {
            return false;
        }
        if (rule.Minimum_Amount__c != null && amount < rule.Minimum_Amount__c) {
            return false;
        }
        if (rule.Maximum_Amount__c != null && amount >= rule.Maximum_Amount__c) {
            return false;
        }
        return true;
    }

    /**
     * R-AK4. The earliest date the donor has is read from the gifts, and a gift on that date is a
     * first gift, which is why two gifts on the same day are both first gifts: nothing separates
     * them. A gift being inserted is not yet in the query, so a donor with no earlier gift has no
     * entry at all and the gift is their first.
     */
    private static Boolean isFirstGift(Gift__c gift, Map<Id, Date> earliestByDonor) {
        if (gift.Gift_Date__c == null || !counted(gift)) {
            return false;
        }
        Id donorId = donorIdFor(gift);
        if (donorId == null) {
            return false;
        }
        Date earliest = earliestByDonor.get(donorId);
        return earliest == null || gift.Gift_Date__c <= earliest;
    }

    /** The same filter the earliest gift query uses, applied to the gift in front of us. */
    private static Boolean counted(Gift__c gift) {
        return gift.Amount__c != null &&
            gift.Amount__c > 0 &&
            AcknowledgmentSelector.COUNTED_STATUSES.contains(gift.Status__c);
    }

    /** R-AT4. A rule that names wording it cannot use decides the channel and nothing else. */
    private static void resolveTemplate(Decision decision) {
        if (decision.channel == CHANNEL_NONE) {
            return;
        }
        Acknowledgment_Template__c template = decision.rule.Template__r;
        if (
            template == null ||
            template.Active__c != true ||
            template.Channel__c != decision.channel
        ) {
            decision.problem = String.format(
                Label.Giving_Acknowledgment_TemplateUnusable,
                new List<String>{ decision.rule.Name }
            );
            return;
        }
        decision.template = template;
    }

    private static Boolean anyRuleAsksAboutFirstGifts(List<Acknowledgment_Rule__c> rules) {
        for (Acknowledgment_Rule__c rule : rules) {
            if (rule.First_Gift_Only__c == true) {
                return true;
            }
        }
        return false;
    }

    private static Set<Id> donorIds(List<Gift__c> gifts) {
        Set<Id> donors = new Set<Id>();
        for (Gift__c gift : gifts) {
            Id donorId = donorIdFor(gift);
            if (donorId != null) {
                donors.add(donorId);
            }
        }
        return donors;
    }

    /** A gift's donor is a contact or an account and never both (canonical model Section 4). */
    private static Id donorIdFor(Gift__c gift) {
        return gift.Donor_Contact__c != null ? gift.Donor_Contact__c : gift.Donor_Account__c;
    }
}

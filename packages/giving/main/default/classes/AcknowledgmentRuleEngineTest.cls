/**
 * Which rule is about which gift: R-AK1 to R-AK5, and the template resolution of R-AT4.
 *
 * The ladder in the setup is the one a real organization writes and the one the admin guide walks
 * through: thank a first gift with a letter whatever it is worth, say nothing for the small ones,
 * write to the major donors, and email everybody else. Every test here is about a gift falling
 * into the right rung of it.
 *
 * NOT EXECUTED. No Salesforce org was reachable from the environment this feature was built in, so
 * these tests have been written and compiled but never run.
 */
@IsTest
private class AcknowledgmentRuleEngineTest {
    private static final String LETTER_TEMPLATE = 'Warm letter';
    private static final String EMAIL_TEMPLATE = 'Standard thank you email';
    private static final Date LONG_AGO = Date.newInstance(2025, 1, 15);
    private static final Date TODAY_ISH = Date.newInstance(2026, 3, 1);

    @TestSetup
    static void makeData() {
        GivingTestDataFactory.insertDefaultFund();
        Appeal__c springAppeal = GivingTestDataFactory.buildAppeal('Spring Appeal');
        insert springAppeal;

        Contact ana = GivingTestDataFactory.insertHouseholdContact(
            'The Nolan Family',
            'Ana',
            'Nolan'
        );
        GivingTestDataFactory.insertHouseholdContact('The Okafor Family', 'Ben', 'Okafor');

        List<Acknowledgment_Template__c> templates = new List<Acknowledgment_Template__c>{
            new Acknowledgment_Template__c(
                Name = LETTER_TEMPLATE,
                Channel__c = AcknowledgmentRuleEngine.CHANNEL_LETTER,
                Body__c = 'Dear {{DonorFirstName}}, thank you for {{GiftAmount}}.',
                Active__c = true
            ),
            new Acknowledgment_Template__c(
                Name = EMAIL_TEMPLATE,
                Channel__c = AcknowledgmentRuleEngine.CHANNEL_EMAIL,
                Email_Template_Developer_Name__c = 'Thank_You_Standard',
                Active__c = true
            )
        };
        insert templates;
        Map<String, Id> templateIdByName = new Map<String, Id>();
        for (Acknowledgment_Template__c template : templates) {
            templateIdByName.put(template.Name, template.Id);
        }

        insert new List<Acknowledgment_Rule__c>{
            new Acknowledgment_Rule__c(
                Name = 'First gifts',
                Evaluation_Order__c = 10,
                First_Gift_Only__c = true,
                Channel__c = AcknowledgmentRuleEngine.CHANNEL_LETTER,
                Template__c = templateIdByName.get(LETTER_TEMPLATE),
                Active__c = true
            ),
            new Acknowledgment_Rule__c(
                Name = 'No thank you for small gifts',
                Evaluation_Order__c = 20,
                Maximum_Amount__c = 50,
                Channel__c = AcknowledgmentRuleEngine.CHANNEL_NONE,
                Active__c = true
            ),
            new Acknowledgment_Rule__c(
                Name = 'Major gifts',
                Evaluation_Order__c = 30,
                Minimum_Amount__c = 1000,
                Channel__c = AcknowledgmentRuleEngine.CHANNEL_LETTER,
                Template__c = templateIdByName.get(LETTER_TEMPLATE),
                Active__c = true
            ),
            new Acknowledgment_Rule__c(
                Name = 'Everything else',
                Evaluation_Order__c = 40,
                Channel__c = AcknowledgmentRuleEngine.CHANNEL_EMAIL,
                Template__c = templateIdByName.get(EMAIL_TEMPLATE),
                Active__c = true
            )
        };

        // Ana has given before. Ben has not. That is the whole of the first gift question.
        Gift__c earlier = GivingTestDataFactory.buildGift(ana.Id, 100);
        earlier.Gift_Date__c = LONG_AGO;
        insert earlier;
    }

    private static Contact donor(String lastName) {
        return [SELECT Id FROM Contact WHERE LastName = :lastName LIMIT 1];
    }

    private static Gift__c giftFrom(Contact person, Decimal amount) {
        Gift__c gift = GivingTestDataFactory.buildGift(person.Id, amount);
        gift.Gift_Date__c = TODAY_ISH;
        return gift;
    }

    private static AcknowledgmentRuleEngine.Decision decisionFor(Gift__c gift) {
        return AcknowledgmentRuleEngine.decide(new List<Gift__c>{ gift })[0];
    }

    /** R-AK1: the first rule that matches wins, so a first gift of 25 is a letter, not silence. */
    @IsTest
    static void firstMatchWinsOverALaterRuleThatAlsoMatches() {
        Gift__c bensFirst = giftFrom(donor('Okafor'), 25);

        Test.startTest();
        AcknowledgmentRuleEngine.Decision decision = decisionFor(bensFirst);
        Test.stopTest();

        Assert.isNotNull(decision, 'A first gift matches the first gift rule.');
        Assert.areEqual('First gifts', decision.rule.Name, 'The lowest ordered match decides.');
        Assert.areEqual(
            AcknowledgmentRuleEngine.CHANNEL_LETTER,
            decision.channel,
            'The first gift rule writes a letter.'
        );
        Assert.isNotNull(decision.template, 'An active letter template resolves.');
        Assert.isNull(decision.problem, 'Nothing is wrong with this configuration.');
    }

    /** R-AK4: a donor who has given before is not giving a first gift. */
    @IsTest
    static void aDonorWhoHasGivenBeforeFallsPastTheFirstGiftRule() {
        Gift__c anasSecond = giftFrom(donor('Nolan'), 25);

        Test.startTest();
        AcknowledgmentRuleEngine.Decision decision = decisionFor(anasSecond);
        Test.stopTest();

        Assert.areEqual(
            'No thank you for small gifts',
            decision.rule.Name,
            'A small repeat gift falls to the small gift rule.'
        );
        Assert.areEqual(
            AcknowledgmentRuleEngine.CHANNEL_NONE,
            decision.channel,
            'That rule asks for no thank you at all.'
        );
        Assert.isNull(decision.template, 'A channel of None names no wording.');
    }

    /** R-AK3: the maximum is exclusive, so a gift of exactly 50 is not a small gift. */
    @IsTest
    static void aGiftOfExactlyTheMaximumBelongsToTheNextRuleUp() {
        Gift__c onTheBoundary = giftFrom(donor('Nolan'), 50);

        Test.startTest();
        AcknowledgmentRuleEngine.Decision decision = decisionFor(onTheBoundary);
        Test.stopTest();

        Assert.areEqual(
            'Everything else',
            decision.rule.Name,
            'Fifty is past the small gift rule and under the major gift rule.'
        );
        Assert.areEqual(
            AcknowledgmentRuleEngine.CHANNEL_EMAIL,
            decision.channel,
            'Everything else is emailed.'
        );
    }

    /** R-AK3: the minimum is inclusive, so a gift of exactly 1000 is a major gift. */
    @IsTest
    static void aGiftOfExactlyTheMinimumMatchesTheRule() {
        Gift__c major = giftFrom(donor('Nolan'), 1000);

        Test.startTest();
        AcknowledgmentRuleEngine.Decision decision = decisionFor(major);
        Test.stopTest();

        Assert.areEqual('Major gifts', decision.rule.Name, 'One thousand reaches the rung.');
    }

    /** R-AK2: a criterion an administrator left empty matches everything. */
    @IsTest
    static void anEmptyCriterionMatchesEverything() {
        Gift__c ordinary = giftFrom(donor('Nolan'), 500);
        ordinary.Type__c = 'Card';

        Test.startTest();
        AcknowledgmentRuleEngine.Decision decision = decisionFor(ordinary);
        Test.stopTest();

        Assert.areEqual(
            'Everything else',
            decision.rule.Name,
            'The catch-all rule names no amount, no type and no appeal, so it matches anything.'
        );
    }

    /** A rule that names a gift type is only about that gift type. */
    @IsTest
    static void aGiftTypeCriterionExcludesOtherTypes() {
        Acknowledgment_Rule__c stockRule = new Acknowledgment_Rule__c(
            Name = 'Stock gifts get a call, not a letter',
            Evaluation_Order__c = 5,
            Gift_Type__c = 'Stock',
            Channel__c = AcknowledgmentRuleEngine.CHANNEL_NONE,
            Active__c = true
        );
        insert stockRule;

        Gift__c check = giftFrom(donor('Nolan'), 5000);
        Gift__c stock = giftFrom(donor('Nolan'), 5000);
        stock.Type__c = 'Stock';

        Test.startTest();
        List<AcknowledgmentRuleEngine.Decision> decisions = AcknowledgmentRuleEngine.decide(
            new List<Gift__c>{ check, stock }
        );
        Test.stopTest();

        Assert.areEqual('Major gifts', decisions[0].rule.Name, 'A check is not stock.');
        Assert.areEqual(
            'Stock gifts get a call, not a letter',
            decisions[1].rule.Name,
            'Stock matches the rule that asked for stock.'
        );
    }

    /** A rule that names an appeal is only about gifts to that appeal. */
    @IsTest
    static void anAppealCriterionExcludesGiftsToOtherAppeals() {
        Appeal__c spring = [SELECT Id FROM Appeal__c WHERE Name = 'Spring Appeal' LIMIT 1];
        insert new Acknowledgment_Rule__c(
            Name = 'Spring Appeal donors',
            Evaluation_Order__c = 5,
            Appeal__c = spring.Id,
            Channel__c = AcknowledgmentRuleEngine.CHANNEL_NONE,
            Active__c = true
        );

        Gift__c toSpring = giftFrom(donor('Nolan'), 500);
        toSpring.Appeal__c = spring.Id;
        Gift__c toNothing = giftFrom(donor('Nolan'), 500);

        Test.startTest();
        List<AcknowledgmentRuleEngine.Decision> decisions = AcknowledgmentRuleEngine.decide(
            new List<Gift__c>{ toSpring, toNothing }
        );
        Test.stopTest();

        Assert.areEqual('Spring Appeal donors', decisions[0].rule.Name, 'The appeal matches.');
        Assert.areEqual(
            'Everything else',
            decisions[1].rule.Name,
            'A gift with no appeal does not match a rule that named one.'
        );
    }

    /** R-AK5: an organization that has written no rules gets no opinion and no error. */
    @IsTest
    static void noRulesMeansNoDecision() {
        delete [SELECT Id FROM Acknowledgment_Rule__c];
        Gift__c gift = giftFrom(donor('Nolan'), 500);

        Test.startTest();
        List<AcknowledgmentRuleEngine.Decision> decisions = AcknowledgmentRuleEngine.decide(
            new List<Gift__c>{ gift }
        );
        Test.stopTest();

        Assert.areEqual(1, decisions.size(), 'One gift in, one answer out.');
        Assert.isNull(decisions[0], 'No rule matched, so the package has no opinion.');
    }

    /** An inactive rule is not tested at all. */
    @IsTest
    static void anInactiveRuleIsNotTested() {
        Acknowledgment_Rule__c smallGifts = [
            SELECT Id
            FROM Acknowledgment_Rule__c
            WHERE Name = 'No thank you for small gifts'
            LIMIT 1
        ];
        smallGifts.Active__c = false;
        update smallGifts;

        Gift__c small = giftFrom(donor('Nolan'), 25);

        Test.startTest();
        AcknowledgmentRuleEngine.Decision decision = decisionFor(small);
        Test.stopTest();

        Assert.areEqual(
            'Everything else',
            decision.rule.Name,
            'With the small gift rule switched off, a small gift falls to the catch-all.'
        );
    }

    /** R-AT4: a rule whose wording is switched off decides the channel and reports the problem. */
    @IsTest
    static void wordingThatIsSwitchedOffIsReportedAndTheChannelStands() {
        Acknowledgment_Template__c letter = [
            SELECT Id, Active__c
            FROM Acknowledgment_Template__c
            WHERE Name = :LETTER_TEMPLATE
            LIMIT 1
        ];
        letter.Active__c = false;
        update letter;

        Gift__c major = giftFrom(donor('Nolan'), 5000);

        Test.startTest();
        AcknowledgmentRuleEngine.Decision decision = decisionFor(major);
        Test.stopTest();

        Assert.areEqual('Major gifts', decision.rule.Name, 'The rule still matched.');
        Assert.isNull(decision.template, 'Wording that is switched off is not used.');
        Assert.isNotNull(decision.problem, 'The administrator is told which rule is wrong.');
        Assert.isTrue(
            decision.problem.contains('Major gifts'),
            'The message names the rule so it can be found.'
        );
    }

    /** R-AT4 again, from the other side: a letter rule pointing at email wording is a mismatch. */
    @IsTest
    static void wordingForTheOtherChannelIsReported() {
        Acknowledgment_Template__c emailWording = [
            SELECT Id
            FROM Acknowledgment_Template__c
            WHERE Name = :EMAIL_TEMPLATE
            LIMIT 1
        ];
        Acknowledgment_Rule__c majorGifts = [
            SELECT Id, Template__c
            FROM Acknowledgment_Rule__c
            WHERE Name = 'Major gifts'
            LIMIT 1
        ];
        majorGifts.Template__c = emailWording.Id;
        update majorGifts;

        Gift__c major = giftFrom(donor('Nolan'), 5000);

        Test.startTest();
        AcknowledgmentRuleEngine.Decision decision = decisionFor(major);
        Test.stopTest();

        Assert.isNull(decision.template, 'Email wording does not serve a letter rule.');
        Assert.isNotNull(decision.problem, 'The mismatch is reported.');
    }

    /** A gift from an organization is decided the same way a gift from a person is. */
    @IsTest
    static void anOrganizationGiftIsDecidedToo() {
        Account trust = GivingTestDataFactory.insertOrganization('Riverside Community Trust');
        Gift__c grant = GivingTestDataFactory.buildAccountGift(trust.Id, 5000);
        grant.Gift_Date__c = TODAY_ISH;

        Test.startTest();
        AcknowledgmentRuleEngine.Decision decision = decisionFor(grant);
        Test.stopTest();

        Assert.areEqual(
            'First gifts',
            decision.rule.Name,
            'The trust has never given, so this is its first gift.'
        );
    }

    /** Two hundred gifts in one call stay inside the platform's limits (plan Section 7.2). */
    @IsTest
    static void twoHundredGiftsAreDecidedInOneCall() {
        Contact ana = donor('Nolan');
        List<Gift__c> gifts = GivingTestDataFactory.buildGifts(ana.Id, 200, 25);
        for (Gift__c gift : gifts) {
            gift.Gift_Date__c = TODAY_ISH;
        }

        Test.startTest();
        List<AcknowledgmentRuleEngine.Decision> decisions = AcknowledgmentRuleEngine.decide(gifts);
        Test.stopTest();

        Assert.areEqual(200, decisions.size(), 'Every gift gets an answer.');
        for (AcknowledgmentRuleEngine.Decision decision : decisions) {
            Assert.areEqual(
                AcknowledgmentRuleEngine.CHANNEL_NONE,
                decision.channel,
                'Every one of them is a small repeat gift.'
            );
        }
    }
}

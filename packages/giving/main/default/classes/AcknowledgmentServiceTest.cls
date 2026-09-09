/**
 * What a save does: R-AK6 and R-AK7 on the way in, R-AC1 to R-AC3 on the way out, and R-AT2 on the
 * wording in between.
 *
 * These tests go through real DML on gifts rather than calling the handler, because the thing worth
 * proving is that marking a gift acknowledged records the thank you whatever moved the field. That
 * is the whole design: David does the sending outside Salesforce and changes a status here, and it
 * has to work from a record page, a list view, an import or the API, which are all the same save.
 *
 * Nothing here asserts that an email was sent, because nothing sends one (R-AK8).
 *
 * NOT EXECUTED. No Salesforce org was reachable from the environment this feature was built in, so
 * these tests have been written and compiled but never run.
 */
@IsTest
private class AcknowledgmentServiceTest {
    private static final String LETTER_TEMPLATE = 'Major donor letter';
    private static final String EMAIL_TEMPLATE = 'Standard thank you email';
    private static final String EMAIL_DEVELOPER_NAME = 'Thank_You_Standard';
    private static final Date GIFT_DAY = Date.newInstance(2026, 3, 1);

    @TestSetup
    static void makeData() {
        Nonprofit_Settings__c core = Nonprofit_Settings__c.getOrgDefaults();
        core.SetupOwnerId = UserInfo.getOrganizationId();
        core.Organization_Legal_Name__c = 'Hope For Homes';
        core.Receipt_Signer_Name__c = 'Tom Alvarez';
        core.Receipt_Signer_Title__c = 'Executive Director';
        upsert core;

        GivingTestDataFactory.insertDefaultFund();
        GivingTestDataFactory.insertHouseholdContact('The Nolan Family', 'Ana', 'Nolan');

        List<Acknowledgment_Template__c> templates = new List<Acknowledgment_Template__c>{
            new Acknowledgment_Template__c(
                Name = LETTER_TEMPLATE,
                Channel__c = AcknowledgmentRuleEngine.CHANNEL_LETTER,
                Body__c = 'Dear {{DonorFirstName}}, thank you for your gift of {{GiftAmount}} ' +
                    'to {{OrganizationName}}. {{SignerName}}, {{SignerTitle}}. {{NotAToken}}',
                Active__c = true
            ),
            new Acknowledgment_Template__c(
                Name = EMAIL_TEMPLATE,
                Channel__c = AcknowledgmentRuleEngine.CHANNEL_EMAIL,
                Email_Template_Developer_Name__c = EMAIL_DEVELOPER_NAME,
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
                Name = 'No thank you for small gifts',
                Evaluation_Order__c = 10,
                Maximum_Amount__c = 50,
                Channel__c = AcknowledgmentRuleEngine.CHANNEL_NONE,
                Active__c = true
            ),
            new Acknowledgment_Rule__c(
                Name = 'Major gifts',
                Evaluation_Order__c = 20,
                Minimum_Amount__c = 1000,
                Channel__c = AcknowledgmentRuleEngine.CHANNEL_LETTER,
                Template__c = templateIdByName.get(LETTER_TEMPLATE),
                Active__c = true
            ),
            new Acknowledgment_Rule__c(
                Name = 'Everything else',
                Evaluation_Order__c = 30,
                Channel__c = AcknowledgmentRuleEngine.CHANNEL_EMAIL,
                Template__c = templateIdByName.get(EMAIL_TEMPLATE),
                Active__c = true
            )
        };
    }

    private static Contact ana() {
        return [SELECT Id FROM Contact WHERE LastName = 'Nolan' LIMIT 1];
    }

    private static Gift__c insertGift(Decimal amount) {
        Gift__c gift = GivingTestDataFactory.buildGift(ana().Id, amount);
        gift.Gift_Date__c = GIFT_DAY;
        insert gift;
        return gift;
    }

    private static Gift__c reread(Id giftId) {
        return [
            SELECT Id, Acknowledgment_Status__c, Acknowledgment_Date__c
            FROM Gift__c
            WHERE Id = :giftId
        ];
    }

    private static List<Acknowledgment__c> thankYousFor(Id giftId) {
        return AcknowledgmentSelector.forGift(giftId);
    }

    /** R-AK6: a rule that says no thank you is needed takes the gift out of the waiting list. */
    @IsTest
    static void aRuleWithNoChannelMarksTheGiftNotRequired() {
        Test.startTest();
        Gift__c small = insertGift(25);
        Test.stopTest();

        Assert.areEqual(
            AcknowledgmentService.STATUS_NOT_REQUIRED,
            reread(small.Id).Acknowledgment_Status__c,
            'A gift under fifty needs no thank you here.'
        );
        Assert.areEqual(
            0,
            thankYousFor(small.Id).size(),
            'Nothing was thanked, so nothing is recorded.'
        );
    }

    /** R-AK5: a gift a rule wants thanked is left waiting for a person to do the thanking. */
    @IsTest
    static void aGiftToBeThankedStaysWaiting() {
        Test.startTest();
        Gift__c ordinary = insertGift(500);
        Test.stopTest();

        Gift__c saved = reread(ordinary.Id);
        Assert.areEqual(
            AcknowledgmentService.STATUS_TO_ACKNOWLEDGE,
            saved.Acknowledgment_Status__c,
            'Deciding is not sending: the gift waits for somebody to send the thank you.'
        );
        Assert.isNull(saved.Acknowledgment_Date__c, 'Nothing has been sent, so there is no date.');
    }

    /** R-AC1 and R-AC3: marking a gift acknowledged stamps the date and freezes the letter. */
    @IsTest
    static void markingAGiftAcknowledgedRecordsTheThankYou() {
        Gift__c major = insertGift(2500);

        Test.startTest();
        major.Acknowledgment_Status__c = AcknowledgmentService.STATUS_ACKNOWLEDGED;
        update major;
        Test.stopTest();

        Assert.areEqual(
            Date.today(),
            reread(major.Id).Acknowledgment_Date__c,
            'A gift marked acknowledged with no date is dated today.'
        );

        List<Acknowledgment__c> recorded = thankYousFor(major.Id);
        Assert.areEqual(1, recorded.size(), 'One thank you, one record.');
        Acknowledgment__c thankYou = recorded[0];
        Assert.areEqual(
            AcknowledgmentRuleEngine.CHANNEL_LETTER,
            thankYou.Channel__c,
            'A major gift is written to.'
        );
        Assert.areEqual(Date.today(), thankYou.Acknowledged_Date__c, 'The dates agree.');
        Assert.isNotNull(thankYou.Rule__c, 'The rule that matched is recorded.');
        Assert.isNotNull(thankYou.Template__c, 'The wording that was used is recorded.');
        Assert.isTrue(thankYou.Letter__c.contains('Ana'), 'The donor is greeted by name.');
        Assert.isTrue(
            thankYou.Letter__c.contains('Hope For Homes'),
            'The organization signs its own letter.'
        );
        Assert.isTrue(
            thankYou.Letter__c.contains('Tom Alvarez'),
            'The signer named in settings signs it.'
        );
        Assert.isTrue(
            thankYou.Letter__c.contains('{{NotAToken}}'),
            'R-AT2: a token the package does not know is left exactly as it was typed.'
        );
        Assert.isTrue(
            String.isBlank(thankYou.Email_Template_Developer_Name__c),
            'A letter names no email template.'
        );
    }

    /** R-AT3: the email channel records which standard template applies and merges nothing. */
    @IsTest
    static void anEmailThankYouRecordsTheTemplateNameAndNoWording() {
        Gift__c ordinary = insertGift(500);

        Test.startTest();
        ordinary.Acknowledgment_Status__c = AcknowledgmentService.STATUS_ACKNOWLEDGED;
        update ordinary;
        Test.stopTest();

        Acknowledgment__c thankYou = thankYousFor(ordinary.Id)[0];
        Assert.areEqual(
            AcknowledgmentRuleEngine.CHANNEL_EMAIL,
            thankYou.Channel__c,
            'Everything else is emailed.'
        );
        Assert.areEqual(
            EMAIL_DEVELOPER_NAME,
            thankYou.Email_Template_Developer_Name__c,
            'The standard email template that applies is named on the record.'
        );
        Assert.isTrue(
            String.isBlank(thankYou.Letter__c),
            'The package does not merge or send the email, so it stores no guess at the wording.'
        );
    }

    /** R-AC1: a gift entered already acknowledged is recorded on the way in. */
    @IsTest
    static void aGiftEnteredAlreadyAcknowledgedIsRecorded() {
        Gift__c gift = GivingTestDataFactory.buildGift(ana().Id, 2500);
        gift.Gift_Date__c = GIFT_DAY;
        gift.Acknowledgment_Status__c = AcknowledgmentService.STATUS_ACKNOWLEDGED;

        Test.startTest();
        insert gift;
        Test.stopTest();

        Assert.areEqual(
            Date.today(),
            reread(gift.Id).Acknowledgment_Date__c,
            'The date is stamped on insert too.'
        );
        Assert.areEqual(1, thankYousFor(gift.Id).size(), 'And the record is written on insert.');
    }

    /** R-AC1: editing a gift that was already acknowledged does not invent a second thank you. */
    @IsTest
    static void editingAnAlreadyAcknowledgedGiftRecordsNothingFurther() {
        Gift__c major = insertGift(2500);
        major.Acknowledgment_Status__c = AcknowledgmentService.STATUS_ACKNOWLEDGED;
        update major;

        Test.startTest();
        major.Payment_Reference__c = 'Check 1182';
        update major;
        Test.stopTest();

        Assert.areEqual(
            1,
            thankYousFor(major.Id).size(),
            'The status did not change, so nothing was recorded again.'
        );
    }

    /** R-AC2: a donor thanked twice has two records, and neither of them is edited. */
    @IsTest
    static void aGiftThankedTwiceKeepsBothRecords() {
        Gift__c major = insertGift(2500);
        major.Acknowledgment_Status__c = AcknowledgmentService.STATUS_ACKNOWLEDGED;
        update major;

        Test.startTest();
        major.Acknowledgment_Status__c = AcknowledgmentService.STATUS_TO_ACKNOWLEDGE;
        major.Acknowledgment_Date__c = null;
        update major;
        major.Acknowledgment_Status__c = AcknowledgmentService.STATUS_ACKNOWLEDGED;
        update major;
        Test.stopTest();

        Assert.areEqual(
            2,
            thankYousFor(major.Id).size(),
            'Thanked twice is two records, which is the honest account of it.'
        );
    }

    /** R-AK7: a decision somebody made by hand is not reconsidered. */
    @IsTest
    static void aStatusSetByHandIsLeftAlone() {
        Gift__c small = GivingTestDataFactory.buildGift(ana().Id, 25);
        small.Gift_Date__c = GIFT_DAY;
        small.Acknowledgment_Status__c = 'Do not acknowledge';

        Test.startTest();
        insert small;
        small.Payment_Reference__c = 'Check 1183';
        update small;
        Test.stopTest();

        Assert.areEqual(
            'Do not acknowledge',
            reread(small.Id).Acknowledgment_Status__c,
            'The rules never overwrite a person.'
        );
    }

    /** R-AK7: a gift whose amount changes is reconsidered, because a rule can read the amount. */
    @IsTest
    static void changingTheAmountReconsidersTheGift() {
        Gift__c ordinary = insertGift(500);
        Assert.areEqual(
            AcknowledgmentService.STATUS_TO_ACKNOWLEDGE,
            reread(ordinary.Id).Acknowledgment_Status__c,
            'Five hundred is thanked by email.'
        );

        Test.startTest();
        ordinary.Amount__c = 25;
        update ordinary;
        Test.stopTest();

        Assert.areEqual(
            AcknowledgmentService.STATUS_NOT_REQUIRED,
            reread(ordinary.Id).Acknowledgment_Status__c,
            'Corrected down to twenty five, it falls under the small gift rule.'
        );
    }

    /** R-AT4: a rule whose wording is unusable still records that the gift was thanked. */
    @IsTest
    static void anUnusableTemplateStillRecordsTheThankYou() {
        Acknowledgment_Template__c letter = [
            SELECT Id, Active__c
            FROM Acknowledgment_Template__c
            WHERE Name = :LETTER_TEMPLATE
            LIMIT 1
        ];
        letter.Active__c = false;
        update letter;

        Gift__c major = insertGift(2500);

        Test.startTest();
        major.Acknowledgment_Status__c = AcknowledgmentService.STATUS_ACKNOWLEDGED;
        update major;
        Test.stopTest();

        List<Acknowledgment__c> recorded = thankYousFor(major.Id);
        Assert.areEqual(1, recorded.size(), 'The record of the thank you is not lost.');
        Assert.isNotNull(recorded[0].Rule__c, 'The rule that matched is still named.');
        Assert.isNull(recorded[0].Template__c, 'Wording that could not be used is not claimed.');
        Assert.isTrue(String.isBlank(recorded[0].Letter__c), 'And no letter is invented.');
    }

    /** R-AK5: an organization with no rules has every gift left exactly where it was. */
    @IsTest
    static void withNoRulesNothingIsDecided() {
        delete [SELECT Id FROM Acknowledgment_Rule__c];

        Test.startTest();
        Gift__c small = insertGift(25);
        Test.stopTest();

        Assert.areEqual(
            AcknowledgmentService.STATUS_TO_ACKNOWLEDGE,
            reread(small.Id).Acknowledgment_Status__c,
            'No rules means no opinion, not a default of silence.'
        );
    }

    /** Two hundred gifts in one save (plan Section 7.2). */
    @IsTest
    static void twoHundredGiftsInOneSaveAreAllDecided() {
        List<Gift__c> gifts = GivingTestDataFactory.buildGifts(ana().Id, 200, 25);
        for (Gift__c gift : gifts) {
            gift.Gift_Date__c = GIFT_DAY;
        }

        Test.startTest();
        insert gifts;
        Test.stopTest();

        Integer notRequired = [
            SELECT COUNT()
            FROM Gift__c
            WHERE Acknowledgment_Status__c = :AcknowledgmentService.STATUS_NOT_REQUIRED
        ];
        Assert.areEqual(200, notRequired, 'All two hundred were decided, not the first chunk.');
    }

    /** Two hundred gifts acknowledged in one save produce two hundred records. */
    @IsTest
    static void twoHundredGiftsAcknowledgedInOneSaveAreAllRecorded() {
        List<Gift__c> gifts = GivingTestDataFactory.buildGifts(ana().Id, 200, 2500);
        for (Gift__c gift : gifts) {
            gift.Gift_Date__c = GIFT_DAY;
        }
        insert gifts;

        Test.startTest();
        for (Gift__c gift : gifts) {
            gift.Acknowledgment_Status__c = AcknowledgmentService.STATUS_ACKNOWLEDGED;
        }
        update gifts;
        Test.stopTest();

        Assert.areEqual(
            200,
            [SELECT COUNT() FROM Acknowledgment__c],
            'One record each, written in one insert.'
        );
    }

    /** R-AT2: a gift with nothing to merge produces a letter with gaps, not an error. */
    @IsTest
    static void missingValuesMergeToNothingRatherThanFailing() {
        Test.startTest();
        String merged = AcknowledgmentTemplateService.mergeBody(
            'Dear {{DonorFirstName}}, thank you for {{GiftAmount}} on {{GiftDate}} ' +
            'to {{AppealName}}. {{Mystery}}',
            new Gift__c(),
            null
        );
        Test.stopTest();

        Assert.areEqual(
            'Dear , thank you for  on  to . {{Mystery}}',
            merged,
            'Known tokens empty, unknown tokens survive.'
        );
    }

    /** The token list the admin guide publishes is the list the merge actually supports. */
    @IsTest
    static void everyPublishedTokenIsMerged() {
        String body = String.join(AcknowledgmentTemplateService.supportedTokens(), ' ');

        Test.startTest();
        String merged = AcknowledgmentTemplateService.mergeBody(body, new Gift__c(), null);
        Test.stopTest();

        Assert.isTrue(
            String.isBlank(merged.trim()),
            'Every token the package publishes was replaced, so nothing is left but spaces.'
        );
    }
}

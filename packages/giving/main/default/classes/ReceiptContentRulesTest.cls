/**
 * The third of the three tests ADR-0016 names: **the IRS language is emitted by code.**
 *
 * An administrator can rewrite every word of the letter. These tests assert what they cannot
 * rewrite, so a template edit that deleted the substantiation language would still produce a valid
 * receipt, and a template edit that tried to assert a value for a gift of goods would not.
 *
 * They compose HTML and read it. PDF bytes are not asserted anywhere, for the reason ADR-0016
 * gives: they cannot be, so the manual visual check is part of the definition of done instead.
 */
@IsTest
private class ReceiptContentRulesTest {
    private static final Date GIFT_DATE = Date.newInstance(2026, 4, 12);

    @TestSetup
    static void setUp() {
        ReceiptTestDataFactory.setUpReceipting();
    }

    /**
     * A plain cash gift carries the no goods or services sentence, and states who issued it, how
     * much, and when. Those four are what makes a piece of paper a receipt.
     */
    @IsTest
    static void aPlainCashGiftRendersTheNoGoodsOrServicesSentence() {
        Gift__c gift = ReceiptTestDataFactory.plainCashGift(null, 250, GIFT_DATE);

        Test.startTest();
        String html = ReceiptContentBuilder.forGift(
            gift,
            'Ana Reyes',
            'HFH-2026-000001',
            Date.newInstance(2027, 1, 15),
            ReceiptTestDataFactory.perGiftTemplateBody()
        );
        Test.stopTest();

        Assert.isTrue(
            html.contains(ReceiptContentBuilder.SENTENCE_NO_GOODS),
            'The no goods or services sentence is on the receipt: ' + html
        );
        Assert.isTrue(html.contains('Hope For Homes'), 'The organization that issued it is named.');
        Assert.isTrue(html.contains('$250.00'), 'The amount is stated.');
        Assert.isTrue(html.contains('12 April 2026'), 'The date of the gift is stated.');
        Assert.isTrue(html.contains('HFH-2026-000001'), 'The receipt number is on the document.');
    }

    /**
     * A gift over the seventy five dollar threshold where the donor received something carries all
     * three parts of the quid pro quo disclosure: what they got, what the organization thinks it
     * was worth, and how much of the payment is deductible.
     */
    @IsTest
    static void aQuidProQuoGiftOverSeventyFiveRendersAllThreeParts() {
        Gift__c gift = ReceiptTestDataFactory.quidProQuoGift(
            null,
            200,
            40,
            'two tickets to the harvest dinner',
            GIFT_DATE
        );

        Test.startTest();
        String html = ReceiptContentBuilder.forGift(
            gift,
            'Kofi Osei',
            'HFH-2026-000002',
            Date.newInstance(2027, 1, 15),
            ReceiptTestDataFactory.perGiftTemplateBody()
        );
        Test.stopTest();

        Assert.isTrue(
            gift.Amount__c > ReceiptContentBuilder.QUID_PRO_QUO_THRESHOLD,
            'This is the case the disclosure is required for.'
        );
        Assert.isTrue(
            html.contains('two tickets to the harvest dinner'),
            'The benefit is described: ' + html
        );
        Assert.isTrue(html.contains('$40.00'), 'The good faith estimate of its value is stated.');
        Assert.isTrue(
            html.contains('$160.00'),
            'The deductible amount, the payment less the benefit, is stated.'
        );
        Assert.isFalse(
            html.contains(ReceiptContentBuilder.SENTENCE_NO_GOODS),
            'A receipt that discloses a benefit never also says none was provided.'
        );
    }

    /**
     * A gift where the only thing the donor received was an intangible religious benefit carries
     * that sentence, and not a value.
     */
    @IsTest
    static void anIntangibleReligiousBenefitGiftRendersItsOwnSentence() {
        Gift__c gift = ReceiptTestDataFactory.plainCashGift(null, 500, GIFT_DATE);
        gift.Intangible_Religious_Benefits__c = true;

        Test.startTest();
        String html = ReceiptContentBuilder.forGift(
            gift,
            'Petra Novak',
            'HFH-2026-000003',
            Date.newInstance(2027, 1, 15),
            ReceiptTestDataFactory.perGiftTemplateBody()
        );
        Test.stopTest();

        Assert.isTrue(
            html.contains(ReceiptContentBuilder.SENTENCE_INTANGIBLE_RELIGIOUS),
            'The intangible religious benefits sentence is on the receipt: ' + html
        );
        Assert.isFalse(
            html.contains(ReceiptContentBuilder.SENTENCE_NO_GOODS),
            'It replaces the no goods or services sentence rather than joining it.'
        );
    }

    /**
     * A gift of goods prints the donor's description and **no value the organization asserts**,
     * even though the organization has recorded a fair market value of its own for reporting.
     * Valuing donated property is the donor's responsibility.
     */
    @IsTest
    static void anInKindGiftRendersTheDescriptionAndNoOrganizationAssertedValue() {
        Gift__c gift = ReceiptTestDataFactory.inKindGift(
            null,
            'a used upright piano, delivered to the community hall',
            GIFT_DATE
        );

        Test.startTest();
        String html = ReceiptContentBuilder.forGift(
            gift,
            'Sam Whitfield',
            'HFH-2026-000004',
            Date.newInstance(2027, 1, 15),
            ReceiptTestDataFactory.perGiftTemplateBody()
        );
        Test.stopTest();

        Assert.isTrue(
            html.contains('a used upright piano, delivered to the community hall'),
            'What the donor gave is described on the receipt: ' + html
        );
        Assert.isFalse(
            html.contains('$900.00'),
            'The fair market value the organization recorded is never printed on the receipt.'
        );
        Assert.isTrue(
            html.contains('has not placed a value'),
            'The receipt says plainly that the organization has not valued the gift.'
        );
    }

    /**
     * A consolidated statement carries the status of every gift on that gift's own line (R-RC8).
     * A footer saying that some of the year's gifts were refunded is not something a reader can
     * act on.
     */
    @IsTest
    static void aConsolidatedStatementCarriesTheStatusOnEveryLine() {
        Gift__c received = ReceiptTestDataFactory.plainCashGift(
            null,
            100,
            Date.newInstance(2026, 2, 1)
        );
        Gift__c refunded = ReceiptTestDataFactory.plainCashGift(
            null,
            300,
            Date.newInstance(2026, 6, 1)
        );
        refunded.Status__c = 'Refunded';
        Gift__c writtenOff = ReceiptTestDataFactory.plainCashGift(
            null,
            50,
            Date.newInstance(2026, 9, 1)
        );
        writtenOff.Status__c = 'Written off';

        Test.startTest();
        String html = ReceiptContentBuilder.forStatement(
            'The Reyes Family',
            new List<Gift__c>{ received, refunded, writtenOff },
            'HFH-2026-000005',
            2026,
            Date.newInstance(2027, 1, 15),
            ReceiptTestDataFactory.statementTemplateBody()
        );
        Test.stopTest();

        for (String status : new List<String>{ 'Received', 'Refunded', 'Written off' }) {
            Assert.isTrue(
                html.contains('<td class="status">' + status + '</td>'),
                'The status ' + status + ' is on its own line: ' + html
            );
        }
        Assert.areEqual(
            3,
            html.countMatches('<td class="status">'),
            'Every line states a status, and no line is missing one.'
        );
        Assert.isTrue(html.contains('$450.00'), 'The total is the sum of the lines it prints.');
        Assert.isTrue(html.contains('$100.00'), 'The received gift is a line.');
        Assert.isTrue(html.contains('$300.00'), 'The refunded gift is still a line.');
    }
}

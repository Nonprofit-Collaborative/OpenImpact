/**
 * What an in-kind gift has to say about itself before it is allowed to be saved (R-G12, G-18).
 *
 * A gift of goods with no description gives the receipt nothing to print in place of an amount,
 * and a gift of money carrying a fair market value gives it goods to describe that nobody gave.
 * Both are cheap to refuse here and expensive to find later, on a document a donor has filed with
 * a tax return.
 *
 * **These tests have not been executed.** No Salesforce org was reachable while this feature was
 * built, so no Apex in this repository has been run and no validation rule has been deployed. They
 * are written to be run against the first org that exists.
 */
@IsTest
private class InKindGiftRulesTest {
    private static final String IN_KIND = 'In-kind';

    @TestSetup
    static void makeData() {
        GivingTestDataFactory.insertDefaultFund();
        GivingTestDataFactory.insertHouseholdContact('The Whitfield Family', 'Sam', 'Whitfield');
    }

    private static Contact donor() {
        return [SELECT Id FROM Contact LIMIT 1];
    }

    private static Gift__c inKindGift(Decimal value, String description) {
        Gift__c gift = GivingTestDataFactory.buildGift(donor().Id, value);
        gift.Type__c = IN_KIND;
        gift.Gift_Date__c = Date.today();
        gift.In_Kind_Description__c = description;
        gift.Fair_Market_Value__c = value;
        return gift;
    }

    /** What a correctly recorded gift of goods looks like, so the rest of the class has a control. */
    @IsTest
    static void anInKindGiftWithBothADescriptionAndAMatchingValueSaves() {
        Test.startTest();
        insert inKindGift(900, 'a used upright piano, delivered to the community hall');
        Test.stopTest();

        Gift__c saved = [
            SELECT Id, Type__c, Amount__c, Fair_Market_Value__c, In_Kind_Description__c
            FROM Gift__c
            LIMIT 1
        ];
        Assert.areEqual(IN_KIND, saved.Type__c, 'The gift is recorded as goods rather than money.');
        Assert.areEqual(
            saved.Amount__c,
            saved.Fair_Market_Value__c,
            'One gift carries one number (R-G12).'
        );
    }

    @IsTest
    static void anInKindGiftWithoutADescriptionIsRefused() {
        Gift__c gift = inKindGift(900, null);

        Test.startTest();
        DmlException refused = null;
        try {
            insert gift;
        } catch (DmlException failure) {
            refused = failure;
        }
        Test.stopTest();

        Assert.isNotNull(refused, 'A gift of goods that says nothing about them is refused.');
        Assert.isTrue(
            refused.getMessage().contains('Describe what was given'),
            'The message says what to do: ' + refused.getMessage()
        );
    }

    @IsTest
    static void anInKindGiftWithoutAFairMarketValueIsRefused() {
        Gift__c gift = inKindGift(900, 'Twelve cases of tinned food for the pantry');
        gift.Fair_Market_Value__c = null;

        Test.startTest();
        DmlException refused = null;
        try {
            insert gift;
        } catch (DmlException failure) {
            refused = failure;
        }
        Test.stopTest();

        Assert.isNotNull(refused, 'A gift of goods carries the value the organization records.');
        Assert.isTrue(
            refused.getMessage().contains('Enter a fair market value'),
            'The message names the field: ' + refused.getMessage()
        );
    }

    @IsTest
    static void anInKindGiftWhoseValueDisagreesWithItsAmountIsRefused() {
        Gift__c gift = inKindGift(900, 'Two laptops for the homework club');
        gift.Fair_Market_Value__c = 750;

        Test.startTest();
        DmlException refused = null;
        try {
            insert gift;
        } catch (DmlException failure) {
            refused = failure;
        }
        Test.stopTest();

        Assert.isNotNull(refused, 'Two figures for one gift would make two reports disagree.');
        Assert.isTrue(
            refused.getMessage().contains('the same number'),
            'The message says they are one number: ' + refused.getMessage()
        );
    }

    @IsTest
    static void aGiftOfMoneyCarryingInKindFieldsIsRefused() {
        Gift__c gift = GivingTestDataFactory.buildGift(donor().Id, 500);
        gift.Type__c = 'Cash';
        gift.In_Kind_Description__c = 'A used minibus in working order';

        Test.startTest();
        DmlException refused = null;
        try {
            insert gift;
        } catch (DmlException failure) {
            refused = failure;
        }
        Test.stopTest();

        Assert.isNotNull(refused, 'A cash receipt must not end up describing goods.');
        Assert.isTrue(
            refused.getMessage().contains('belong to a gift of goods or services'),
            'The message offers both ways out: ' + refused.getMessage()
        );
    }

    /**
     * The rules are on the gift that records the property, not on the negative gift that reverses
     * it (R-G3). A reversal copies the type and names the gift that carries the description, so a
     * refund of a gift of goods is recorded the way every other reversal is.
     */
    @IsTest
    static void aRefundOfAnInKindGiftIsNotAskedToDescribeTheGoodsAgain() {
        Gift__c original = inKindGift(900, 'a used upright piano, delivered to the community hall');
        insert original;

        Test.startTest();
        Id reversalId = GiftService.refund(original.Id, 900, 'The piano was returned unplayable');
        Test.stopTest();

        Gift__c reversal = [
            SELECT Id, Type__c, Amount__c, In_Kind_Description__c, Fair_Market_Value__c
            FROM Gift__c
            WHERE Id = :reversalId
        ];
        Assert.areEqual(
            IN_KIND,
            reversal.Type__c,
            'A reversal keeps the type of what it reverses.'
        );
        Assert.areEqual(-900, reversal.Amount__c, 'A reversal is a negative gift.');
        Assert.isNull(
            reversal.In_Kind_Description__c,
            'The description stays on the gift that recorded the property.'
        );
    }
}

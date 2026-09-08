/**
 * The receipt lock, from both sides.
 *
 * ADR-0010 says a receipted gift stops changing. ADR-0024 says that rule is not a setting: it
 * runs from an automation the console cannot switch off and a pause does not suspend, and the
 * only way past it is a custom permission the package grants to nobody, every use of which is
 * written to the Error Log.
 *
 * So these tests are about David, who cannot change a receipted gift however he tries, and about
 * the one afternoon Maria is given the override permission in Setup to correct a receipt that
 * was issued against the wrong donor, and finds that Open Impact wrote down what she did.
 */
@IsTest
private class GiftReceiptLockHandlerTest {
    private static final String OVERRIDE_PERMISSION = 'Override_Receipt_Lock';
    private static final String RECEIPT_NUMBER = 'R-2026-000042';

    @TestSetup
    static void makeData() {
        GivingTestDataFactory.insertDefaultFund();
        Contact donor = GivingTestDataFactory.insertHouseholdContact(
            'The Nolan Family',
            'Ana',
            'Nolan'
        );
        GivingTestDataFactory.insertHouseholdContact('The Okafor Family', 'Ben', 'Okafor');
        Gift__c gift = GivingTestDataFactory.buildGift(donor.Id, 250);
        gift.Gift_Date__c = Date.newInstance(2026, 3, 1);
        insert gift;
        // Issuing a number for the first time is allowed: that is what locks the gift.
        gift.Receipt_Number__c = RECEIPT_NUMBER;
        update gift;
    }

    private static Gift__c receiptedGift() {
        return [
            SELECT
                Id,
                Amount__c,
                Gift_Date__c,
                Donor_Contact__c,
                Donor_Account__c,
                Receipt_Number__c
            FROM Gift__c
            WHERE Receipt_Number__c = :RECEIPT_NUMBER
            LIMIT 1
        ];
    }

    private static Contact otherDonor() {
        return [SELECT Id FROM Contact WHERE LastName = 'Okafor' LIMIT 1];
    }

    /**
     * The permission set an administrator builds in Setup for the length of one correction, and
     * takes away again. Written inside `runAs` because a permission set is a setup object and the
     * test has already touched gifts.
     */
    private static User userHoldingTheOverride() {
        User maria = TestDataFactory.createUser(
            'Maria',
            new List<String>{ 'Nonprofit_Admin', 'Giving_Admin' }
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            PermissionSet granted = new PermissionSet(
                Name = 'Receipt_Lock_Override_Test',
                Label = 'Receipt lock override (test)'
            );
            insert granted;
            List<CustomPermission> permissions = [
                SELECT Id
                FROM CustomPermission
                WHERE DeveloperName = :OVERRIDE_PERMISSION
                LIMIT 1
            ];
            Assert.areEqual(
                1,
                permissions.size(),
                'The package ships the override permission, or there is nothing to grant.'
            );
            insert new SetupEntityAccess(ParentId = granted.Id, SetupEntityId = permissions[0].Id);
            insert new PermissionSetAssignment(AssigneeId = maria.Id, PermissionSetId = granted.Id);
        }
        return maria;
    }

    private static String refusalFrom(Gift__c gift) {
        try {
            update gift;
            return null;
        } catch (DmlException refused) {
            return refused.getDmlMessage(0);
        }
    }

    @IsTest
    static void theLockRefusesEachOfTheFourChangesThatWouldContradictTheReceipt() {
        Gift__c gift = receiptedGift();
        Id otherPerson = otherDonor().Id;

        Test.startTest();
        Gift__c amountChange = new Gift__c(Id = gift.Id, Amount__c = 300);
        String amountRefusal = refusalFrom(amountChange);

        Gift__c dateChange = new Gift__c(Id = gift.Id, Gift_Date__c = Date.newInstance(2026, 4, 1));
        String dateRefusal = refusalFrom(dateChange);

        Gift__c donorChange = new Gift__c(Id = gift.Id, Donor_Contact__c = otherPerson);
        String donorRefusal = refusalFrom(donorChange);

        Gift__c numberChange = new Gift__c(Id = gift.Id, Receipt_Number__c = 'R-2026-000099');
        String numberRefusal = refusalFrom(numberChange);
        Test.stopTest();

        Assert.isTrue(
            amountRefusal != null && amountRefusal.contains(Label.Giving_Gift_ReceiptLocked),
            'Changing the amount contradicts the document the donor holds.'
        );
        Assert.isTrue(
            dateRefusal != null && dateRefusal.contains(Label.Giving_Gift_ReceiptLocked),
            'So does changing the date the receipt states.'
        );
        Assert.isTrue(
            donorRefusal != null && donorRefusal.contains(Label.Giving_Gift_ReceiptLocked),
            'So does moving the gift to another donor.'
        );
        Assert.isTrue(
            numberRefusal != null && numberRefusal.contains(Label.Giving_Gift_ReceiptNumberLocked),
            'And the number itself is locked, or the lock could be lifted in two saves.'
        );

        Gift__c unchanged = receiptedGift();
        Assert.areEqual(250, unchanged.Amount__c, 'Nothing was saved: the amount is as receipted.');
        Assert.areEqual(
            Date.newInstance(2026, 3, 1),
            unchanged.Gift_Date__c,
            'And so is the date.'
        );
        Assert.areEqual(
            RECEIPT_NUMBER,
            unchanged.Receipt_Number__c,
            'And the receipt number is the one the donor is holding.'
        );
    }

    @IsTest
    static void theLockRefusesToDeleteAReceiptedGift() {
        Gift__c gift = receiptedGift();

        Test.startTest();
        String refusal;
        try {
            delete gift;
        } catch (DmlException refused) {
            refusal = refused.getDmlMessage(0);
        }
        Test.stopTest();

        Assert.isTrue(
            refusal != null && refusal.contains(Label.Giving_Gift_ReceiptedGiftNotDeletable),
            'A receipted gift is corrected by a refund or a reissue, never deleted.'
        );
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Gift__c WHERE Receipt_Number__c = :RECEIPT_NUMBER],
            'And the gift is still there.'
        );
    }

    @IsTest
    static void theLockStillRefusesWhileAllAutomationIsPaused() {
        TestDataFactory.pausedSettings(2);
        AutomationControl.clearCache();
        Gift__c gift = receiptedGift();

        Test.startTest();
        String refusal = refusalFrom(new Gift__c(Id = gift.Id, Amount__c = 400));
        Test.stopTest();

        Assert.isTrue(
            refusal != null && refusal.contains(Label.Giving_Gift_ReceiptLocked),
            'The pause stops Open Impact filling things in, never stops it refusing something.'
        );
        Assert.areEqual(
            250,
            receiptedGift().Amount__c,
            'So the amount a donor was receipted for did not move during the pause.'
        );
    }

    @IsTest
    static void theOverridePermissionLetsTheCorrectionThroughAndRecordsIt() {
        Gift__c gift = receiptedGift();
        Id otherPerson = otherDonor().Id;
        User maria = userHoldingTheOverride();

        Test.startTest();
        System.runAs(maria) {
            update new Gift__c(
                Id = gift.Id,
                Amount__c = 300,
                Gift_Date__c = Date.newInstance(2026, 4, 1),
                Donor_Contact__c = otherPerson
            );
        }
        Test.stopTest();

        Gift__c corrected = receiptedGift();
        Assert.areEqual(300, corrected.Amount__c, 'The correction was saved.');
        Assert.areEqual(
            Date.newInstance(2026, 4, 1),
            corrected.Gift_Date__c,
            'Every locked value the save carried was allowed through, not just the first.'
        );
        Assert.areEqual(otherPerson, corrected.Donor_Contact__c, 'Including the donor.');

        List<Error_Log__c> logged = [
            SELECT Message__c, Context__c, Severity__c, User__c
            FROM Error_Log__c
            WHERE Severity__c = :ErrorLogger.SEVERITY_WARNING
        ];
        Assert.areEqual(1, logged.size(), 'One overridden gift, one Error Log entry.');
        Assert.areEqual(
            'Receipt lock override',
            logged[0].Context__c,
            'Filed where an auditor looking for overrides will find it.'
        );
        Assert.areEqual(maria.Id, logged[0].User__c, 'Naming the person who made the change.');
        Assert.isTrue(
            logged[0].Message__c.contains(String.valueOf(gift.Id)),
            'The entry names the gift.'
        );
        Assert.isTrue(
            logged[0].Message__c.contains(RECEIPT_NUMBER),
            'And the receipt the donor is holding.'
        );
        Assert.isTrue(
            logged[0].Message__c.contains('amount') &&
                logged[0].Message__c.contains('gift date') &&
                logged[0].Message__c.contains('donor contact'),
            'And each value that moved, so the change can be reconstructed: ' + logged[0].Message__c
        );
    }

    @IsTest
    static void theOverridePermissionLetsAReceiptedGiftBeDeletedAndRecordsThat() {
        Gift__c gift = receiptedGift();
        User maria = userHoldingTheOverride();

        Test.startTest();
        System.runAs(maria) {
            delete gift;
        }
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Gift__c WHERE Receipt_Number__c = :RECEIPT_NUMBER],
            'The deletion went through for the one person holding the permission.'
        );
        List<Error_Log__c> logged = [
            SELECT Message__c, Severity__c
            FROM Error_Log__c
            WHERE Context__c = 'Receipt lock override'
        ];
        Assert.areEqual(1, logged.size(), 'And it was recorded.');
        Assert.areEqual(
            ErrorLogger.SEVERITY_WARNING,
            logged[0].Severity__c,
            'At Warning, which is what the Error Log page filters on.'
        );
        Assert.isTrue(
            logged[0].Message__c.contains('the gift was deleted'),
            'Saying what was done, not just that something was: ' + logged[0].Message__c
        );
    }

    @IsTest
    static void aGiftWithNoReceiptIsStillAnOrdinaryEditableGift() {
        Contact person = otherDonor();
        Gift__c plain = GivingTestDataFactory.buildGift(person.Id, 60);
        insert plain;

        Test.startTest();
        plain.Amount__c = 75;
        update plain;
        Test.stopTest();

        Assert.areEqual(
            75,
            [SELECT Amount__c FROM Gift__c WHERE Id = :plain.Id].Amount__c,
            'The lock is about receipts, not about gifts: a mistyped amount is still correctable.'
        );
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'Receipt lock override'],
            'And nothing was overridden, so nothing was recorded.'
        );
    }
}

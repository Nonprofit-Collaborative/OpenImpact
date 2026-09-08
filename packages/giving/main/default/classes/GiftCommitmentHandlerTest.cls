/**
 * Tests for the Gift handler that applies a gift to the payment it fulfills.
 */
@IsTest
private class GiftCommitmentHandlerTest {
    private static Contact donor() {
        Contact person = new Contact(FirstName = 'Sarah', LastName = 'Nguyen');
        insert person;
        return person;
    }

    private static Commitment__c pledgeWithSchedule(Id donorId) {
        Commitment__c pledge = new Commitment__c(
            Type__c = 'Pledge',
            Status__c = 'Active',
            Donor_Contact__c = donorId,
            Amount__c = 100,
            Frequency__c = 'Monthly',
            Start_Date__c = Date.newInstance(2026, 10, 1),
            Expected_Total__c = 300,
            Installments_Planned__c = 3
        );
        insert pledge;
        CommitmentService.generateInstallments(new Set<Id>{ pledge.Id });
        return pledge;
    }

    private static Gift__c giftFor(Id donorId, Id commitmentId, Id installmentId, Decimal amount) {
        return new Gift__c(
            Donor_Contact__c = donorId,
            Gift_Date__c = Date.newInstance(2026, 10, 1),
            Amount__c = amount,
            Type__c = 'Check',
            Status__c = 'Received',
            Commitment__c = commitmentId,
            Installment__c = installmentId
        );
    }

    @IsTest
    static void appliesGiftsOnInsert() {
        Contact person = donor();
        Commitment__c pledge = pledgeWithSchedule(person.Id);
        Installment__c first = [
            SELECT Id
            FROM Installment__c
            WHERE Commitment__c = :pledge.Id
            ORDER BY Sequence__c
            LIMIT 1
        ];
        Gift__c gift = giftFor(person.Id, pledge.Id, first.Id, 100);
        insert gift;

        Test.startTest();
        new GiftCommitmentHandler().onAfterInsert(new List<Gift__c>{ gift });
        Test.stopTest();

        Assert.areEqual(
            'Paid',
            [SELECT Status__c FROM Installment__c WHERE Id = :first.Id].Status__c,
            'A received gift pays the payment it names.'
        );
    }

    @IsTest
    static void recalculatesWhenAGiftIsRefunded() {
        Contact person = donor();
        Commitment__c pledge = pledgeWithSchedule(person.Id);
        Installment__c first = [
            SELECT Id
            FROM Installment__c
            WHERE Commitment__c = :pledge.Id
            ORDER BY Sequence__c
            LIMIT 1
        ];
        Gift__c gift = giftFor(person.Id, pledge.Id, first.Id, 100);
        insert gift;
        CommitmentService.applyGift(new List<Gift__c>{ gift });

        Map<Id, Gift__c> oldMap = new Map<Id, Gift__c>{ gift.Id => gift.clone(true, true) };
        gift.Status__c = 'Refunded';
        update gift;

        Test.startTest();
        new GiftCommitmentHandler().onAfterUpdate(new List<Gift__c>{ gift }, oldMap);
        Test.stopTest();

        Assert.areEqual(
            'Scheduled',
            [SELECT Status__c FROM Installment__c WHERE Id = :first.Id].Status__c,
            'A gift that is no longer received stops counting toward the payment.'
        );
    }

    @IsTest
    static void recalculatesTheInstallmentAGiftLeaves() {
        Contact person = donor();
        Commitment__c pledge = pledgeWithSchedule(person.Id);
        List<Installment__c> schedule = [
            SELECT Id
            FROM Installment__c
            WHERE Commitment__c = :pledge.Id
            ORDER BY Sequence__c
        ];
        Gift__c gift = giftFor(person.Id, pledge.Id, schedule[0].Id, 100);
        insert gift;
        CommitmentService.applyGift(new List<Gift__c>{ gift });

        Map<Id, Gift__c> oldMap = new Map<Id, Gift__c>{ gift.Id => gift.clone(true, true) };
        gift.Installment__c = schedule[1].Id;
        update gift;

        Test.startTest();
        new GiftCommitmentHandler().onAfterUpdate(new List<Gift__c>{ gift }, oldMap);
        Test.stopTest();

        Map<Id, Installment__c> byId = new Map<Id, Installment__c>(
            [SELECT Id, Status__c FROM Installment__c WHERE Commitment__c = :pledge.Id]
        );
        Assert.areEqual(
            'Scheduled',
            byId.get(schedule[0].Id).Status__c,
            'The payment the gift left goes back to Scheduled.'
        );
        Assert.areEqual(
            'Paid',
            byId.get(schedule[1].Id).Status__c,
            'The payment the gift moved to is now paid.'
        );
    }

    @IsTest
    static void ignoresAGiftThatHasNothingToDoWithACommitment() {
        Contact person = donor();
        Gift__c gift = giftFor(person.Id, null, null, 100);
        insert gift;

        Test.startTest();
        new GiftCommitmentHandler().onAfterInsert(new List<Gift__c>{ gift });
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Installment__c],
            'A one off gift creates and changes nothing here.'
        );
    }
}

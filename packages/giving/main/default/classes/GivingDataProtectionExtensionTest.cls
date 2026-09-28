/**
 * Giving's receipts and acknowledgment ledger are refused by every data job through Core's
 * extension seam, and its everyday records are not (ADR-0047 as amended 2026-09-28).
 */
@IsTest
private class GivingDataProtectionExtensionTest {
    @IsTest
    static void receiptsAndTheAcknowledgmentLedgerAreProtected() {
        Set<Schema.SObjectType> objects = new GivingDataProtectionExtension().protectedObjects();
        Assert.isTrue(objects.contains(Receipt__c.SObjectType));
        Assert.isTrue(objects.contains(Receipt_Run__c.SObjectType));
        Assert.isTrue(objects.contains(Receipt_Number_Sequence__c.SObjectType));
        Assert.isTrue(objects.contains(Acknowledgment__c.SObjectType));
        Assert.isTrue(objects.contains(Acknowledgment_Run__c.SObjectType));
    }

    @IsTest
    static void coreFindsItAndRefusesThoseObjects() {
        Assert.isTrue(
            DataProtectionExtensions.protectedObjects().contains(Receipt__c.SObjectType),
            'Core resolves Giving by name'
        );
        Assert.areEqual(
            Label.Core_BulkUpdate_ReasonBookkeeping,
            DataProtectedFields.objectReason(Receipt__c.SObjectType)
        );
        Assert.isNotNull(DataProtectedFields.objectRefusal(Acknowledgment__c.SObjectType));
        Assert.isNull(
            DataProtectedFields.objectRefusal(Gift__c.SObjectType),
            'a gift is an everyday record, protected field by field, not as an object'
        );
    }
}

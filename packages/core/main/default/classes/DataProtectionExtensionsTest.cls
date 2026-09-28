/**
 * A module's protected objects reach Core's protected list through the extension seam, and a
 * broken extension is left out without stopping anything (ADR-0047 as amended 2026-09-28).
 */
@IsTest
private class DataProtectionExtensionsTest {
    private class ProtectsMembers implements DataProtectionExtension {
        public Set<Schema.SObjectType> protectedObjects() {
            return new Set<Schema.SObjectType>{ Household_Member__c.SObjectType };
        }
    }

    private class Throws implements DataProtectionExtension {
        public Set<Schema.SObjectType> protectedObjects() {
            throw new System.TypeException('broken');
        }
    }

    @IsTest
    static void anObjectAnExtensionProtectsIsRefusedLikeCoresOwnBookkeeping() {
        DataProtectionExtensions.noneForTest = true;
        Assert.isNull(
            DataProtectedFields.objectRefusal(Household_Member__c.SObjectType),
            'without the extension a membership may be loaded'
        );

        DataProtectionExtensions.overrides.add(new ProtectsMembers());
        DataProtectionExtensions.reset();
        Assert.areEqual(
            String.format(
                Label.Core_Data_ObjectBookkeeping,
                new List<String>{ Household_Member__c.SObjectType.getDescribe().getLabelPlural() }
            ),
            DataProtectedFields.objectRefusal(Household_Member__c.SObjectType)
        );
        Assert.areEqual(
            Label.Core_BulkUpdate_ReasonBookkeeping,
            DataProtectedFields.objectReason(Household_Member__c.SObjectType)
        );
    }

    @IsTest
    static void anExtensionThatThrowsIsLeftOutAndTheOthersStillCount() {
        DataProtectionExtensions.noneForTest = true;
        DataProtectionExtensions.overrides.add(new Throws());
        DataProtectionExtensions.overrides.add(new ProtectsMembers());

        Set<Schema.SObjectType> objects = DataProtectionExtensions.protectedObjects();

        Assert.areEqual(new Set<Schema.SObjectType>{ Household_Member__c.SObjectType }, objects);
    }

    @IsTest
    static void noExtensionMeansNothingMoreIsProtected() {
        DataProtectionExtensions.noneForTest = true;

        Assert.isTrue(DataProtectionExtensions.protectedObjects().isEmpty());
        Assert.isNull(DataProtectedFields.objectRefusal(Contact.SObjectType));
    }
}

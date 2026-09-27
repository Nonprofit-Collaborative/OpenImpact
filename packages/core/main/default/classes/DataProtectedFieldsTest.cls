/**
 * What a data job may never write (R-IB15): the package's bookkeeping objects, what it computes
 * (including a rollup target added at run time), and what describe says nobody, or not this
 * person, may edit.
 */
@IsTest
private class DataProtectedFieldsTest {
    private static Schema.DescribeFieldResult field(Schema.SObjectType type, String name) {
        return type.getDescribe().fields.getMap().get(name.toLowerCase()).getDescribe();
    }

    @IsTest
    static void refusesThePackagesOwnBookkeepingAndSettings() {
        for (
            Schema.SObjectType type : new List<Schema.SObjectType>{
                Import_Batch__c.SObjectType,
                Import_Journal__c.SObjectType,
                Error_Log__c.SObjectType,
                Setting_Change__c.SObjectType,
                Barn_Settings__c.SObjectType,
                Rollup_Definition__c.SObjectType
            }
        ) {
            Assert.areEqual(
                Label.Core_BulkUpdate_ReasonBookkeeping,
                DataProtectedFields.objectReason(type),
                String.valueOf(type)
            );
        }
        Assert.isNull(DataProtectedFields.objectReason(Contact.SObjectType));
        Assert.isNull(DataProtectedFields.objectReason(Saved_Query__c.SObjectType));
    }

    @IsTest
    static void refusesWhatThePackageComputes() {
        Assert.areEqual(
            Label.Core_BulkUpdate_ReasonComputed,
            DataProtectedFields.fieldReason(
                Account.SObjectType,
                field(Account.SObjectType, 'Household_Formal_Greeting__c')
            )
        );
        Assert.areEqual(
            Label.Core_BulkUpdate_ReasonComputed,
            DataProtectedFields.fieldReason(Account.SObjectType, field(Account.SObjectType, 'Name'))
        );
        Assert.areEqual(
            Label.Core_BulkUpdate_ReasonComputed,
            DataProtectedFields.fieldReason(
                Contact.SObjectType,
                field(Contact.SObjectType, 'Created_By_Import_Batch__c')
            )
        );
        Assert.areEqual(
            Label.Core_BulkUpdate_ReasonComputed,
            DataProtectedFields.fieldReason(
                Saved_Query__c.SObjectType,
                field(Saved_Query__c.SObjectType, 'Query_JSON__c')
            )
        );
        Assert.isNull(
            DataProtectedFields.fieldReason(
                Contact.SObjectType,
                field(Contact.SObjectType, 'MailingCity')
            )
        );
    }

    @IsTest
    static void protectsARollupTargetWithoutACodeChange() {
        insert new Rollup_Definition__c(
            Name = 'Test target',
            Definition_Key__c = 'Test_Protected_Target',
            Source_Object__c = 'Household_Member__c',
            Target_Object__c = 'Contact',
            Relationship_Path__c = 'Contact__c',
            Aggregate__c = 'COUNT',
            Target_Field__c = 'Department',
            Mode__c = RollupService.MODE_BOTH,
            Fiscal_Year_Aware__c = false,
            Active__c = false
        );
        Assert.areEqual(
            Label.Core_BulkUpdate_ReasonComputed,
            DataProtectedFields.fieldReason(
                Contact.SObjectType,
                field(Contact.SObjectType, 'Department')
            ),
            'an inactive definition still protects its target'
        );
        Assert.isNull(
            DataProtectedFields.fieldReason(
                Contact.SObjectType,
                field(Contact.SObjectType, 'Title')
            ),
            'a field no rollup writes is not protected'
        );
    }

    @IsTest
    static void refusesAutoNumberAndSystemFields() {
        Assert.areEqual(
            Label.Core_BulkUpdate_ReasonAutoNumber,
            DataProtectedFields.fieldReason(
                Import_Batch__c.SObjectType,
                field(Import_Batch__c.SObjectType, 'Name')
            )
        );
        Assert.areEqual(
            Label.Core_BulkUpdate_ReasonSystem,
            DataProtectedFields.fieldReason(
                Contact.SObjectType,
                field(Contact.SObjectType, 'CreatedDate')
            )
        );
    }

    @IsTest
    static void refusesAFieldThePersonMayNotEdit() {
        User limited = TestDataFactory.createUser('Protfls', new List<String>{ 'Barn_Admin' });
        System.runAs(limited) {
            // BarnCRM Admin grants no access to this standard field (ImportFieldAccessTest).
            Assert.areEqual(
                Label.Core_BulkUpdate_ReasonNoFieldAccess,
                DataProtectedFields.fieldReason(
                    Contact.SObjectType,
                    field(Contact.SObjectType, 'AssistantName')
                )
            );
        }
    }
}

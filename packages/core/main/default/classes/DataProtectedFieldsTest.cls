/**
 * What data management never writes (canonical model R-IT12): the package's bookkeeping, the
 * objects Salesforce keeps, the fields the package or the platform keeps, every Rollup
 * Definition target, and a household's name.
 */
@IsTest
private class DataProtectedFieldsTest {
    @IsTest
    static void thePackagesBookkeepingIsNeverLoaded() {
        Test.startTest();
        String batches = DataProtectedFields.objectRefusal(Import_Batch__c.SObjectType);
        String journal = DataProtectedFields.objectRefusal(Import_Journal__c.SObjectType);
        String errors = DataProtectedFields.objectRefusal(Error_Log__c.SObjectType);
        String rollups = DataProtectedFields.objectRefusal(Rollup_Definition__c.SObjectType);
        Test.stopTest();

        Assert.areEqual(
            String.format(
                Label.Core_Data_ObjectBookkeeping,
                new List<String>{ Import_Batch__c.SObjectType.getDescribe().getLabelPlural() }
            ),
            batches,
            'Import batches are the package bookkeeping.'
        );
        Assert.isNotNull(journal, 'So is the journal.');
        Assert.isNotNull(errors, 'And the error log.');
        Assert.isNotNull(rollups, 'And the rollup definitions.');
    }

    @IsTest
    static void settingsEventsAndMissingObjectsAreRefusedAndPeopleDataIsNot() {
        Test.startTest();
        String settings = DataProtectedFields.objectRefusal(Barn_Settings__c.SObjectType);
        String event = DataProtectedFields.objectRefusal(Error_Log_Event__e.SObjectType);
        String missing = DataProtectedFields.objectRefusal(null);
        String users = DataProtectedFields.objectRefusal(User.SObjectType);
        String affiliations = DataProtectedFields.objectRefusal(Affiliation__c.SObjectType);
        String contacts = DataProtectedFields.objectRefusal(Contact.SObjectType);
        Test.stopTest();

        Assert.isNotNull(settings, 'A settings object is never loaded.');
        Assert.isNotNull(event, 'Nor a platform event.');
        Assert.areEqual(Label.Core_Data_ObjectUnknown, missing, 'Nor an object the org lacks.');
        Assert.areEqual(
            String.format(
                Label.Core_Data_ObjectSetup,
                new List<String>{ User.SObjectType.getDescribe().getLabelPlural() }
            ),
            users,
            'Users are managed in Setup, never loaded here.'
        );
        Assert.isNull(affiliations, 'Affiliations are the organization own records.');
        Assert.isNull(contacts, 'So are people.');
    }

    @IsTest
    static void theFieldsThePackageKeepsAreProtected() {
        Test.startTest();
        Set<String> accountFields = DataProtectedFields.fieldNames(Account.SObjectType);
        Set<String> contactFields = DataProtectedFields.fieldNames(Contact.SObjectType);
        Test.stopTest();

        for (
            Schema.SObjectField field : new List<Schema.SObjectField>{
                Account.Household_Formal_Greeting__c,
                Account.Household_Informal_Greeting__c,
                Account.Member_Count__c,
                Account.Primary_Contact__c,
                Account.Created_By_Import_Batch__c,
                Account.CreatedDate,
                Account.LastModifiedById
            }
        ) {
            Assert.isTrue(
                accountFields.contains(field.getDescribe().getName().toLowerCase()),
                field.getDescribe().getName() + ' is kept by BarnCRM or Salesforce.'
            );
        }
        Assert.isTrue(
            contactFields.contains(
                Contact.Primary_Affiliation__c.getDescribe().getName().toLowerCase()
            ),
            'A person primary affiliation is kept by the affiliation upkeep.'
        );
        Assert.isFalse(
            accountFields.contains('name'),
            'An account name is not kept on every account.'
        );
        Assert.isFalse(contactFields.contains('email'), 'Nor is an email.');
        Assert.isTrue(
            DataProtectedFields.isProtected(Contact.SObjectType, 'CREATED_BY_IMPORT_BATCH__C'),
            'Asked ignoring case.'
        );
    }

    @IsTest
    static void everyRollupTargetIsProtectedWithoutCode() {
        DataProtectedFields.definitionsOverride = new List<Rollup_Definition__c>{
            new Rollup_Definition__c(Target_Object__c = 'Contact', Target_Field__c = 'Description'),
            new Rollup_Definition__c(Target_Object__c = 'Account', Target_Field__c = 'Site')
        };

        Test.startTest();
        Boolean description = DataProtectedFields.isProtected(Contact.SObjectType, 'Description');
        Boolean site = DataProtectedFields.isProtected(Account.SObjectType, 'Site');
        Boolean title = DataProtectedFields.isProtected(Contact.SObjectType, 'Title');
        Test.stopTest();

        Assert.isTrue(description, 'A rollup target on Contact is protected.');
        Assert.isTrue(site, 'And one on Account.');
        Assert.isFalse(title, 'A field no definition targets is not.');
    }

    @IsTest
    static void aHouseholdsNameIsProtectedAndAnOrganizationsIsNot() {
        Id householdType = HouseholdService.householdRecordTypeId();
        Id organizationType = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization')
            .getRecordTypeId();

        Test.startTest();
        Boolean household = DataProtectedFields.isProtectedOnRecord(
            Account.SObjectType,
            'Name',
            householdType
        );
        Boolean organization = DataProtectedFields.isProtectedOnRecord(
            Account.SObjectType,
            'Name',
            organizationType
        );
        Boolean other = DataProtectedFields.isProtectedOnRecord(
            Account.SObjectType,
            'Phone',
            householdType
        );
        Test.stopTest();

        Assert.isTrue(household, 'The household naming patterns keep a household name.');
        Assert.isFalse(organization, 'An organization name is its own to change.');
        Assert.isFalse(other, 'Only the name.');
    }

    // Bulk update's questions (C-35, R-IB17).

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

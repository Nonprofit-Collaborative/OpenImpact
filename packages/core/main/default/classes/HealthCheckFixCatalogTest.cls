/**
 * The six fixes themselves: what each one says it will do, and what it does (feature C-21).
 *
 * NOT EXECUTED. There was no Salesforce org reachable from the environment these tests were
 * written in, so they have been compiled and reviewed but never run against an org.
 *
 * The shipped defaults are custom metadata, which cannot be inserted, so the two selectors
 * that read them are given the rows a test chose through the injection points they already
 * carry. That is also what makes these assertions numbers the test picked rather than
 * whatever happens to be shipped on the day.
 */
@IsTest
private class HealthCheckFixCatalogTest {
    private static OrgShapeDetector.OrgShape npspShape() {
        OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
        shape.hasNpsp = true;
        return shape;
    }

    private static OrgShapeDetector.OrgShape personAccountsShape() {
        OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
        shape.hasPersonAccounts = true;
        return shape;
    }

    /** Two shipped rollups over objects every org has, so neither is skipped as inapplicable. */
    private static void shipTwoRollups() {
        RollupSelector.defaultsOverride = new List<Rollup_Definition_Default__mdt>{
            new Rollup_Definition_Default__mdt(
                DeveloperName = 'Test_Household_Gift_Count',
                MasterLabel = 'Household Gift Count',
                Definition_Key__c = 'test_household_gift_count',
                Source_Object__c = 'Contact',
                Target_Object__c = 'Account',
                Aggregate__c = 'COUNT',
                Target_Field__c = 'Member_Count__c',
                Default_Active__c = true
            ),
            new Rollup_Definition_Default__mdt(
                DeveloperName = 'Test_Household_Last_Gift',
                MasterLabel = 'Household Last Gift Date',
                Definition_Key__c = 'test_household_last_gift',
                Source_Object__c = 'Contact',
                Target_Object__c = 'Account',
                Aggregate__c = 'MAX',
                Source_Field__c = 'Birthdate',
                Target_Field__c = 'Anniversary__c',
                Default_Active__c = true
            )
        };
    }

    @IsTest
    static void theModeFixSaysWhichModeItWouldSetAndSetsIt() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();

        System.runAs(maria) {
            OrgShapeDetector.overrideShape = npspShape();

            Test.startTest();
            HealthCheckFix.Preview preview = HealthCheckFix.preview(
                HealthCheckFix.KEY_RECOMMENDED_MODE
            );
            HealthCheckFix.Result result = HealthCheckFix.apply(
                HealthCheckFix.KEY_RECOMMENDED_MODE
            );
            Test.stopTest();

            Assert.areEqual(1, preview.affected, 'One setting would change.');
            Assert.isTrue(
                preview.summary.contains(Label.Core_CoexistenceMode_Npsp),
                'The preview names the mode it would set: ' + preview.summary
            );
            Assert.areEqual(
                CoexistenceService.MODE_NPSP,
                CoexistenceService.getCurrentMode(),
                'And confirming it sets that mode.'
            );
            Assert.areEqual(1, result.changed, 'The result reports the one change.');
        }
    }

    @IsTest
    static void theModeFixHasNothingToDoWhenTheModeAlreadyMatches() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();

        System.runAs(maria) {
            OrgShapeDetector.overrideShape = npspShape();
            CoexistenceService.applyMode(CoexistenceService.MODE_NPSP);

            Test.startTest();
            HealthCheckFix.Preview preview = HealthCheckFix.preview(
                HealthCheckFix.KEY_RECOMMENDED_MODE
            );
            Test.stopTest();

            Assert.areEqual(0, preview.affected, 'The mode already matches.');
            Assert.areEqual(true, preview.nothingToDo, 'So there is nothing to press.');
        }
    }

    @IsTest
    static void theMembershipFixMovesMembershipToTheJunctionOnce() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();

        System.runAs(maria) {
            OrgShapeDetector.overrideShape = personAccountsShape();

            Test.startTest();
            HealthCheckFix.Result first = HealthCheckFix.apply(
                HealthCheckFix.KEY_JUNCTION_MEMBERSHIP
            );
            HealthCheckFix.Result second = HealthCheckFix.apply(
                HealthCheckFix.KEY_JUNCTION_MEMBERSHIP
            );
            Test.stopTest();

            Assert.areEqual(
                CoexistenceService.MEMBERSHIP_JUNCTION,
                CoexistenceService.getMembershipMode(),
                'Membership is stored on the junction.'
            );
            Assert.areEqual(1, first.changed, 'The first press changed it.');
            Assert.areEqual(0, second.changed, 'The second press changed nothing.');
        }
    }

    @IsTest
    static void theRollupFixNamesWhatIsMissingAndCreatesExactlyThat() {
        shipTwoRollups();

        Test.startTest();
        HealthCheckFix.Preview preview = HealthCheckFix.preview(HealthCheckFix.KEY_SHIPPED_ROLLUPS);
        HealthCheckFix.Result result = HealthCheckFix.apply(HealthCheckFix.KEY_SHIPPED_ROLLUPS);
        Test.stopTest();

        Assert.areEqual(2, preview.affected, 'Both shipped rollups are missing.');
        Assert.areEqual(2, preview.items.size(), 'And the preview names both.');
        Assert.isTrue(
            preview.items.contains('Household Gift Count'),
            'By the name the administrator will see: ' + preview.items
        );
        Assert.areEqual(2, result.changed, 'Both were created.');
        List<Rollup_Definition__c> created = [
            SELECT Definition_Key__c, Is_Package_Default__c
            FROM Rollup_Definition__c
            WHERE Definition_Key__c LIKE 'test_household%'
        ];
        Assert.areEqual(2, created.size(), 'Two definitions, matching the two shipped rows.');
        Assert.areEqual(
            true,
            created[0].Is_Package_Default__c,
            'Marked as shipped by the package.'
        );
    }

    @IsTest
    static void theRollupFixLeavesAnEditedRollupAloneAndAddsOnlyTheMissingOne() {
        shipTwoRollups();
        insert new Rollup_Definition__c(
            Name = 'A name Maria chose',
            Definition_Key__c = 'test_household_gift_count',
            Source_Object__c = 'Contact',
            Target_Object__c = 'Account',
            Aggregate__c = 'COUNT',
            Target_Field__c = 'Member_Count__c',
            Active__c = false
        );

        Test.startTest();
        HealthCheckFix.Preview preview = HealthCheckFix.preview(HealthCheckFix.KEY_SHIPPED_ROLLUPS);
        HealthCheckFix.apply(HealthCheckFix.KEY_SHIPPED_ROLLUPS);
        Test.stopTest();

        Assert.areEqual(1, preview.affected, 'Only the one that is really missing is counted.');
        List<Rollup_Definition__c> kept = [
            SELECT Name, Active__c
            FROM Rollup_Definition__c
            WHERE Definition_Key__c = 'test_household_gift_count'
        ];
        Assert.areEqual(1, kept.size(), 'The one she already had was not duplicated.');
        Assert.areEqual('A name Maria chose', kept[0].Name, 'Nor renamed.');
        Assert.areEqual(false, kept[0].Active__c, 'Nor switched back on behind her.');
    }

    @IsTest
    static void theAutomationFixCreatesTheMissingSwitchesOnlyOnce() {
        AutomationRegistrySelector.registryOverride = new List<Automation_Registry__mdt>{
            new Automation_Registry__mdt(
                DeveloperName = 'Test_Household_Upkeep',
                MasterLabel = 'Household upkeep',
                Handler_Class__c = 'TestRegisteredHandler',
                Object_Name__c = 'Contact',
                Execution_Order__c = 10,
                Enabled_By_Default__c = true
            )
        };
        AutomationControl.clearCache();

        Test.startTest();
        HealthCheckFix.Preview preview = HealthCheckFix.preview(
            HealthCheckFix.KEY_AUTOMATION_SWITCHES
        );
        HealthCheckFix.Result first = HealthCheckFix.apply(HealthCheckFix.KEY_AUTOMATION_SWITCHES);
        HealthCheckFix.Result second = HealthCheckFix.apply(HealthCheckFix.KEY_AUTOMATION_SWITCHES);
        Test.stopTest();

        Assert.areEqual(1, preview.affected, 'One automation has no switch.');
        Assert.areEqual(1, first.changed, 'The first press created it.');
        Assert.areEqual(0, second.changed, 'The second press created nothing.');
        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM Automation_Setting__c
                WHERE Automation_Name__c = 'Test_Household_Upkeep'
            ],
            'One row, however many times the button is pressed.'
        );
    }

    @IsTest
    static void anAutomationRowWithNoRegistryEntryIsReportedAndLeftAlone() {
        insert new Automation_Setting__c(
            Name = 'Something an upgrade retired',
            Automation_Name__c = 'Retired_Automation',
            Enabled__c = true
        );
        AutomationRegistrySelector.registryOverride = new List<Automation_Registry__mdt>();
        AutomationControl.clearCache();

        Test.startTest();
        List<String> unregistered = HealthCheckFixCatalog.unregisteredAutomationNames();
        Test.stopTest();

        Assert.areEqual(1, unregistered.size(), 'The row an upgrade left behind is reported.');
        Assert.areEqual('Something an upgrade retired', unregistered[0], 'By its label.');
        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM Automation_Setting__c
                WHERE Automation_Name__c = 'Retired_Automation'
            ],
            'And it is still there: no Health Check action deletes a record (ADR-0029).'
        );
    }

    @IsTest
    static void theTemplateFixHasNothingToDoOnceTheTemplatesExist() {
        Test.startTest();
        ImportTemplateService.materializeDefaults();
        HealthCheckFix.Preview preview = HealthCheckFix.preview(
            HealthCheckFix.KEY_IMPORT_TEMPLATES
        );
        Test.stopTest();

        Assert.areEqual(0, preview.affected, 'Every shipped template is already here.');
        Assert.areEqual(true, preview.nothingToDo, 'So the fix has nothing to offer.');
    }

    @IsTest
    static void theAdminRoleFixNamesThePersonWaitingForTheRole() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();
        List<PermissionSet> adminSet = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = :HealthCheckService.PERMISSION_SET_ADMIN
            LIMIT 1
        ];
        Assert.areEqual(
            1,
            adminSet.size(),
            'The Nonprofit Admin permission set ships with this package (C-07).'
        );
        System.runAs(HealthCheckTestHelper.currentUser()) {
            insert new PermissionSetAssignment(
                AssigneeId = maria.Id,
                PermissionSetId = adminSet[0].Id
            );
        }

        String mariaName = [SELECT Name FROM User WHERE Id = :maria.Id].Name;

        System.runAs(maria) {
            Test.startTest();
            HealthCheckFix.Preview preview = HealthCheckFix.preview(HealthCheckFix.KEY_ADMIN_ROLE);
            Test.stopTest();

            Assert.isTrue(
                preview.affected >= 1,
                'Maria holds the permission set and not the role.'
            );
            Assert.isTrue(
                preview.items.contains(mariaName),
                'And the preview names her before anything is assigned: ' + preview.items
            );
        }
    }
}

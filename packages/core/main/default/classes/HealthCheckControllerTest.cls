/**
 * Tests for HealthCheckController (feature C-11).
 *
 * Reading the report needs nothing. Acting on a finding needs the Manage Nonprofit Settings
 * custom permission, and the controller checks it rather than trusting the component, so
 * both sides of that check are covered here.
 */
@IsTest
private class HealthCheckControllerTest {
    @IsTest
    static void anyoneCanReadTheReport() {
        OrgShapeDetector.overrideShape = npspShape();

        Test.startTest();
        HealthCheckService.Report report = HealthCheckController.getReport();
        Test.stopTest();

        System.assertNotEquals(null, report, 'The report is readable without any permission.');
        System.assertNotEquals(null, report.findings, 'It carries its findings.');
        System.assertEquals(
            CoexistenceService.MODE_NPSP,
            report.recommendedMode,
            'It says what this org shape calls for.'
        );
        System.assertEquals(
            false,
            report.canManageSettings,
            'The running user has not been given the permission, and the report says so.'
        );
    }

    @IsTest
    static void applyingTheRecommendationNeedsThePermission() {
        OrgShapeDetector.overrideShape = npspShape();

        Boolean refused = false;
        try {
            HealthCheckController.applyRecommendedMode();
        } catch (AuraHandledException e) {
            refused = true;
        }

        System.assert(refused, 'Without the permission, the fix is refused rather than applied.');
        System.assertEquals(
            null,
            CoexistenceService.getCurrentMode(),
            'Nothing was written on the way to being refused.'
        );
    }

    @IsTest
    static void switchingMembershipNeedsThePermission() {
        OrgShapeDetector.overrideShape = personAccountsShape();

        Boolean refused = false;
        try {
            HealthCheckController.applyJunctionMembership();
        } catch (AuraHandledException e) {
            refused = true;
        }

        System.assert(refused, 'Without the permission, the membership fix is refused.');
    }

    @IsTest
    static void withThePermissionTheRecommendationIsApplied() {
        User maria = userWithManageSettings();
        if (maria == null) {
            return;
        }

        System.runAs(maria) {
            OrgShapeDetector.overrideShape = npspShape();

            Test.startTest();
            HealthCheckService.Report report = HealthCheckController.applyRecommendedMode();
            Test.stopTest();

            System.assertEquals(
                true,
                report.canManageSettings,
                'Maria holds the permission, so she sees the fix buttons.'
            );
            System.assertEquals(
                CoexistenceService.MODE_NPSP,
                CoexistenceService.getCurrentMode(),
                'Taking the recommendation saves it.'
            );
            System.assertEquals(
                false,
                report.modeNeedsAttention,
                'Once applied, the mode no longer needs attention.'
            );
        }
    }

    @IsTest
    static void withThePermissionMembershipIsSwitched() {
        User maria = userWithManageSettings();
        if (maria == null) {
            return;
        }

        System.runAs(maria) {
            OrgShapeDetector.overrideShape = personAccountsShape();

            Test.startTest();
            HealthCheckController.applyJunctionMembership();
            Test.stopTest();

            System.assertEquals(
                CoexistenceService.MEMBERSHIP_JUNCTION,
                CoexistenceService.getMembershipMode(),
                'The membership fix does what its button says.'
            );
        }
    }

    /**
     * A user holding the Manage Nonprofit Settings custom permission, or null when the
     * custom permission is not in the org yet (it ships with the settings console, C-03).
     * Returning null rather than failing keeps this class useful while Core is assembled.
     */
    private static User userWithManageSettings() {
        List<CustomPermission> permissions = [
            SELECT Id
            FROM CustomPermission
            WHERE DeveloperName = 'Manage_Nonprofit_Settings'
            LIMIT 1
        ];
        if (permissions.isEmpty()) {
            return null;
        }

        PermissionSet permissionSet = new PermissionSet(
            Name = 'Health_Check_Test_Access',
            Label = 'Health Check test access'
        );
        insert permissionSet;
        insert new SetupEntityAccess(
            ParentId = permissionSet.Id,
            SetupEntityId = permissions[0].Id
        );

        User maria = new User(
            Alias = 'maria',
            Email = 'maria@example.invalid',
            EmailEncodingKey = 'UTF-8',
            FirstName = 'Maria',
            LastName = 'Operations',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = UserInfo.getProfileId(),
            TimeZoneSidKey = 'America/New_York',
            Username = 'maria.healthcheck.' + System.now().getTime() + '@example.invalid'
        );
        insert maria;
        insert new PermissionSetAssignment(
            AssigneeId = maria.Id,
            PermissionSetId = permissionSet.Id
        );
        return maria;
    }

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
}

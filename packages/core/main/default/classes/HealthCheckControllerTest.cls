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
        User maria = HealthCheckTestHelper.mariaWithManageSettings();

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
        User maria = HealthCheckTestHelper.mariaWithManageSettings();

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

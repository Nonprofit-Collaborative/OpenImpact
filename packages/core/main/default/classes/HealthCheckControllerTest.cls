/**
 * Tests for HealthCheckController (features C-11 and C-21).
 *
 * Reading the report needs nothing. Previewing or applying a fix needs the Manage Nonprofit
 * Settings custom permission, and the controller checks it rather than trusting the component,
 * so both sides of that check are covered here. The preview is gated as well as the apply,
 * because a preview counts things a person without that permission may not count.
 *
 * NOT EXECUTED. There was no Salesforce org reachable from the environment the C-21 changes
 * were written in, so the tests in this class have been compiled and reviewed but not run.
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
    static void previewingAFixNeedsThePermission() {
        OrgShapeDetector.overrideShape = npspShape();

        Boolean refused = false;
        try {
            HealthCheckController.previewFix(HealthCheckFix.KEY_RECOMMENDED_MODE);
        } catch (AuraHandledException e) {
            refused = true;
        }

        System.assert(refused, 'Without the permission, even the preview is refused.');
    }

    @IsTest
    static void applyingTheRecommendationNeedsThePermission() {
        OrgShapeDetector.overrideShape = npspShape();

        Boolean refused = false;
        try {
            HealthCheckController.applyFix(HealthCheckFix.KEY_RECOMMENDED_MODE);
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
            HealthCheckController.applyFix(HealthCheckFix.KEY_JUNCTION_MEMBERSHIP);
        } catch (AuraHandledException e) {
            refused = true;
        }

        System.assert(refused, 'Without the permission, the membership fix is refused.');
        System.assertEquals(
            CoexistenceService.MEMBERSHIP_CONTACT,
            CoexistenceService.getMembershipMode(),
            'And membership is where it was.'
        );
    }

    @IsTest
    static void aPreviewChangesNothing() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();

        System.runAs(maria) {
            OrgShapeDetector.overrideShape = npspShape();

            Test.startTest();
            HealthCheckFix.Preview preview = HealthCheckController.previewFix(
                HealthCheckFix.KEY_RECOMMENDED_MODE
            );
            Test.stopTest();

            System.assertEquals(1, preview.affected, 'The preview counts the one change.');
            System.assertEquals(
                null,
                CoexistenceService.getCurrentMode(),
                'And asking what would happen does not make it happen.'
            );
        }
    }

    @IsTest
    static void withThePermissionTheRecommendationIsApplied() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();

        System.runAs(maria) {
            OrgShapeDetector.overrideShape = npspShape();

            Test.startTest();
            HealthCheckController.FixOutcome outcome = HealthCheckController.applyFix(
                HealthCheckFix.KEY_RECOMMENDED_MODE
            );
            Test.stopTest();

            System.assertEquals(
                true,
                outcome.report.canManageSettings,
                'Maria holds the permission, so she sees the fix buttons.'
            );
            System.assertEquals(
                CoexistenceService.MODE_NPSP,
                CoexistenceService.getCurrentMode(),
                'Taking the recommendation saves it.'
            );
            System.assertEquals(
                false,
                outcome.report.modeNeedsAttention,
                'Once applied, the mode no longer needs attention.'
            );
            System.assertEquals(
                true,
                outcome.result.changedAnything,
                'And the person is told what was done, not only shown the new report.'
            );
        }
    }

    @IsTest
    static void withThePermissionMembershipIsSwitched() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();

        System.runAs(maria) {
            OrgShapeDetector.overrideShape = personAccountsShape();

            Test.startTest();
            HealthCheckController.applyFix(HealthCheckFix.KEY_JUNCTION_MEMBERSHIP);
            Test.stopTest();

            System.assertEquals(
                CoexistenceService.MEMBERSHIP_JUNCTION,
                CoexistenceService.getMembershipMode(),
                'The membership fix does what its button says.'
            );
        }
    }

    @IsTest
    static void anActionNobodyShipsIsRefusedWithSomethingReadable() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();

        System.runAs(maria) {
            Boolean refused = false;
            try {
                HealthCheckController.applyFix('deleteEverything');
            } catch (AuraHandledException e) {
                refused = true;
                System.assertEquals(
                    Label.Core_HealthCheckFix_Unknown,
                    e.getMessage(),
                    'The message is the label, not "Script-thrown exception".'
                );
            }

            System.assert(refused, 'A key that names no action changes nothing.');
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

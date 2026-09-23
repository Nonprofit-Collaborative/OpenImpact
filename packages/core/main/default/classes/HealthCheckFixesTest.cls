/**
 * The Health Check fix buttons C-21 adds (ADR-NEXT): each finding names what is missing,
 * counted from this org, and its fix creates exactly that, once, or schedules the nightly
 * run, once. Everything runs as Maria, who holds the permission the checks and the fixes are
 * gated on; the refusal is asserted as Priya.
 *
 * The test context sees no Rollup Definition, Automation Setting or Import Template row the
 * org already has, so every shipped default starts missing here. That is the state the
 * finding exists for.
 */
@IsTest
private class HealthCheckFixesTest {
    private static void shipOneRollup(String mode) {
        RollupSelector.defaultsOverride = new List<Rollup_Definition_Default__mdt>{
            new Rollup_Definition_Default__mdt(
                DeveloperName = 'Core_Household_Member_Count',
                MasterLabel = 'Household member count',
                Definition_Key__c = 'Core_Household_Member_Count',
                Source_Object__c = 'Household_Member__c',
                Target_Object__c = 'Account',
                Relationship_Path__c = 'Household__c',
                Aggregate__c = 'COUNT',
                Target_Field__c = 'Member_Count__c',
                Mode__c = mode,
                Fiscal_Year_Aware__c = false,
                Default_Active__c = true,
                Package__c = 'Core'
            )
        };
    }

    private static HealthCheckService.Finding find(String key) {
        for (HealthCheckService.Finding finding : HealthCheckService.run()) {
            if (key.equals(finding.key)) {
                return finding;
            }
        }
        return null;
    }

    private static HealthCheckService.Finding find(HealthCheckService.Report report, String key) {
        for (HealthCheckService.Finding finding : report.findings) {
            if (key.equals(finding.key)) {
                return finding;
            }
        }
        return null;
    }

    @IsTest
    static void aMissingShippedRollupIsNamedAndRestoredOnce() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();
        shipOneRollup('Both');

        System.runAs(maria) {
            HealthCheckService.Finding finding = find('shipped_rollups_missing');
            Assert.isNotNull(finding, 'A shipped rollup the org does not have is reported.');
            Assert.isTrue(
                finding.detail.contains('Household member count'),
                'The finding names what the fix will create.'
            );
            Assert.areEqual(
                HealthCheckService.FIX_ACTION_PREFIX + HealthCheckService.FIX_KEY_RESTORE_ROLLUPS,
                finding.fixTarget,
                'It carries the restore fix.'
            );

            Test.startTest();
            HealthCheckService.Report report = HealthCheckController.applyFix(
                HealthCheckService.FIX_KEY_RESTORE_ROLLUPS
            );
            HealthCheckController.applyFix(HealthCheckService.FIX_KEY_RESTORE_ROLLUPS);
            Test.stopTest();

            Assert.isNull(
                find(report, 'shipped_rollups_missing'),
                'The re-run report no longer has the finding.'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Rollup_Definition__c],
                'Pressing the fix twice is pressing it once.'
            );
        }
    }

    @IsTest
    static void missingAutomationSwitchesAreRestoredWithTheirShippedSetting() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();

        System.runAs(maria) {
            List<String> missing = AutomationControl.missingDefaultNames();
            HealthCheckService.Finding finding = find('automation_switches_missing');
            if (missing.isEmpty()) {
                Assert.isNull(finding, 'Nothing shipped, nothing missing, nothing said.');
                return;
            }
            Assert.isNotNull(finding, 'Automations with no switch are reported.');
            Assert.isTrue(
                finding.title.contains(String.valueOf(missing.size())),
                'The title counts them.'
            );

            Test.startTest();
            HealthCheckService.Report report = HealthCheckController.applyFix(
                HealthCheckService.FIX_KEY_RESTORE_AUTOMATION_SWITCHES
            );
            Test.stopTest();

            Assert.isNull(find(report, 'automation_switches_missing'), 'Every switch is back.');
            Assert.areEqual(
                missing.size(),
                [SELECT COUNT() FROM Automation_Setting__c WHERE Is_Package_Default__c = TRUE],
                'One switch for each automation that had none.'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Automation_Setting__c WHERE Enabled__c = FALSE],
                'A restored switch leaves its automation running, as it was before.'
            );
        }
    }

    @IsTest
    static void missingImportTemplatesAreRestoredOnce() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();

        System.runAs(maria) {
            List<String> missing = ImportTemplateService.missingDefaultNames();
            HealthCheckService.Finding finding = find('import_templates_missing');
            if (missing.isEmpty()) {
                Assert.isNull(finding, 'Nothing shipped, nothing missing, nothing said.');
                return;
            }
            Assert.isNotNull(finding, 'Shipped templates the org does not have are reported.');

            Test.startTest();
            HealthCheckController.applyFix(HealthCheckService.FIX_KEY_RESTORE_IMPORT_TEMPLATES);
            HealthCheckService.Report report = HealthCheckController.applyFix(
                HealthCheckService.FIX_KEY_RESTORE_IMPORT_TEMPLATES
            );
            Test.stopTest();

            Assert.isNull(find(report, 'import_templates_missing'), 'Every template is back.');
            Assert.areEqual(
                missing.size(),
                [SELECT COUNT() FROM Import_Template__c],
                'Pressing the fix twice is pressing it once.'
            );
        }
    }

    @IsTest
    static void aNightlyOnlyRollupWithNoNightlyRunIsAWarningAndTheFixSchedulesIt() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();
        shipOneRollup(RollupService.MODE_SCHEDULED);
        RollupService.skipEngine = true;

        System.runAs(maria) {
            RollupService.ensureDefaults();
            HealthCheckService.Finding finding = find('nightly_rollups_not_scheduled');
            if (RollupScheduler.isScheduled()) {
                // The org this runs in already has the nightly run, which a test cannot stop
                // for somebody else. The finding must then stay quiet.
                Assert.isNull(finding, 'A scheduled run is not reported.');
                return;
            }
            Assert.isNotNull(finding, 'A rollup waiting on a run nobody scheduled is reported.');
            Assert.areEqual(
                HealthCheckService.SEVERITY_WARNING,
                finding.severity,
                'A rollup that recalculates only at night is going stale.'
            );

            // No startTest: the scheduled run must not execute inside the test.
            HealthCheckService.Report report = HealthCheckController.applyFix(
                HealthCheckService.FIX_KEY_SCHEDULE_NIGHTLY_ROLLUPS
            );
            HealthCheckController.applyFix(HealthCheckService.FIX_KEY_SCHEDULE_NIGHTLY_ROLLUPS);

            Assert.isTrue(RollupScheduler.isScheduled(), 'The nightly run is scheduled.');
            Assert.isNull(
                find(report, 'nightly_rollups_not_scheduled'),
                'The re-run report no longer has the finding.'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM CronJobDetail WHERE Name = :RollupScheduler.JOB_NAME],
                'Pressing the fix twice schedules one run.'
            );
        }
    }

    @IsTest
    static void aRollupThatAlsoRunsInRealTimeIsOnlyInformation() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();
        shipOneRollup(RollupService.MODE_BOTH);

        System.runAs(maria) {
            RollupService.ensureDefaults();
            HealthCheckService.Finding finding = find('nightly_rollups_not_scheduled');
            if (RollupScheduler.isScheduled()) {
                Assert.isNull(finding, 'A scheduled run is not reported.');
                return;
            }
            Assert.areEqual(
                HealthCheckService.SEVERITY_INFO,
                finding.severity,
                'It still updates as records change; only the nightly correction is missed.'
            );
        }
    }

    @IsTest
    static void theFixesNeedThePermissionAndTheChecksAreNotShownWithoutIt() {
        User priya = HealthCheckTestHelper.priyaWithoutManageSettings();
        shipOneRollup('Both');

        System.runAs(priya) {
            Assert.isNull(
                find('shipped_rollups_missing'),
                'Only somebody who can press the fix is told about it.'
            );
            try {
                HealthCheckController.applyFix(HealthCheckService.FIX_KEY_RESTORE_ROLLUPS);
                Assert.fail('Without the permission the fix is refused.');
            } catch (AuraHandledException expected) {
                Assert.isNotNull(expected.getMessage(), 'Refused with a sentence.');
            }
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Rollup_Definition__c], 'Nothing was created.');
    }

    @IsTest
    static void aFixHealthCheckDoesNotHaveIsRefusedAndChangesNothing() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();

        System.runAs(maria) {
            try {
                HealthCheckController.applyFix('deleteEverything');
                Assert.fail('An unknown fix is refused.');
            } catch (AuraHandledException expected) {
                Assert.isNotNull(expected.getMessage(), 'Refused with a sentence.');
            }
            try {
                HealthCheckController.applyFix(null);
                Assert.fail('No fix is refused.');
            } catch (AuraHandledException expected) {
                Assert.isNotNull(expected.getMessage(), 'Refused with a sentence.');
            }
        }
    }
}

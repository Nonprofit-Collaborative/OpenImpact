/**
 * Tests for HealthCheckService (feature C-11), one per finding path.
 *
 * Org shape is forced through the detector's test override so that every path runs on every
 * org shape in the CI matrix, and the two access counts through the service's own override,
 * so that a finding is asserted against numbers the test chose rather than against whoever
 * happens to hold a permission set in the org the tests run in.
 */
@IsTest
private class HealthCheckServiceTest {
    @IsTest
    static void npspOrgReportsNpspDetectedAndRecommendsIt() {
        OrgShapeDetector.overrideShape = shape(true, false, false, false);

        Test.startTest();
        List<HealthCheckService.Finding> findings = HealthCheckService.run();
        Test.stopTest();

        HealthCheckService.Finding orgShape = find(findings, 'org_shape');
        System.assertNotEquals(null, orgShape, 'The report always opens with the org shape.');
        System.assert(
            orgShape.detail.contains(System.Label.Core_HealthCheck_NpspDetected),
            'An org with NPSP installed is told, in those words, that NPSP was detected.'
        );
        System.assert(
            orgShape.detail.contains(System.Label.Core_CoexistenceMode_Npsp),
            'The org shape finding names the mode it recommends.'
        );
        System.assertEquals(
            CoexistenceService.MODE_NPSP,
            CoexistenceService.applyRecommendedIfUnset(),
            'The C-11 criterion: NPSP detected means the mode defaults to NPSP coexistence.'
        );
    }

    @IsTest
    static void personAccountsOrgReportsWhatItFound() {
        OrgShapeDetector.overrideShape = shape(false, true, true, true);

        List<HealthCheckService.Finding> findings = HealthCheckService.run();

        HealthCheckService.Finding orgShape = find(findings, 'org_shape');
        System.assert(
            orgShape.detail.contains(System.Label.Core_HealthCheck_PersonAccountsDetected),
            'Person Accounts are named in the org shape card.'
        );
        System.assert(
            orgShape.detail.contains(System.Label.Core_HealthCheck_IndustriesDetected),
            'Nonprofit Cloud objects are named in the org shape card.'
        );
        System.assert(
            orgShape.detail.contains(System.Label.Core_HealthCheck_SalesObjectsDetected),
            'Standard Sales and Service Cloud objects are named too.'
        );
    }

    @IsTest
    static void freshOrgSaysNothingElseIsInstalled() {
        OrgShapeDetector.overrideShape = shape(false, false, false, false);

        HealthCheckService.Finding orgShape = find(HealthCheckService.run(), 'org_shape');

        System.assert(
            orgShape.detail.contains(System.Label.Core_HealthCheck_NothingDetected),
            'A fresh org is told it is a fresh org, not given an empty list.'
        );
    }

    @IsTest
    static void modeUnsetIsAWarningWithAOneClickFix() {
        OrgShapeDetector.overrideShape = shape(false, true, false, false);

        HealthCheckService.Finding finding = find(
            HealthCheckService.run(),
            'coexistence_mode_unset'
        );

        System.assertNotEquals(null, finding, 'An unconfirmed mode is reported.');
        System.assertEquals(
            HealthCheckService.SEVERITY_WARNING,
            finding.severity,
            'Not confirming a mode is worth knowing about, not an error.'
        );
        System.assertEquals(
            HealthCheckService.FIX_APPLY_RECOMMENDED_MODE,
            finding.fixTarget,
            'The fix applies the recommendation.'
        );
    }

    @IsTest
    static void modeThatDoesNotMatchTheOrgIsAWarning() {
        CoexistenceService.setMode(CoexistenceService.MODE_STANDALONE);
        OrgShapeDetector.overrideShape = shape(true, false, false, false);

        HealthCheckService.Finding finding = find(
            HealthCheckService.run(),
            'coexistence_mode_mismatch'
        );

        System.assertNotEquals(null, finding, 'A mode that does not match the org is reported.');
        System.assertEquals(
            HealthCheckService.SEVERITY_WARNING,
            finding.severity,
            'A mismatch may be deliberate, so it is a warning.'
        );
    }

    @IsTest
    static void modeThatMatchesTheOrgIsReportedAsFine() {
        OrgShapeDetector.overrideShape = shape(true, false, false, false);
        CoexistenceService.setMode(CoexistenceService.MODE_NPSP);

        HealthCheckService.Finding finding = find(
            HealthCheckService.run(),
            'coexistence_mode_match'
        );

        System.assertNotEquals(null, finding, 'Health Check says when something is right.');
        System.assertEquals(
            HealthCheckService.SEVERITY_INFO,
            finding.severity,
            'A matching mode is information.'
        );
    }

    @IsTest
    static void contactMembershipWithPersonAccountsIsAnError() {
        OrgShapeDetector.overrideShape = shape(false, true, false, false);
        CoexistenceService.setMode(CoexistenceService.MODE_STANDALONE);

        HealthCheckService.Finding finding = find(
            HealthCheckService.run(),
            'membership_mode_person_accounts'
        );

        System.assertNotEquals(null, finding, 'This combination is always reported.');
        System.assertEquals(
            HealthCheckService.SEVERITY_ERROR,
            finding.severity,
            'Contact membership in a Person Accounts org is broken, not merely untidy.'
        );
        System.assertEquals(
            HealthCheckService.FIX_APPLY_JUNCTION_MEMBERSHIP,
            finding.fixTarget,
            'The fix switches household membership to the junction.'
        );
    }

    @IsTest
    static void junctionMembershipWithPersonAccountsIsNotReported() {
        OrgShapeDetector.overrideShape = shape(false, true, false, false);
        CoexistenceService.setMode(CoexistenceService.MODE_AGENTFORCE_NONPROFIT);

        System.assertEquals(
            null,
            find(HealthCheckService.run(), 'membership_mode_person_accounts'),
            'Once membership is on the junction there is nothing to report.'
        );
    }

    /**
     * The state ADR-0037 closes, and the finding that makes it impossible to sit in it
     * silently: membership on the junction, automatic creation off, so no new person gets a
     * household and nothing else in the product says so.
     */
    @IsTest
    static void junctionMembershipWithNoCreationPathIsAnError() {
        OrgShapeDetector.overrideShape = shape(false, true, false, false);
        HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();

        HealthCheckService.Finding finding = find(
            HealthCheckService.run(),
            'household_creation_disabled'
        );

        System.assertNotEquals(null, finding, 'The state is always reported.');
        System.assertEquals(
            HealthCheckService.SEVERITY_ERROR,
            finding.severity,
            'Nobody is getting a household, which is broken rather than untidy.'
        );
        System.assertEquals(
            HealthCheckService.CATEGORY_SETTINGS,
            finding.category,
            'It is a settings finding: the setting is what has to change.'
        );
        System.assertEquals(
            HealthCheckService.FIX_ENABLE_AUTOMATIC_HOUSEHOLDS,
            finding.fixTarget,
            'And the fix turns automatic household creation on.'
        );
    }

    @IsTest
    static void junctionMembershipWithAutomaticHouseholdsIsNotReported() {
        OrgShapeDetector.overrideShape = shape(false, true, false, false);
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);

        System.assertEquals(
            null,
            find(HealthCheckService.run(), 'household_creation_disabled'),
            'Every new person is getting a household, so there is nothing to report.'
        );
    }

    /**
     * Contact mode is left alone by this check on purpose: the person still has a household
     * field anyone can fill in, and turning creation off there is an ordinary preference.
     */
    @IsTest
    static void contactMembershipWithAutomaticHouseholdsOffIsNotReported() {
        OrgShapeDetector.overrideShape = shape(false, false, false, false);
        Nonprofit_Settings__c settings = HouseholdTestDataFactory.settings(
            HouseholdTestDataFactory.MODE_CONTACT
        );
        settings.Auto_Create_Households__c = false;
        HouseholdTestDataFactory.save(settings);

        System.assertEquals(
            null,
            find(HealthCheckService.run(), 'household_creation_disabled'),
            'This check is about the mode with no household field to fall back on.'
        );
    }

    @IsTest
    static void industriesObjectsWithoutConnectAreReported() {
        OrgShapeDetector.overrideShape = shape(false, false, true, false);

        HealthCheckService.Finding finding = find(
            HealthCheckService.run(),
            'connect_module_absent'
        );

        System.assertNotEquals(null, finding, 'The gift mirror is worth mentioning once.');
        System.assertEquals(
            HealthCheckService.SEVERITY_INFO,
            finding.severity,
            'Nothing is broken, so this is information.'
        );
        System.assertEquals(
            null,
            finding.fixTarget,
            'There is nothing to click: Connect is a separate install in v0.6.'
        );
    }

    @IsTest
    static void multiCurrencyIsAWarning() {
        OrgShapeDetector.OrgShape orgShape = shape(false, false, false, false);
        orgShape.isMultiCurrency = true;
        OrgShapeDetector.overrideShape = orgShape;

        HealthCheckService.Finding finding = find(HealthCheckService.run(), 'multi_currency');

        System.assertNotEquals(null, finding, 'Multi-currency is detected and reported.');
        System.assertEquals(
            HealthCheckService.SEVERITY_WARNING,
            finding.severity,
            'Multi-currency is unsupported in v1 but does not break anything.'
        );
        System.assertEquals(
            HealthCheckService.CATEGORY_LICENSES,
            finding.category,
            'Currency belongs with the license findings.'
        );
    }

    @IsTest
    static void anOrgWithNobodyInTheAdminRoleIsAnError() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();

        System.runAs(maria) {
            OrgShapeDetector.overrideShape = shape(false, false, false, false);
            HealthCheckService.accessCountsOverride = new FixedAccessCounts(0, 0);

            HealthCheckService.Finding finding = find(
                HealthCheckService.run(),
                'no_nonprofit_admin'
            );

            System.assertNotEquals(
                null,
                finding,
                'An org where nobody can administer Open Impact is told so.'
            );
            System.assertEquals(
                HealthCheckService.SEVERITY_ERROR,
                finding.severity,
                'Nobody able to administer the app is an error.'
            );
            System.assertEquals(
                HealthCheckService.SECTION_ACCESS,
                finding.fixTarget,
                'The fix opens the Access page.'
            );
        }
    }

    @IsTest
    static void anOrgThatIsSetUpProperlyIsToldNothingAboutAccess() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();

        System.runAs(maria) {
            OrgShapeDetector.overrideShape = shape(false, false, false, false);
            HealthCheckService.accessCountsOverride = new FixedAccessCounts(1, 0);

            List<HealthCheckService.Finding> findings = HealthCheckService.run();

            System.assertEquals(
                null,
                find(findings, 'no_nonprofit_admin'),
                'One administrator is enough: there is nothing to say about it.'
            );
            System.assertEquals(
                null,
                find(findings, 'users_without_access'),
                'Everyone can see the app, so nobody is reported as locked out.'
            );
        }
    }

    @IsTest
    static void anAdministratorAssignedDirectlyStillCounts() {
        List<PermissionSet> packaged = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = :HealthCheckService.PERMISSION_SET_ADMIN
            LIMIT 1
        ];
        System.assert(
            !packaged.isEmpty(),
            'The Nonprofit Admin permission set is not in this org. It ships with the access ' +
            'feature (C-06), which has to merge before this test means anything.'
        );

        User maria = HealthCheckTestHelper.mariaWithManageSettings();
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM PermissionSetAssignment
                WHERE AssigneeId = :maria.Id AND PermissionSetId = :packaged[0].Id
            ],
            'Maria holds the admin permission set directly rather than through a group.'
        );

        System.runAs(maria) {
            OrgShapeDetector.overrideShape = shape(false, false, false, false);

            System.assertEquals(
                null,
                find(HealthCheckService.run(), 'no_nonprofit_admin'),
                'Someone given the admin permission set by hand is still an administrator.'
            );
        }
    }

    @IsTest
    static void usersWithNoRoleAreCounted() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();

        System.runAs(maria) {
            OrgShapeDetector.overrideShape = shape(false, false, false, false);
            HealthCheckService.accessCountsOverride = new FixedAccessCounts(1, 3);

            HealthCheckService.Finding finding = find(
                HealthCheckService.run(),
                'users_without_access'
            );

            System.assertNotEquals(
                null,
                finding,
                'Active people holding no packaged role are counted and reported.'
            );
            System.assertEquals(
                HealthCheckService.SEVERITY_WARNING,
                finding.severity,
                'People who cannot see the app is a warning, not an error.'
            );
            System.assert(
                finding.detail.contains('3'),
                'The finding reports the number of people that were counted: ' + finding.detail
            );
        }
    }

    @IsTest
    static void someoneWhoCannotSeeTheAnswerIsNotGivenAWrongOne() {
        User priya = HealthCheckTestHelper.priyaWithoutManageSettings();

        System.runAs(priya) {
            OrgShapeDetector.overrideShape = shape(false, false, false, false);
            List<HealthCheckService.Finding> findings = HealthCheckService.run();

            System.assertEquals(
                null,
                find(findings, 'no_nonprofit_admin'),
                'Priya sees her own assignments and nothing else, so the count would be wrong.'
            );
            System.assertEquals(
                null,
                find(findings, 'users_without_access'),
                'The same is true of counting who cannot see the app.'
            );
            System.assertEquals(
                null,
                find(findings, 'error_log_new'),
                'And of counting errors she may not be allowed to read.'
            );

            HealthCheckService.Finding gate = find(findings, 'access_checks_need_admin');
            System.assertNotEquals(
                null,
                gate,
                'She is told why the access checks are missing rather than left guessing.'
            );
            System.assertEquals(
                HealthCheckService.SEVERITY_INFO,
                gate.severity,
                'Not being an administrator is information, not a fault.'
            );
            System.assertNotEquals(
                null,
                find(findings, 'org_shape'),
                'Everything that does not depend on seeing other people still runs.'
            );
        }
    }

    @IsTest
    static void pausedAutomationIsReportedWhileItLasts() {
        OrgShapeDetector.overrideShape = shape(false, false, false, false);
        // The pause is not an editable setting with a shipped Setting Definition row: Maria sets
        // it from the Automation panel, and the settings service rightly refuses a key no row
        // names. The factory writes the same field the way the product does.
        TestDataFactory.pausedSettings(2);

        HealthCheckService.Finding finding = find(HealthCheckService.run(), 'automation_paused');

        System.assertNotEquals(null, finding, 'A pause is always visible while it is on.');
        System.assertEquals(
            HealthCheckService.SEVERITY_INFO,
            finding.severity,
            'Pausing is a normal thing to do during a load.'
        );
        System.assertEquals(
            null,
            find(HealthCheckService.run(), 'automation_running'),
            'Automation cannot be both paused and running.'
        );
    }

    @IsTest
    static void automationThatIsRunningIsSaidSo() {
        OrgShapeDetector.overrideShape = shape(false, false, false, false);

        HealthCheckService.Finding finding = find(HealthCheckService.run(), 'automation_running');

        System.assertNotEquals(
            null,
            finding,
            'Maria is told automation is running, so silence never has to be interpreted.'
        );
        System.assertEquals(
            HealthCheckService.SEVERITY_INFO,
            finding.severity,
            'Working normally is information.'
        );
    }

    @IsTest
    static void expiredPauseIsNotReported() {
        OrgShapeDetector.overrideShape = shape(false, false, false, false);
        TestDataFactory.pausedSettings(-1);

        List<HealthCheckService.Finding> findings = HealthCheckService.run();

        System.assertEquals(
            null,
            find(findings, 'automation_paused'),
            'A pause that has expired is not news.'
        );
        System.assertNotEquals(
            null,
            find(findings, 'automation_running'),
            'Once the pause expires, automation is running again.'
        );
    }

    @IsTest
    static void unreadErrorsAreCounted() {
        insert new Error_Log__c(
            Timestamp__c = System.now(),
            Context__c = 'Health Check test',
            Message__c = 'Something went wrong and here is what to do about it.',
            Severity__c = 'Error',
            Status__c = 'New'
        );
        // Counting the Error Log needs read on the object and on Status, which is what the
        // packaged Nonprofit Admin permission set gives Maria, and mariaWithManageSettings
        // now assigns it because every audited settings save needs it too. Without that
        // access the selector keeps its promise and says nothing, which is what this test
        // used to be measuring.
        User maria = HealthCheckTestHelper.mariaWithManageSettings();

        System.runAs(maria) {
            OrgShapeDetector.overrideShape = shape(false, false, false, false);

            HealthCheckService.Finding finding = find(HealthCheckService.run(), 'error_log_new');

            System.assertNotEquals(
                null,
                finding,
                'A new error is surfaced where Maria will see it.'
            );
            System.assertEquals(
                HealthCheckService.SEVERITY_WARNING,
                finding.severity,
                'Unread errors are a warning.'
            );
            System.assert(finding.title.contains('1'), 'The title says how many there are.');
        }
    }

    @IsTest
    static void noUnreadErrorsMeansNoFinding() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();

        System.runAs(maria) {
            OrgShapeDetector.overrideShape = shape(false, false, false, false);

            System.assertEquals(
                null,
                find(HealthCheckService.run(), 'error_log_new'),
                'An empty Error Log produces no finding at all.'
            );
        }
    }

    @IsTest
    static void someoneHoldingTheReceiptLockOverrideIsNamed() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();
        CustomPermissionSelector.holdersOverride = holders(
            true,
            1,
            new List<String>{ 'Dana Ellery' }
        );

        System.runAs(maria) {
            OrgShapeDetector.overrideShape = shape(false, false, false, false);

            HealthCheckService.Finding finding = find(
                HealthCheckService.run(),
                'override_receipt_lock'
            );

            System.assertNotEquals(
                null,
                finding,
                'ADR-0024: an override permission left assigned is reported, because leaving ' +
                'it assigned is the way an org misuses it.'
            );
            System.assert(
                finding.detail.contains('Dana Ellery'),
                'The finding names the holder. "Somebody has it" is not something Maria can ' +
                    'act on. Detail was: ' +
                    finding.detail
            );
            System.assertEquals(
                HealthCheckService.SEVERITY_WARNING,
                finding.severity,
                'The permission may be legitimately assigned for the next ten minutes, so it ' +
                'is an amber "be aware", not a red "broken".'
            );
            System.assertEquals(
                HealthCheckService.CATEGORY_ACCESS,
                finding.category,
                'Who holds a permission is an access question, and it groups with the others.'
            );
            System.assertEquals(
                HealthCheckService.FIX_CUSTOM_PERMISSIONS_URL,
                finding.fixTarget,
                'The fix is in Setup, deliberately not in the settings console: ADR-0024 keeps ' +
                'lifting the receipt lock out of the console on purpose.'
            );
        }
    }

    @IsTest
    static void severalHoldersAreNamedAndTheRestAreCounted() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();
        CustomPermissionSelector.holdersOverride = holders(
            true,
            5,
            new List<String>{ 'Ada Lo', 'Ben Ruiz', 'Cara Nkemdi' }
        );

        System.runAs(maria) {
            OrgShapeDetector.overrideShape = shape(false, false, false, false);

            HealthCheckService.Finding finding = find(
                HealthCheckService.run(),
                'override_receipt_lock'
            );

            System.assert(
                finding.detail.contains('Cara Nkemdi'),
                'The named holders are all in the line. Detail was: ' + finding.detail
            );
            System.assert(
                finding.detail.contains('2'),
                'The two holders past the naming limit are counted rather than dropped, so ' +
                    'the line is never quietly short. Detail was: ' +
                    finding.detail
            );
        }
    }

    @IsTest
    static void anOrgWhereNobodyHoldsTheOverrideIsNotToldAboutIt() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();
        CustomPermissionSelector.holdersOverride = holders(true, 0, new List<String>());

        System.runAs(maria) {
            OrgShapeDetector.overrideShape = shape(false, false, false, false);

            System.assertEquals(
                null,
                find(HealthCheckService.run(), 'override_receipt_lock'),
                'A permission granted to nobody is the shipped state, including on a ' +
                    'Platform-only org where the Giving package that owns it is not installed at ' +
                    'all, and the shipped state is not a finding.'
            );
        }
    }

    @IsTest
    static void anOverrideNobodyCanSeeIsNotReportedAsSafe() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();
        CustomPermissionSelector.holdersOverride = holders(false, 0, new List<String>());

        System.runAs(maria) {
            OrgShapeDetector.overrideShape = shape(false, false, false, false);

            System.assertEquals(
                null,
                find(HealthCheckService.run(), 'override_receipt_lock'),
                'When the setup objects cannot be read the question was not answered, so ' +
                    'Health Check says nothing rather than printing a clean bill of health it ' +
                    'cannot stand behind.'
            );
        }
    }

    @IsTest
    static void theOverrideCheckIsNotRunForSomeoneWhoCannotSeeOtherPeople() {
        User priya = HealthCheckTestHelper.priyaWithoutManageSettings();
        CustomPermissionSelector.holdersOverride = holders(
            true,
            1,
            new List<String>{ 'Dana Ellery' }
        );

        System.runAs(priya) {
            OrgShapeDetector.overrideShape = shape(false, false, false, false);
            List<HealthCheckService.Finding> findings = HealthCheckService.run();

            System.assertEquals(
                null,
                find(findings, 'override_receipt_lock'),
                'Salesforce shows a person only their own access, so who holds a permission ' +
                'is asked only of an administrator.'
            );
            System.assertNotEquals(
                null,
                find(findings, 'access_checks_need_admin'),
                'Priya is told the access checks were skipped rather than left to assume they ' +
                'passed.'
            );
        }
    }

    @IsTest
    static void twoFiscalYearsThatDisagreeAreReportedWithBothMonths() {
        OrgShapeDetector.overrideShape = shape(false, false, false, false);
        SettingsService.saveSystemValue('Fiscal_Year_Start_Month__c', 7);
        FiscalYearSelector.orgStartMonthOverridden = true;
        FiscalYearSelector.orgStartMonthOverride = 1;

        HealthCheckService.Finding finding = find(HealthCheckService.run(), 'fiscal_year_mismatch');

        System.assertNotEquals(
            null,
            finding,
            'ADR-0025: the rollups are computed from the Nonprofit Settings month and the ' +
                'retention reports from the Setup month, so a disagreement makes every year based ' +
                'number wrong in a way nobody notices.'
        );
        System.assert(
            finding.detail.contains(FiscalYearSelector.monthName(7)),
            'The finding names the month Open Impact uses. Detail was: ' + finding.detail
        );
        System.assert(
            finding.detail.contains(FiscalYearSelector.monthName(1)),
            'And the month Setup uses, because the fix is deciding which one is right. ' +
                'Detail was: ' +
                finding.detail
        );
        System.assertEquals(
            HealthCheckService.SEVERITY_WARNING,
            finding.severity,
            'Nothing is broken today: the numbers are simply measured on two boundaries.'
        );
        System.assertEquals(
            HealthCheckService.SECTION_GENERAL,
            finding.fixTarget,
            'The one field an administrator can change from inside the app is in General ' +
            'settings, and the fix button opens it.'
        );
    }

    @IsTest
    static void twoFiscalYearsThatAgreeAreNotReported() {
        OrgShapeDetector.overrideShape = shape(false, false, false, false);
        SettingsService.saveSystemValue('Fiscal_Year_Start_Month__c', 7);
        FiscalYearSelector.orgStartMonthOverridden = true;
        FiscalYearSelector.orgStartMonthOverride = 7;

        System.assertEquals(
            null,
            find(HealthCheckService.run(), 'fiscal_year_mismatch'),
            'Both fiscal years start in July, which is the state the check exists to ask for.'
        );
    }

    @IsTest
    static void aSetupFiscalYearNobodyCouldReadIsNotAMismatch() {
        OrgShapeDetector.overrideShape = shape(false, false, false, false);
        SettingsService.saveSystemValue('Fiscal_Year_Start_Month__c', 7);
        FiscalYearSelector.orgStartMonthOverridden = true;
        FiscalYearSelector.orgStartMonthOverride = null;

        System.assertEquals(
            null,
            find(HealthCheckService.run(), 'fiscal_year_mismatch'),
            'A value that could not be read is not evidence that the two disagree, so the ' +
            'report says nothing rather than accusing the org of a mismatch.'
        );
    }

    @IsTest
    static void oneReceiptNumberConsumedByAFailedRunIsInformation() {
        OrgShapeDetector.overrideShape = shape(false, false, false, false);
        ReceiptGapSelector.resultOverride = receipts(true, 1);

        HealthCheckService.Finding finding = find(
            HealthCheckService.run(),
            'receipt_generation_failed_once'
        );

        System.assertNotEquals(
            null,
            finding,
            'Rule R-RC3: a number consumed by a run that failed is reconciled into a void ' +
            'receipt, and the administrator is told the record is there.'
        );
        System.assertEquals(
            HealthCheckService.SEVERITY_INFO,
            finding.severity,
            'One of these is the reconciliation mechanism working, not a problem.'
        );
        System.assertEquals(
            ErrorLogCountSelector.listViewUrl(),
            finding.fixTarget,
            'What went wrong is in the Error Log, so that is where the button goes.'
        );
    }

    @IsTest
    static void repeatedReceiptFailuresAreAWarningThatSaysHowMany() {
        OrgShapeDetector.overrideShape = shape(false, false, false, false);
        ReceiptGapSelector.resultOverride = receipts(true, 9);

        List<HealthCheckService.Finding> findings = HealthCheckService.run();
        HealthCheckService.Finding finding = find(findings, 'receipt_generation_failed');

        System.assertNotEquals(
            null,
            finding,
            'Nine numbers consumed by failed runs means receipt generation is failing over ' +
            'and over and nobody has looked.'
        );
        System.assertEquals(
            HealthCheckService.SEVERITY_WARNING,
            finding.severity,
            'Donors are waiting for documents that are not being produced.'
        );
        System.assert(
            finding.title.contains('9'),
            'The title says how many, because the number is the whole signal. Title was: ' +
            finding.title
        );
        System.assertEquals(
            null,
            find(findings, 'receipt_generation_failed_once'),
            'Only one of the two receipt findings is ever reported.'
        );
    }

    @IsTest
    static void noFailedReceiptsMeansNoFinding() {
        OrgShapeDetector.overrideShape = shape(false, false, false, false);
        ReceiptGapSelector.resultOverride = receipts(true, 0);

        System.assertEquals(
            null,
            find(HealthCheckService.run(), 'receipt_generation_failed_once'),
            'An org whose receipts all generated has nothing to be told.'
        );
    }

    @IsTest
    static void anOrgWithoutGivingIsToldNothingAboutReceipts() {
        OrgShapeDetector.overrideShape = shape(false, false, false, false);
        ReceiptGapSelector.resultOverride = receipts(false, 0);

        List<HealthCheckService.Finding> findings = HealthCheckService.run();

        System.assertEquals(
            null,
            find(findings, 'receipt_generation_failed_once'),
            'This is the Platform-only org shape: no Giving package, no Receipt object, no ' +
                'count to take. Core does not compile against Giving and does not pretend the ' +
                'answer is zero.'
        );
        System.assertEquals(
            null,
            find(findings, 'check_failed_receipt_generation'),
            'And the absence of Giving is an ordinary org shape rather than a check failure, ' +
            'so nothing is written to the Error Log about it.'
        );
        System.assertNotEquals(
            null,
            find(findings, 'org_shape'),
            'The rest of the report is unaffected.'
        );
    }

    @IsTest
    static void oneFailingCheckDoesNotHideTheOthers() {
        OrgShapeDetector.overrideShape = shape(true, false, false, false);
        HealthCheckService.faultInjection = new BrokenCheck();

        List<HealthCheckService.Finding> findings = HealthCheckService.run();

        HealthCheckService.Finding failed = find(findings, 'check_failed_injected');
        System.assertNotEquals(null, failed, 'The check that failed says so, by name.');
        System.assertEquals(
            HealthCheckService.SEVERITY_WARNING,
            failed.severity,
            'One check failing is a warning about the report, not an error about the org.'
        );
        System.assertNotEquals(
            null,
            find(findings, 'org_shape'),
            'The other eight answers are still there.'
        );
        System.assertNotEquals(
            null,
            find(findings, 'coexistence_mode_unset'),
            'Including the ones that come after the failure.'
        );
    }

    @IsTest
    static void anErrorLoggerThatIsItselfBrokenDoesNotTakeTheReportDown() {
        OrgShapeDetector.overrideShape = shape(true, false, false, false);
        HealthCheckService.faultInjection = new BrokenCheck();
        HealthCheckService.loggerFault = new BrokenCheckException('The Error Log is unwritable.');

        List<HealthCheckService.Finding> findings = HealthCheckService.run();

        System.assertNotEquals(
            null,
            find(findings, 'check_failed_injected'),
            'The failure is still reported even when it could not be written down.'
        );
        System.assertNotEquals(
            null,
            find(findings, 'org_shape'),
            'And the rest of the report survives a logger that cannot log.'
        );
    }

    private class BrokenCheckException extends Exception {
    }

    private class BrokenCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            throw new BrokenCheckException('This check is broken on purpose.');
        }
    }

    @IsTest
    static void everyFindingCarriesACategoryAndASeverity() {
        OrgShapeDetector.overrideShape = shape(true, true, true, true);

        for (HealthCheckService.Finding finding : HealthCheckService.run()) {
            System.assertNotEquals(null, finding.key, 'Every finding has a key.');
            System.assertNotEquals(null, finding.title, 'Every finding has a title.');
            System.assertNotEquals(null, finding.detail, 'Every finding explains itself.');
            System.assert(
                finding.severity == HealthCheckService.SEVERITY_INFO ||
                    finding.severity == HealthCheckService.SEVERITY_WARNING ||
                    finding.severity == HealthCheckService.SEVERITY_ERROR,
                'Severity is one of the three the component knows how to draw.'
            );
            System.assert(
                finding.category == HealthCheckService.CATEGORY_ORG_SHAPE ||
                    finding.category == HealthCheckService.CATEGORY_LICENSES ||
                    finding.category == HealthCheckService.CATEGORY_ACCESS ||
                    finding.category == HealthCheckService.CATEGORY_SETTINGS,
                'Category is one of the four the component groups by.'
            );
        }
    }

    @IsTest
    static void reportCarriesTheModesAndThePermission() {
        OrgShapeDetector.overrideShape = shape(true, false, false, false);

        Test.startTest();
        HealthCheckService.Report report = HealthCheckService.buildReport();
        Test.stopTest();

        System.assertNotEquals(null, report.findings, 'The report carries the findings.');
        System.assertEquals(
            CoexistenceService.MODE_NPSP,
            report.recommendedMode,
            'The report says what is recommended.'
        );
        System.assertEquals(
            System.Label.Core_CoexistenceMode_Npsp,
            report.recommendedModeLabel,
            'The recommendation is labelled for a person to read.'
        );
        System.assertEquals(
            true,
            report.modeNeedsAttention,
            'An unconfirmed mode needs attention, which is what shows the button.'
        );
        System.assertNotEquals(
            null,
            report.orgShapeSummary,
            'The card summary is on the report, not rebuilt by the component.'
        );
    }

    @IsTest
    static void modeLabelFallsBackWhenNothingIsSet() {
        System.assertEquals(
            System.Label.Core_CoexistenceMode_Unset,
            HealthCheckService.modeLabel(null),
            'An unset mode reads as unset, never as blank.'
        );
        System.assertEquals(
            System.Label.Core_CoexistenceMode_Standalone,
            HealthCheckService.modeLabel(CoexistenceService.MODE_STANDALONE),
            'Standalone has a name a person recognizes.'
        );
        System.assertEquals(
            System.Label.Core_CoexistenceMode_AgentforceNonprofit,
            HealthCheckService.modeLabel(CoexistenceService.MODE_AGENTFORCE_NONPROFIT),
            'Agentforce Nonprofit coexistence has a name a person recognizes.'
        );
    }

    @IsTest
    static void summaryOfANullShapeIsStillReadable() {
        System.assertEquals(
            System.Label.Core_HealthCheck_NothingDetected,
            HealthCheckService.detectedSummary(null),
            'A shape that could not be read still produces a sentence.'
        );
    }

    /**
     * Access counts the test chose. The real counts are questions about every user and
     * permission set in the org, so a finding asserted against them is really an assertion
     * about the org the tests happen to run in. These are the numbers the test asked for.
     */
    private class FixedAccessCounts implements HealthCheckService.AccessCounts {
        private final Integer admins;
        private final Integer without;

        private FixedAccessCounts(Integer admins, Integer without) {
            this.admins = admins;
            this.without = without;
        }

        public Integer administrators() {
            return admins;
        }

        public Integer usersWithoutAccess() {
            return without;
        }
    }

    /** Holders of a custom permission the test chose, rather than whoever the org has. */
    private static CustomPermissionSelector.Holders holders(
        Boolean readable,
        Integer total,
        List<String> names
    ) {
        CustomPermissionSelector.Holders result = new CustomPermissionSelector.Holders();
        result.readable = readable;
        result.total = total;
        result.names = names;
        return result;
    }

    /**
     * A receipt reconciliation count the test chose. Receipt__c belongs to the Giving package
     * and Core cannot compile against it, so the count is injected here exactly as the
     * selector would return it, including the case where there is no Giving to ask.
     */
    private static ReceiptGapSelector.Result receipts(Boolean available, Integer count) {
        ReceiptGapSelector.Result result = new ReceiptGapSelector.Result();
        result.available = available;
        result.count = count;
        return result;
    }

    private static OrgShapeDetector.OrgShape shape(
        Boolean hasNpsp,
        Boolean hasPersonAccounts,
        Boolean hasIndustriesNonprofit,
        Boolean hasSalesCloudObjects
    ) {
        OrgShapeDetector.OrgShape orgShape = new OrgShapeDetector.OrgShape();
        orgShape.hasNpsp = hasNpsp;
        orgShape.hasPersonAccounts = hasPersonAccounts;
        orgShape.hasIndustriesNonprofit = hasIndustriesNonprofit;
        orgShape.hasSalesCloudObjects = hasSalesCloudObjects;
        return orgShape;
    }

    private static HealthCheckService.Finding find(
        List<HealthCheckService.Finding> findings,
        String key
    ) {
        for (HealthCheckService.Finding finding : findings) {
            if (key.equals(finding.key)) {
                return finding;
            }
        }
        return null;
    }
}

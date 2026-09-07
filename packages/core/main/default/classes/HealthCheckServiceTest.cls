/**
 * Tests for HealthCheckService (feature C-11), one per finding path.
 *
 * Org shape is forced through the detector's test override so that every path runs on every
 * org shape in the CI matrix. The access and Error Log checks read the org they run in.
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
        OrgShapeDetector.overrideShape = shape(false, false, false, false);

        HealthCheckService.Finding finding = find(HealthCheckService.run(), 'no_nonprofit_admin');

        System.assertNotEquals(
            null,
            finding,
            'No packaged role has been assigned in a test org, so this is reported.'
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

    @IsTest
    static void anAdministratorAssignedDirectlyStillCounts() {
        List<PermissionSet> packaged = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = :HealthCheckService.PERMISSION_SET_ADMIN
            LIMIT 1
        ];
        if (packaged.isEmpty()) {
            return;
        }

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
            Username = 'maria.direct.' + System.now().getTime() + '@example.invalid'
        );
        insert maria;
        insert new PermissionSetAssignment(AssigneeId = maria.Id, PermissionSetId = packaged[0].Id);

        OrgShapeDetector.overrideShape = shape(false, false, false, false);

        System.assertEquals(
            null,
            find(HealthCheckService.run(), 'no_nonprofit_admin'),
            'Someone given the admin permission set by hand is still an administrator.'
        );
    }

    @IsTest
    static void usersWithNoRoleAreCounted() {
        OrgShapeDetector.overrideShape = shape(false, false, false, false);

        HealthCheckService.Finding finding = find(HealthCheckService.run(), 'users_without_access');

        System.assertNotEquals(
            null,
            finding,
            'The running user holds no packaged role, so at least one user is counted.'
        );
        System.assertEquals(
            HealthCheckService.SEVERITY_WARNING,
            finding.severity,
            'People who cannot see the app is a warning, not an error.'
        );
    }

    @IsTest
    static void pausedAutomationIsReportedWhileItLasts() {
        OrgShapeDetector.overrideShape = shape(false, false, false, false);
        SettingsService.saveValues(
            new Map<String, Object>{ 'Automation_Paused_Until__c' => System.now().addHours(2) }
        );

        HealthCheckService.Finding finding = find(HealthCheckService.run(), 'automation_paused');

        System.assertNotEquals(null, finding, 'A pause is always visible while it is on.');
        System.assertEquals(
            HealthCheckService.SEVERITY_INFO,
            finding.severity,
            'Pausing is a normal thing to do during a load.'
        );
    }

    @IsTest
    static void expiredPauseIsNotReported() {
        OrgShapeDetector.overrideShape = shape(false, false, false, false);
        SettingsService.saveValues(
            new Map<String, Object>{ 'Automation_Paused_Until__c' => System.now().addHours(-1) }
        );

        System.assertEquals(
            null,
            find(HealthCheckService.run(), 'automation_paused'),
            'A pause that has expired is not news.'
        );
    }

    @IsTest
    static void unreadErrorsAreCounted() {
        OrgShapeDetector.overrideShape = shape(false, false, false, false);
        insert new Error_Log__c(
            Timestamp__c = System.now(),
            Context__c = 'Health Check test',
            Message__c = 'Something went wrong and here is what to do about it.',
            Severity__c = 'Error',
            Status__c = 'New'
        );

        HealthCheckService.Finding finding = find(HealthCheckService.run(), 'error_log_new');

        System.assertNotEquals(null, finding, 'A new error is surfaced where Maria will see it.');
        System.assertEquals(
            HealthCheckService.SEVERITY_WARNING,
            finding.severity,
            'Unread errors are a warning.'
        );
        System.assert(finding.title.contains('1'), 'The title says how many there are.');
    }

    @IsTest
    static void noUnreadErrorsMeansNoFinding() {
        OrgShapeDetector.overrideShape = shape(false, false, false, false);

        System.assertEquals(
            null,
            find(HealthCheckService.run(), 'error_log_new'),
            'An empty Error Log produces no finding at all.'
        );
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

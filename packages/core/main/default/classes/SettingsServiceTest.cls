/**
 * The v0.1 settings accessor: read the org's settings once, treat a value nobody recognizes as
 * the shipped default, and record every change.
 */
@IsTest
private class SettingsServiceTest {
    @IsTest
    static void theOrgSettingsAreReadOncePerTransaction() {
        TestDataFactory.defaultSettings();

        Nonprofit_Settings__c first = SettingsService.getSettings();
        Nonprofit_Settings__c second = SettingsService.getSettings();

        Assert.isNotNull(first, 'A fresh org has settings to read.');
        Assert.areEqual(first.Id, second.Id, 'The second read is the cached one.');
        Assert.areEqual(
            'The {LastName} Family',
            first.Household_Name_Pattern__c,
            'The shipped naming pattern is there on install.'
        );
    }

    @IsTest
    static void aWriteIsSeenByTheNextRead() {
        Nonprofit_Settings__c settings = TestDataFactory.defaultSettings();
        Assert.isNull(SettingsService.getSettings().Automation_Paused_Until__c, 'Not paused.');

        settings.Automation_Paused_Until__c = System.now().addHours(4);
        TestDataFactory.saveSettings(settings);

        Assert.isNotNull(
            SettingsService.getSettings().Automation_Paused_Until__c,
            'Clearing the cache on write means the next read is not stale.'
        );
    }

    @IsTest
    static void aModeIsReadBackAsItWasSaved() {
        Nonprofit_Settings__c settings = TestDataFactory.defaultSettings();
        settings.Coexistence_Mode__c = 'NPSP';
        settings.Household_Membership_Mode__c = 'Junction';
        TestDataFactory.saveSettings(settings);

        Assert.areEqual('NPSP', SettingsService.coexistenceMode(), 'Maria chose NPSP coexistence.');
        Assert.areEqual(
            'Junction',
            SettingsService.householdMembershipMode(),
            'And junction membership.'
        );
    }

    @IsTest
    static void aModeNobodyRecognizesFallsBackToTheShippedDefault() {
        Nonprofit_Settings__c settings = TestDataFactory.defaultSettings();
        settings.Coexistence_Mode__c = 'Something a data load put here';
        settings.Household_Membership_Mode__c = null;
        TestDataFactory.saveSettings(settings);

        Assert.areEqual(
            SettingsService.COEXISTENCE_MODE_DEFAULT,
            SettingsService.coexistenceMode(),
            'A value outside the list reads as the shipped default (ADR-0019).'
        );
        Assert.areEqual(
            SettingsService.MEMBERSHIP_MODE_DEFAULT,
            SettingsService.householdMembershipMode(),
            'So does an empty one.'
        );
    }

    @IsTest
    static void aModeIsCheckedOnItsWayIn() {
        Assert.areEqual(
            'NPSP',
            SettingsService.validated('NPSP', SettingsService.coexistenceModes()),
            'An offered value is accepted.'
        );

        for (String rejected : new List<String>{ 'npsp', '', null }) {
            try {
                SettingsService.validated(rejected, SettingsService.membershipModes());
                Assert.fail('The value "' + rejected + '" should be refused.');
            } catch (SettingsService.SettingsServiceException expected) {
                Assert.areEqual(
                    Label.Core_Settings_ModeValueInvalid,
                    expected.getMessage(),
                    'Maria is told to pick from the list.'
                );
            }
        }
        try {
            SettingsService.validated('Contact', null);
            Assert.fail('A value with no list to check against should be refused.');
        } catch (SettingsService.SettingsServiceException expected) {
            Assert.isNotNull(expected.getMessage(), 'With a message.');
        }
    }

    @IsTest
    static void theShippedDefaultsAreExactlyWhatTheFieldsSay() {
        // A text field default value is a formula, so whatever sits inside the quotes is the
        // value a fresh org gets: " Standalone " is not a coexistence mode the service
        // recognizes, and a padded pattern puts spaces into every household name C-02 computes.
        // The formula is read from the field describe and not from getOrgDefaults(), because on a
        // fresh org that returns an empty in-memory instance whose every value is null, so an
        // assertion made against it passes whatever the field ships.
        Map<String, String> expectedByField = new Map<String, String>{
            'Coexistence_Mode__c' => '"' +
            SettingsService.COEXISTENCE_MODE_DEFAULT +
            '"',
            'Household_Membership_Mode__c' => '"' +
            SettingsService.MEMBERSHIP_MODE_DEFAULT +
            '"',
            'Household_Name_Pattern__c' => '"The {LastName} Family"',
            'Formal_Greeting_Pattern__c' => '"{Salutation} {FirstName} {LastName}"',
            'Informal_Greeting_Pattern__c' => '"{FirstName}"'
        };
        Map<String, Schema.SObjectField> shipped = Schema.SObjectType.Nonprofit_Settings__c.fields.getMap();

        for (String fieldName : expectedByField.keySet()) {
            String formula = shipped.get(fieldName).getDescribe().getDefaultValueFormula();
            Assert.isNotNull(formula, fieldName + ' ships a default value.');
            Assert.areEqual(
                formula,
                formula.trim(),
                'The default formula for ' + fieldName + ' carries no padding: "' + formula + '"'
            );
            Assert.areEqual(
                formula.removeStart('"').removeEnd('"'),
                formula.removeStart('"').removeEnd('"').trim(),
                'And no padding inside the quotes either: "' + formula + '"'
            );
            Assert.areEqual(
                expectedByField.get(fieldName),
                formula,
                'The shipped default for ' + fieldName + ' is exactly the literal we mean.'
            );
        }

        Assert.isTrue(
            SettingsService.coexistenceModes().contains(SettingsService.COEXISTENCE_MODE_DEFAULT),
            'And the code default is itself one of the offered values.'
        );
        Assert.isTrue(
            SettingsService.membershipModes().contains(SettingsService.MEMBERSHIP_MODE_DEFAULT),
            'For both keys.'
        );
    }

    @IsTest
    static void everyChangeIsRecordedWithWhoWhenAndWhat() {
        Test.startTest();
        SettingsService.logChange(
            'Household naming pattern',
            'The {LastName} Family',
            '{LastName}'
        );
        SettingsService.logChange('  ', 'something', 'something else');
        Test.stopTest();

        List<Setting_Change__c> audit = [
            SELECT Setting_Name__c, Old_Value__c, New_Value__c, Changed_By__c, Changed_At__c
            FROM Setting_Change__c
        ];
        Assert.areEqual(1, audit.size(), 'A change with no setting name is not an audit row.');
        Assert.areEqual('Household naming pattern', audit[0].Setting_Name__c, 'What changed.');
        Assert.areEqual('The {LastName} Family', audit[0].Old_Value__c, 'What it was.');
        Assert.areEqual('{LastName}', audit[0].New_Value__c, 'What it is now.');
        Assert.areEqual(UserInfo.getUserId(), audit[0].Changed_By__c, 'Who changed it.');
        Assert.isNotNull(audit[0].Changed_At__c, 'And when.');
    }
}

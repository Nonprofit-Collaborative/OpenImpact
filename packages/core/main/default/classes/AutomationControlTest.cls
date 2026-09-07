/**
 * The switches Maria uses on the Automation page: pause everything, switch one thing off, and
 * the materialization that keeps her choices through an upgrade.
 */
@IsTest
private class AutomationControlTest {
    private static final String NAMING = 'Household_Naming';
    private static final String HOUSEHOLDS = 'Household_Creation';

    @IsTest
    static void mariaPausesForTwoHoursAndTheBannerKnowsWhenItEnds() {
        TestDataFactory.defaultSettings();

        Test.startTest();
        Datetime until = AutomationControl.pauseAll(2);
        Test.stopTest();

        Assert.isTrue(AutomationControl.isPaused(), 'Automation is paused.');
        Assert.isNotNull(AutomationControl.pausedUntil(), 'The banner has an end time to show.');
        Assert.isTrue(
            until > System.now().addMinutes(110),
            'Two hours from now, give or take the time the test took.'
        );
        List<Setting_Change__c> audit = [
            SELECT Setting_Name__c, Old_Value__c, New_Value__c, Changed_By__c
            FROM Setting_Change__c
        ];
        Assert.areEqual(1, audit.size(), 'Pausing is one audited change.');
        Assert.areEqual(
            AutomationControl.PAUSE_SETTING_NAME,
            audit[0].Setting_Name__c,
            'The audit row names the pause setting.'
        );
        Assert.isTrue(String.isBlank(audit[0].Old_Value__c), 'Nothing was paused before.');
        Assert.isTrue(String.isNotBlank(audit[0].New_Value__c), 'And now there is an end time.');
        Assert.areEqual(UserInfo.getUserId(), audit[0].Changed_By__c, 'Maria made the change.');
    }

    @IsTest
    static void mariaResumesBeforeThePauseExpires() {
        TestDataFactory.pausedSettings(2);
        Assert.isTrue(AutomationControl.isPaused(), 'Set up as paused.');

        Test.startTest();
        AutomationControl.resumeAll();
        Test.stopTest();

        Assert.isFalse(AutomationControl.isPaused(), 'Resuming starts automation again.');
        Assert.isNull(AutomationControl.pausedUntil(), 'There is no end time to show.');
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Setting_Change__c],
            'Resuming is one audited change.'
        );
    }

    @IsTest
    static void aPauseThatHasExpiredIsNotAPause() {
        TestDataFactory.pausedSettings(-1);

        Assert.isFalse(AutomationControl.isPaused(), 'A pause in the past has ended by itself.');
        Assert.isNull(AutomationControl.pausedUntil(), 'So there is no banner.');
    }

    @IsTest
    static void anEmptySettingIsNotAPause() {
        TestDataFactory.defaultSettings();

        Assert.isFalse(AutomationControl.isPaused(), 'A fresh org is not paused.');
    }

    @IsTest
    static void onlyTheOfferedPauseLengthsAreAccepted() {
        TestDataFactory.defaultSettings();
        Assert.areEqual(
            new Set<Integer>{ 1, 2, 4, 8, 24 },
            AutomationControl.allowedPauseHours(),
            'The page offers 1, 2, 4, 8 and 24 hours.'
        );

        for (Integer hours : new List<Integer>{ 3, 0, -2, 100 }) {
            try {
                AutomationControl.pauseAll(hours);
                Assert.fail('A pause of ' + hours + ' hours should be refused.');
            } catch (AutomationControl.AutomationControlException expected) {
                Assert.areEqual(
                    Label.Core_Automation_PauseHoursInvalid,
                    expected.getMessage(),
                    'Maria is told which lengths she can choose.'
                );
            }
        }
        try {
            AutomationControl.pauseAll(null);
            Assert.fail('A pause with no length should be refused.');
        } catch (AutomationControl.AutomationControlException expected) {
            Assert.isNotNull(expected.getMessage(), 'With a message.');
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Setting_Change__c], 'And nothing is audited.');
    }

    @IsTest
    static void switchingOneAutomationOffIsAuditedAndTakesEffect() {
        TestDataFactory.insertAutomationSettings(
            new Map<String, Boolean>{ NAMING => true, HOUSEHOLDS => true }
        );
        Assert.isTrue(AutomationControl.isEnabled(NAMING), 'It starts switched on.');

        Test.startTest();
        AutomationControl.setEnabled(NAMING, false);
        Test.stopTest();

        Assert.isFalse(AutomationControl.isEnabled(NAMING), 'It is switched off.');
        Assert.isTrue(AutomationControl.isEnabled(HOUSEHOLDS), 'And nothing else changed.');
        List<Setting_Change__c> audit = [
            SELECT Setting_Name__c, Old_Value__c, New_Value__c
            FROM Setting_Change__c
        ];
        Assert.areEqual(1, audit.size(), 'One switch, one audit row.');
        Assert.areEqual('Automation: ' + NAMING, audit[0].Setting_Name__c, 'Named in the row.');
        Assert.areEqual('true', audit[0].Old_Value__c, 'It was on.');
        Assert.areEqual('false', audit[0].New_Value__c, 'Now it is off.');
    }

    @IsTest
    static void switchingSomethingToTheValueItAlreadyHasChangesNothing() {
        TestDataFactory.insertAutomationSettings(new Map<String, Boolean>{ NAMING => true });

        AutomationControl.setEnabled(NAMING, true);

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Setting_Change__c],
            'Saving without changing anything writes nothing.'
        );
    }

    @IsTest
    static void switchingSomethingThatDoesNotExistSaysSo() {
        TestDataFactory.defaultSettings();

        try {
            AutomationControl.setEnabled('Not_An_Automation', false);
            Assert.fail('An unknown automation should be refused.');
        } catch (AutomationControl.AutomationControlException expected) {
            Assert.areEqual(
                Label.Core_Automation_NotFound,
                expected.getMessage(),
                'Maria is told to refresh the page.'
            );
        }

        try {
            AutomationControl.setEnabled('   ', false);
            Assert.fail('An empty automation name should be refused.');
        } catch (AutomationControl.AutomationControlException expected) {
            Assert.areEqual(
                Label.Core_Automation_NameRequired,
                expected.getMessage(),
                'Maria is told to pick an automation.'
            );
        }
    }

    @IsTest
    static void anAutomationWithNoRowYetStillRuns() {
        Assert.isTrue(
            AutomationControl.isEnabled('Shipped_But_Not_Materialized_Yet'),
            'A newly shipped automation works from the moment it is installed.'
        );
        Assert.isFalse(AutomationControl.isEnabled(null), 'An automation with no name does not.');
        Assert.isFalse(AutomationControl.isEnabled('  '), 'Nor one with an empty name.');
    }

    @IsTest
    static void bypassIsPerNameAndPerTransaction() {
        Assert.isFalse(AutomationControl.isBypassed(NAMING), 'Nothing is bypassed to begin with.');

        AutomationControl.bypass(NAMING);
        Assert.isTrue(AutomationControl.isBypassed(NAMING), 'This one is bypassed.');
        Assert.isFalse(AutomationControl.isBypassed(HOUSEHOLDS), 'That one is not.');
        Assert.isFalse(AutomationControl.isBypassed(null), 'An empty name is never bypassed.');

        AutomationControl.bypass(null);
        AutomationControl.clearBypass(null);
        AutomationControl.clearBypass(NAMING);
        Assert.isFalse(AutomationControl.isBypassed(NAMING), 'And the bypass can be cleared.');
    }

    @IsTest
    static void shippedAutomationsAreMaterializedOnceAndNeverOverwritten() {
        TestDataFactory.insertAutomationSettings(new Map<String, Boolean>{ NAMING => false });
        AutomationControl.registryOverride = new List<Automation_Registry__mdt>{
            TestDataFactory.registryEntry(NAMING, true),
            TestDataFactory.registryEntry(HOUSEHOLDS, true)
        };

        Test.startTest();
        Integer firstRun = AutomationControl.ensureDefaults();
        Integer secondRun = AutomationControl.ensureDefaults();
        Test.stopTest();

        Assert.areEqual(1, firstRun, 'Only the automation with no row yet is created.');
        Assert.areEqual(0, secondRun, 'Running it again creates nothing.');
        Assert.isFalse(
            AutomationControl.isEnabled(NAMING),
            'The choice to switch this one off survives materialization.'
        );
        List<Automation_Setting__c> created = [
            SELECT Automation_Name__c, Enabled__c, Handler_Class__c, Is_Package_Default__c
            FROM Automation_Setting__c
            WHERE Automation_Name__c = :HOUSEHOLDS
        ];
        Assert.areEqual(1, created.size(), 'The new automation has a row.');
        Assert.isTrue(created[0].Enabled__c, 'On by default, as shipped.');
        Assert.isTrue(created[0].Is_Package_Default__c, 'And marked as one the package created.');
        Assert.areEqual(
            HOUSEHOLDS + 'Handler',
            created[0].Handler_Class__c,
            'With the handler from the registry.'
        );
    }

    @IsTest
    static void materializingAnEmptyRegistryDoesNothing() {
        AutomationControl.registryOverride = new List<Automation_Registry__mdt>();

        Assert.areEqual(0, AutomationControl.ensureDefaults(), 'v0.1 ships no registry records.');
        Assert.areEqual(0, [SELECT COUNT() FROM Automation_Setting__c], 'So there is nothing.');
    }

    @IsTest
    static void materializingIgnoresARegistryEntryWithNoName() {
        AutomationControl.registryOverride = new List<Automation_Registry__mdt>{
            new Automation_Registry__mdt(Description__c = 'No developer name.')
        };

        Assert.areEqual(0, AutomationControl.ensureDefaults(), 'An entry with no name is skipped.');
    }

    @IsTest
    static void twoHundredAutomationsAreReadInOneQuery() {
        Map<String, Boolean> many = new Map<String, Boolean>();
        for (Integer i = 0; i < 200; i++) {
            many.put('Bulk_Automation_' + i, Math.mod(i, 2) == 0);
        }
        TestDataFactory.insertAutomationSettings(many);

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        Boolean first = AutomationControl.isEnabled('Bulk_Automation_0');
        Boolean last = AutomationControl.isEnabled('Bulk_Automation_199');
        Integer queriesAfter = Limits.getQueries();
        Test.stopTest();

        Assert.isTrue(first, 'Even numbered automations are on.');
        Assert.isFalse(last, 'Odd numbered ones are off.');
        Assert.areEqual(1, queriesAfter - queriesBefore, 'The list is read once per transaction.');
    }
}

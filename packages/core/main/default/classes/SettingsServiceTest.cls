/**
 * Maria changes a setting in the console and expects three things: the value sticks, the
 * change is recorded, and a value that makes no sense is refused before anything is saved.
 */
@IsTest
private class SettingsServiceTest {
    private static final String TEXT_KEY = 'Household_Name_Pattern__c';
    private static final String CHECKBOX_KEY = 'Auto_Create_Households__c';
    private static final String DATETIME_KEY = 'Automation_Paused_Until__c';
    private static final String PROGRESS_KEY = 'Setup_Steps_Completed__c';

    private static void stubDefinitions() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>{
            new Setting_Definition__mdt(
                DeveloperName = 'Household_Name_Pattern',
                MasterLabel = 'Household name pattern',
                Setting_Key__c = TEXT_KEY,
                Section__c = 'Households',
                Module__c = 'Core',
                Data_Type__c = 'Text',
                Sort_Order__c = 1
            ),
            new Setting_Definition__mdt(
                DeveloperName = 'Auto_Create_Households',
                MasterLabel = 'Create households automatically',
                Setting_Key__c = CHECKBOX_KEY,
                Section__c = 'Households',
                Module__c = 'Core',
                Data_Type__c = 'Checkbox',
                Sort_Order__c = 2
            ),
            new Setting_Definition__mdt(
                DeveloperName = 'Automation_Paused_Until',
                MasterLabel = 'Automation paused until',
                Setting_Key__c = DATETIME_KEY,
                Section__c = 'Automation',
                Module__c = 'Core',
                Data_Type__c = 'DateTime',
                Sort_Order__c = 1
            )
        };
    }

    @IsTest
    static void savesValueAndRecordsTheChange() {
        stubDefinitions();

        Test.startTest();
        SettingsService.saveValues(new Map<String, Object>{ TEXT_KEY => 'The {LastName} Family' });
        Test.stopTest();

        Assert.areEqual(
            'The {LastName} Family',
            SettingsService.getValue(TEXT_KEY),
            'Maria expects the pattern she typed to be the one in force'
        );
        List<Setting_Change__c> changes = SettingChangeSelector.getRecent(10);
        Assert.areEqual(1, changes.size(), 'One changed setting writes exactly one audit record');
        Assert.areEqual(
            'Nonprofit_Settings__c.' + TEXT_KEY,
            changes[0].Setting_Name__c,
            'The audit record names the settings object and the setting, because each package owns one'
        );
        Assert.areEqual('', changes[0].Old_Value__c, 'The setting had never been set');
        Assert.areEqual(
            'The {LastName} Family',
            changes[0].New_Value__c,
            'The audit record holds the new value'
        );
        Assert.areEqual(
            UserInfo.getUserId(),
            changes[0].Changed_By__c,
            'The audit record names who changed it'
        );
    }

    @IsTest
    static void savingWithoutChangingAnythingRecordsNothing() {
        stubDefinitions();
        SettingsService.saveValues(new Map<String, Object>{ TEXT_KEY => 'The {LastName} Family' });

        Test.startTest();
        SettingsService.saveValues(new Map<String, Object>{ TEXT_KEY => 'The {LastName} Family' });
        Test.stopTest();

        Assert.areEqual(
            1,
            SettingChangeSelector.getRecent(10).size(),
            'Saving a page without changing anything writes nothing'
        );
    }

    @IsTest
    static void savesSeveralSettingsInOneGo() {
        stubDefinitions();

        Test.startTest();
        SettingsService.saveValues(
            new Map<String, Object>{
                TEXT_KEY => 'The {LastName} Household',
                CHECKBOX_KEY => 'false',
                DATETIME_KEY => '2026-09-07T17:00:00.000Z'
            }
        );
        Test.stopTest();

        Assert.areEqual(
            3,
            SettingChangeSelector.getRecent(10).size(),
            'One audit record per changed setting'
        );
        Assert.areEqual(
            false,
            SettingsService.getValue(CHECKBOX_KEY),
            'A checkbox sent as text is read as a checkbox'
        );
        Assert.areNotEqual(
            null,
            SettingsService.getValue(DATETIME_KEY),
            'A date and time sent as text is read as one'
        );
    }

    @IsTest
    static void refusesASettingThatDoesNotExist() {
        stubDefinitions();
        Boolean refused = false;

        Test.startTest();
        try {
            SettingsService.saveValues(new Map<String, Object>{ 'Not_A_Setting__c' => 'anything' });
        } catch (SettingsService.SettingsException e) {
            refused = true;
            Assert.areEqual(
                System.Label.Core_Settings_UnknownKeyError,
                e.getMessage(),
                'The message tells Maria what to do'
            );
        }
        Test.stopTest();

        Assert.isTrue(refused, 'A setting that does not exist is refused');
        Assert.areEqual(
            0,
            SettingChangeSelector.getRecent(10).size(),
            'Nothing is saved when one value is refused'
        );
    }

    @IsTest
    static void refusesASettingThatIsNotOnTheConsole() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
        Boolean refused = false;

        Test.startTest();
        try {
            SettingsService.saveValues(
                new Map<String, Object>{ TEXT_KEY => 'The {LastName} Family' }
            );
        } catch (SettingsService.SettingsException e) {
            refused = true;
        }
        Test.stopTest();

        Assert.isTrue(refused, 'A field with no console row is not editable from the console');
    }

    @IsTest
    static void refusesAValueInTheWrongFormat() {
        stubDefinitions();
        Boolean refused = false;

        Test.startTest();
        try {
            SettingsService.saveValues(new Map<String, Object>{ DATETIME_KEY => 'next Tuesday' });
        } catch (SettingsService.SettingsException e) {
            refused = true;
            Assert.areEqual(
                System.Label.Core_Settings_InvalidValueError,
                e.getMessage(),
                'The message names the problem and what to do'
            );
        }
        Test.stopTest();

        Assert.isTrue(refused, 'A date and time that cannot be read is refused');
    }

    @IsTest
    static void savesTheProgressKeyThePackageOwns() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();

        Test.startTest();
        SettingsService.saveSystemValue(PROGRESS_KEY, 'coexistence,naming');
        Test.stopTest();

        Assert.areEqual(
            'coexistence,naming',
            SettingsService.getValue(PROGRESS_KEY),
            'The package writes its own progress key without a console row'
        );
    }

    @IsTest
    static void readingAnUnknownSettingIsRefused() {
        Boolean refused = false;

        Test.startTest();
        try {
            SettingsService.getValue('Not_A_Setting__c');
        } catch (SettingsService.SettingsException e) {
            refused = true;
        }
        Test.stopTest();

        Assert.isTrue(refused, 'Reading a setting that does not exist is refused');
        Assert.isFalse(
            SettingsService.hasKey('Not_A_Setting__c'),
            'The org does not have that setting'
        );
        Assert.isTrue(
            SettingsService.hasKey(TEXT_KEY),
            'The org does have the household name pattern'
        );
    }

    @IsTest
    static void refusesASettingsObjectNoShippedRowNames() {
        stubDefinitions();
        Boolean refused = false;

        Test.startTest();
        try {
            SettingsService.saveValues(
                'Not_A_Settings_Object__c',
                new Map<String, Object>{ TEXT_KEY => 'anything' }
            );
        } catch (SettingsService.SettingsException e) {
            refused = true;
        }
        Test.stopTest();

        Assert.isTrue(refused, 'Only a settings object a shipped row names can be written');
    }

    @IsTest
    static void readsCoreSettingsByNameAsWellAsByDefault() {
        stubDefinitions();
        SettingsService.saveValues(new Map<String, Object>{ TEXT_KEY => 'The {LastName} Family' });

        Test.startTest();
        Object named = SettingsService.getValue('Nonprofit_Settings__c', TEXT_KEY);
        Test.stopTest();

        Assert.areEqual(
            'The {LastName} Family',
            named,
            'Naming Core\'s own object reads the same value'
        );
        Assert.isTrue(
            SettingsService.hasKey('Nonprofit_Settings__c', TEXT_KEY),
            'Core owns the household name pattern'
        );
        Assert.isFalse(
            SettingsService.hasKey('Nonprofit_Settings__c', 'Not_A_Setting__c'),
            'Core does not own a setting that does not exist'
        );
    }

    @IsTest
    static void readsSettingsWithoutQueryingEveryTime() {
        Test.startTest();
        Nonprofit_Settings__c first = SettingsService.getSettings();
        Nonprofit_Settings__c second = SettingsService.getSettings();
        Test.stopTest();

        Assert.areNotEqual(null, first, 'An org that has never saved still gets a settings record');
        Assert.areEqual(first, second, 'The second read comes from the cache');
    }
}

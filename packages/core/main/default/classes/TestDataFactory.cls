/**
 * Shared test data for Core and for every module package (plan Section 7.3).
 *
 * Public and namespace accessible, never global (ADR-0017), so a module package's tests can call
 * it without it becoming part of the subscriber-facing API. Test only: it is never on a code path
 * a subscriber runs.
 */
@IsTest
@NamespaceAccessible
public class TestDataFactory {
    /**
     * The org level Nonprofit Settings, with the shipped v0.1 defaults, saved and cached.
     */
    @NamespaceAccessible
    public static Nonprofit_Settings__c defaultSettings() {
        Nonprofit_Settings__c settings = Nonprofit_Settings__c.getOrgDefaults();
        settings.Coexistence_Mode__c = SettingsService.COEXISTENCE_MODE_DEFAULT;
        settings.Household_Membership_Mode__c = SettingsService.MEMBERSHIP_MODE_DEFAULT;
        settings.Auto_Create_Households__c = true;
        settings.Delete_Empty_Households__c = true;
        settings.Create_Households_For_Person_Accounts__c = false;
        settings.Household_Name_Pattern__c = 'The {LastName} Family';
        settings.Formal_Greeting_Pattern__c = '{Salutation} {FirstName} {LastName}';
        settings.Informal_Greeting_Pattern__c = '{FirstName}';
        settings.Include_Deceased_In_Name__c = false;
        settings.Relationship_Auto_Reciprocal__c = true;
        saveSettings(settings);
        return settings;
    }

    /**
     * Saves the org level settings and clears the transaction cache so the next read sees them.
     */
    @NamespaceAccessible
    public static void saveSettings(Nonprofit_Settings__c settings) {
        if (settings.Id == null) {
            insert settings;
        } else {
            update settings;
        }
        SettingsService.clearCache();
        AutomationControl.clearCache();
    }

    /**
     * Puts automation into a paused state that ends the given number of hours from now. A
     * negative number produces a pause that has already expired.
     */
    @NamespaceAccessible
    public static Nonprofit_Settings__c pausedSettings(Integer hoursFromNow) {
        Nonprofit_Settings__c settings = defaultSettings();
        settings.Automation_Paused_Until__c = System.now().addHours(hoursFromNow);
        saveSettings(settings);
        return settings;
    }

    @NamespaceAccessible
    public static Automation_Setting__c automationSetting(String automationName, Boolean enabled) {
        return new Automation_Setting__c(
            Name = automationName,
            Automation_Name__c = automationName,
            Description__c = 'Test automation used by the Open Impact test suite.',
            Enabled__c = enabled,
            Handler_Class__c = automationName,
            Object_Name__c = 'Error_Log__c',
            Execution_Order__c = 10,
            Is_Package_Default__c = false
        );
    }

    @NamespaceAccessible
    public static List<Automation_Setting__c> insertAutomationSettings(
        Map<String, Boolean> enabledByName
    ) {
        List<Automation_Setting__c> settings = new List<Automation_Setting__c>();
        for (String automationName : enabledByName.keySet()) {
            settings.add(automationSetting(automationName, enabledByName.get(automationName)));
        }
        insert settings;
        AutomationControl.clearCache();
        return settings;
    }

    /**
     * A shipped registry entry, built in memory. Custom metadata cannot be inserted by a test,
     * so tests hand these to `AutomationRegistrySelector.registryOverride`.
     */
    @NamespaceAccessible
    public static Automation_Registry__mdt registryEntry(String developerName, Boolean enabled) {
        return new Automation_Registry__mdt(
            DeveloperName = developerName,
            MasterLabel = developerName.replace('_', ' '),
            Description__c = 'Shipped test automation.',
            Handler_Class__c = developerName + 'Handler',
            Object_Name__c = 'Error_Log__c',
            Execution_Order__c = 20,
            Enabled_By_Default__c = enabled
        );
    }

    /**
     * A user on a minimal profile whose only Open Impact access comes from the packaged
     * permission sets named here, so that a test proves what those sets actually grant rather
     * than what a system administrator profile already allows.
     *
     * The user and the assignments are setup objects, so they are written in their own context to
     * keep the platform's mixed DML rule happy.
     */
    @NamespaceAccessible
    public static User createUser(String lastName, List<String> permissionSetNames) {
        String unique = lastName + System.now().getTime() + Crypto.getRandomInteger();
        User person = new User(
            Alias = lastName.left(8),
            Email = lastName + '@openimpact.example.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = lastName,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = minimalProfileId(),
            TimeZoneSidKey = 'GMT',
            Username = unique + '@openimpact.example.invalid'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert person;
            List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
            for (PermissionSet packaged : [
                SELECT Id
                FROM PermissionSet
                WHERE Name IN :permissionSetNames
            ]) {
                assignments.add(
                    new PermissionSetAssignment(
                        AssigneeId = person.Id,
                        PermissionSetId = packaged.Id
                    )
                );
            }
            if (!assignments.isEmpty()) {
                insert assignments;
            }
        }
        return person;
    }

    /**
     * The least privileged profile that can be assigned. Standard User on every org shape we
     * support; the running user's profile is the fallback if an org has renamed it.
     */
    private static Id minimalProfileId() {
        List<Profile> minimal = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        return minimal.isEmpty() ? UserInfo.getProfileId() : minimal[0].Id;
    }

    /**
     * Error Log records that already exist, so a selector or a tile has something to read.
     */
    @NamespaceAccessible
    public static List<Error_Log__c> insertErrorLogs(Integer howMany, String status) {
        List<Error_Log__c> logs = new List<Error_Log__c>();
        for (Integer i = 0; i < howMany; i++) {
            logs.add(
                new Error_Log__c(
                    Timestamp__c = System.now().addMinutes(-i),
                    User__c = UserInfo.getUserId(),
                    Context__c = 'Test context ' + i,
                    Message__c = 'Something went wrong, number ' + i + '.',
                    Technical_Detail__c = 'TestException: number ' + i,
                    Severity__c = ErrorLogger.SEVERITY_ERROR,
                    Status__c = status
                )
            );
        }
        insert logs;
        return logs;
    }
}

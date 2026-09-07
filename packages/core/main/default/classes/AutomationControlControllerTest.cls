/**
 * The Automation page as two people see it: Maria, who has the Manage Nonprofit Settings
 * permission through the Nonprofit Admin role, and David, who does not.
 */
@IsTest
private class AutomationControlControllerTest {
    private static final String NAMING = 'Household_Naming';

    private static User buildUser(String lastName) {
        return new User(
            Alias = lastName.left(8),
            Email = lastName + '@openimpact.example.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = lastName,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = UserInfo.getProfileId(),
            TimeZoneSidKey = 'GMT',
            Username = lastName + System.now().getTime() + '@openimpact.example.invalid'
        );
    }

    /**
     * Creates both people. User and permission set assignment are setup objects, so they are
     * inserted in their own context to keep the platform's mixed DML rule happy.
     */
    private static Map<String, User> createPeople() {
        User maria = buildUser('Maria');
        User david = buildUser('David');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<User>{ maria, david };
            List<PermissionSet> admin = [
                SELECT Id
                FROM PermissionSet
                WHERE Name = 'Nonprofit_Admin'
                LIMIT 1
            ];
            if (!admin.isEmpty()) {
                insert new PermissionSetAssignment(
                    AssigneeId = maria.Id,
                    PermissionSetId = admin[0].Id
                );
            }
        }
        return new Map<String, User>{ 'maria' => maria, 'david' => david };
    }

    @IsTest
    static void thePageListsEveryAutomationAndThePauseState() {
        TestDataFactory.insertAutomationSettings(new Map<String, Boolean>{ NAMING => true });
        TestDataFactory.pausedSettings(2);

        Test.startTest();
        AutomationControlController.AutomationPageView page = AutomationControlController.getPage();
        Test.stopTest();

        Assert.isTrue(page.paused, 'The page knows automation is paused.');
        Assert.isNotNull(page.pausedUntil, 'And when it ends.');
        Assert.areEqual(
            new List<Integer>{ 1, 2, 4, 8, 24 },
            page.pauseHourOptions,
            'The page offers the five lengths, in order.'
        );
        Assert.areEqual(1, page.automations.size(), 'One automation is listed.');
        Assert.areEqual(NAMING, page.automations[0].automationName, 'Named as it is registered.');
        Assert.isTrue(page.automations[0].enabled, 'And switched on.');
        Assert.isNotNull(page.automations[0].label, 'With a label Maria reads.');
    }

    @IsTest
    static void mariaPausesResumesAndSwitchesOneAutomationOff() {
        TestDataFactory.insertAutomationSettings(new Map<String, Boolean>{ NAMING => true });
        TestDataFactory.defaultSettings();
        User maria = createPeople().get('maria');

        Test.startTest();
        System.runAs(maria) {
            AutomationControlController.AutomationPageView paused = AutomationControlController.pauseAll(
                2
            );
            Assert.isTrue(paused.canManage, 'Maria may change this page.');
            Assert.isTrue(paused.paused, 'And has paused everything.');

            AutomationControlController.AutomationPageView running = AutomationControlController.resumeAll();
            Assert.isFalse(running.paused, 'And started it again.');

            AutomationControlController.AutomationPageView switched = AutomationControlController.setEnabled(
                NAMING,
                false
            );
            Assert.isFalse(switched.automations[0].enabled, 'And switched one automation off.');
        }
        Test.stopTest();

        Assert.areEqual(
            3,
            [SELECT COUNT() FROM Setting_Change__c],
            'Three changes, three audit rows.'
        );
    }

    @IsTest
    static void davidSeesThePageButCannotChangeIt() {
        TestDataFactory.insertAutomationSettings(new Map<String, Boolean>{ NAMING => true });
        User david = createPeople().get('david');

        Test.startTest();
        System.runAs(david) {
            AutomationControlController.AutomationPageView page = AutomationControlController.getPage();
            Assert.isFalse(page.canManage, 'David may read the page but not change it.');

            for (String action : new List<String>{ 'pause', 'resume', 'switch' }) {
                try {
                    if (action == 'pause') {
                        AutomationControlController.pauseAll(2);
                    } else if (action == 'resume') {
                        AutomationControlController.resumeAll();
                    } else {
                        AutomationControlController.setEnabled(NAMING, false);
                    }
                    Assert.fail('David should not be able to ' + action + '.');
                } catch (AuraHandledException expected) {
                    Assert.areEqual(
                        Label.Core_Automation_NoPermission,
                        expected.getMessage(),
                        'The message names the permission David needs.'
                    );
                }
            }
        }
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Setting_Change__c], 'Nothing was changed.');
    }

    @IsTest
    static void aPauseLengthThatIsNotOfferedIsRefused() {
        TestDataFactory.defaultSettings();
        User maria = createPeople().get('maria');

        Test.startTest();
        System.runAs(maria) {
            try {
                AutomationControlController.pauseAll(3);
                Assert.fail('Three hours is not one of the offered lengths.');
            } catch (AuraHandledException expected) {
                Assert.areEqual(
                    Label.Core_Automation_PauseHoursInvalid,
                    expected.getMessage(),
                    'Maria is told which lengths she can choose.'
                );
            }
            try {
                AutomationControlController.setEnabled('   ', false);
                Assert.fail('An automation with no name should be refused.');
            } catch (AuraHandledException expected) {
                Assert.areEqual(
                    Label.Core_Automation_NameRequired,
                    expected.getMessage(),
                    'Maria is told to pick an automation.'
                );
            }
        }
        Test.stopTest();
    }
}

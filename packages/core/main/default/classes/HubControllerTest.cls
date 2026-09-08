/**
 * Maria lands on the Hub home page and is told what to do next. David, without the
 * Manage Nonprofit Settings permission, can read the checklist but not tick it off.
 */
@IsTest
private class HubControllerTest {
    private static final String EDIT_PERMISSION = 'Manage_Nonprofit_Settings';

    @TestSetup
    static void grantPermission() {
        SettingsTestPermissions.grantTo('C03_Hub_Home_Test', UserInfo.getUserId());
    }

    private static User buildDavid() {
        Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        return new User(
            FirstName = 'David',
            LastName = 'Okonkwo',
            Alias = 'davidh',
            Email = 'david.hub@example.com',
            Username = 'david.hub.' + DateTime.now().getTime() + '@example.com',
            ProfileId = standard.Id,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }

    @IsTest
    static void tellsMariaWhatToDoNext() {
        Test.startTest();
        HubController.HomeModel model = HubController.getHomeModel();
        Test.stopTest();

        Assert.areEqual(8, model.stepsTotal, 'The checklist has eight steps');
        Assert.areEqual(8, model.steps.size(), 'Every step is sent to the page');
        Assert.isNotNull(model.stepsCompleted, 'The page says how many are done');
        Assert.isFalse(model.automationPaused, 'Nothing is paused on a fresh org');
        Assert.areEqual(0, model.newErrorCount, 'A fresh org has nothing to review');
    }

    @IsTest
    static void marksAStepDoneAndBackAgain() {
        Assert.isTrue(
            FeatureManagement.checkPermission(EDIT_PERMISSION),
            'The permission set built in setup carries Manage Nonprofit Settings'
        );

        Test.startTest();
        HubController.HomeModel done = HubController.markStepDone('modules');
        HubController.HomeModel undone = HubController.markStepNotDone('modules');
        Test.stopTest();

        Assert.areEqual(
            done.stepsCompleted - 1,
            undone.stepsCompleted,
            'Putting a step back on the list is one fewer done'
        );
    }

    @IsTest
    static void refusesAStepItDoesNotShip() {
        Boolean refused = false;

        Test.startTest();
        try {
            HubController.markStepDone('not-a-step');
        } catch (AuraHandledException e) {
            refused = true;
        }
        Test.stopTest();

        Assert.isTrue(refused, 'A step key the package does not ship is refused');
    }

    @IsTest
    static void letsDavidReadTheChecklistWithoutTickingItOff() {
        User david = buildDavid();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert david;
        }
        Boolean refused = false;

        Test.startTest();
        System.runAs(david) {
            HubController.HomeModel model = HubController.getHomeModel();
            Assert.areEqual(8, model.steps.size(), 'David sees the same checklist');
            Assert.isFalse(model.canEdit, 'David may not change anything');
            try {
                HubController.markStepDone('modules');
            } catch (AuraHandledException e) {
                refused = true;
            }
        }
        Test.stopTest();

        Assert.isTrue(refused, 'Marking a step done without the permission is refused');
    }
}

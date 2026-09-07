/**
 * Maria works down the setup checklist, and the Hub remembers where she got to.
 */
@IsTest
private class SetupAssistantServiceTest {
    @TestSetup
    static void grantPermission() {
        SettingsTestPermissions.grantTo('C03_Setup_Assistant_Test', UserInfo.getUserId());
    }

    @IsTest
    static void shipsEightStepsInOrder() {
        Test.startTest();
        List<SetupAssistantService.Step> steps = SetupAssistantService.getSteps();
        Test.stopTest();

        Assert.areEqual(8, steps.size(), 'The plan describes eight setup steps');
        for (Integer i = 0; i < steps.size(); i++) {
            Assert.areEqual(
                i + 1,
                steps[i].position,
                'Steps are numbered in the order Maria works through them'
            );
            Assert.isNotNull(steps[i].label, 'Every step is named in the language Maria uses');
            Assert.isNotNull(steps[i].description, 'Every step says what it is for');
            Assert.isNotNull(steps[i].completed, 'Every step says whether it is done');
        }
        Assert.isFalse(
            stepByKey(steps, 'modules').completed,
            'A step nobody has marked and no setting completes is still to do'
        );
        Assert.areEqual(
            'coexistence',
            steps[0].key,
            'Confirming how Open Impact fits the org comes first'
        );
        Assert.areEqual(
            '/lightning/setup/ManageUsers/home',
            steps[3].setupPath,
            'Creating a colleague who has never signed in is the one part of access Salesforce keeps in Setup'
        );
    }

    @IsTest
    static void remembersWhichStepsAreDone() {
        Integer before = SetupAssistantService.countCompleted(SetupAssistantService.getSteps());

        Test.startTest();
        List<SetupAssistantService.Step> afterMarking = SetupAssistantService.markComplete(
            'modules'
        );
        Test.stopTest();

        Assert.areEqual(
            before + 1,
            SetupAssistantService.countCompleted(afterMarking),
            'One more step is done'
        );
        Assert.isTrue(
            stepByKey(afterMarking, 'modules').completed,
            'The step Maria marked is the one that is done'
        );

        List<SetupAssistantService.Step> afterUnmarking = SetupAssistantService.markIncomplete(
            'modules'
        );
        Assert.areEqual(
            before,
            SetupAssistantService.countCompleted(afterUnmarking),
            'Maria can put a step back on the list'
        );
    }

    @IsTest
    static void countsAStepDoneWhenItsSettingIsFilledIn() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
        SettingsService.saveSystemValue('Household_Name_Pattern__c', 'The {LastName} Family');

        Test.startTest();
        List<SetupAssistantService.Step> steps = SetupAssistantService.getSteps();
        Test.stopTest();

        Assert.isTrue(
            stepByKey(steps, 'naming').completed,
            'A step whose setting already has a value does not need marking'
        );
    }

    @IsTest
    static void refusesAStepItDoesNotShip() {
        Boolean refused = false;

        Test.startTest();
        try {
            SetupAssistantService.markComplete('not-a-step');
        } catch (SetupAssistantService.SetupStepException e) {
            refused = true;
            Assert.areEqual(
                System.Label.Core_SetupAssistant_UnknownStepError,
                e.getMessage(),
                'The message says what to do next'
            );
        }
        Test.stopTest();

        Assert.isTrue(refused, 'A step key the package does not ship is refused');
    }

    private static SetupAssistantService.Step stepByKey(
        List<SetupAssistantService.Step> steps,
        String key
    ) {
        for (SetupAssistantService.Step step : steps) {
            if (step.key == key) {
                return step;
            }
        }
        return null;
    }
}

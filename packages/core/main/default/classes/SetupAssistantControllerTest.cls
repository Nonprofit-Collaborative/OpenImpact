/**
 * Maria works through the guided assistant: she confirms how Open Impact fits her
 * Nonprofit Cloud org, fills in what her receipts need, skips the step that is waiting for
 * the Giving module, and starts again when she wants to.
 *
 * Whether the running user holds `Manage_Nonprofit_Settings` depends on the org the tests
 * run in, so every test that saves something accepts either outcome and asserts that the
 * outcome matches the permission, the same way the settings console tests do.
 */
@IsTest
private class SetupAssistantControllerTest {
    private static final String EDIT_PERMISSION = 'Manage_Nonprofit_Settings';

    @IsTest
    static void opensWithEveryPanelItNeeds() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();

        Test.startTest();
        SetupAssistantController.SetupState state = SetupAssistantController.getState();
        Test.stopTest();

        Assert.areEqual(8, state.stepsTotal, 'The plan describes eight setup steps');
        Assert.areEqual(8, state.steps.size(), 'Every step is sent to the page at once');
        Assert.isNotNull(state.coexistence, 'Step one needs what detection found');
        Assert.isNotNull(state.giving, 'Step three needs to know whether Giving is here');
        Assert.isNotNull(state.identity, 'Step five needs the values it is going to edit');
        Assert.areEqual(6, state.modules.size(), 'Step six lists the six Open Impact packages');
        Assert.isNotNull(state.roles, 'Step four needs the roles it can give out');
        Assert.isFalse(state.isComplete, 'A fresh org has not finished setup');
    }

    @IsTest
    static void leadsWithTheNonprofitCloudCase() {
        OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
        shape.hasPersonAccounts = true;
        SetupAssistantService.stubbedShape = shape;

        Test.startTest();
        SetupAssistantController.SetupState state = SetupAssistantController.getState();
        Test.stopTest();

        Assert.areEqual(
            SetupAssistantService.SHAPE_PERSON_ACCOUNTS,
            state.coexistence.detectedShape,
            'An org with Person Accounts is recognised as the Nonprofit Cloud case'
        );
        Assert.areEqual(
            SetupAssistantService.MODE_AGENTFORCE,
            state.coexistence.recommendedMode,
            'That org is recommended Agentforce Nonprofit coexistence (plan Section 4.5)'
        );
    }

    @IsTest
    static void recommendsNpspCoexistenceWhenNpspIsInstalled() {
        OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
        shape.hasNpsp = true;
        SetupAssistantService.stubbedShape = shape;

        Test.startTest();
        String recommended = SetupAssistantService.recommendedMode();
        Test.stopTest();

        Assert.areEqual(
            SetupAssistantService.MODE_NPSP,
            recommended,
            'An org with NPSP keeps the households it already has'
        );
    }

    @IsTest
    static void confirmsTheCoexistenceModeAndMarksStepOneDone() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
        Boolean canEdit = FeatureManagement.checkPermission(EDIT_PERMISSION);

        Test.startTest();
        try {
            SetupAssistantController.SetupState state = SetupAssistantController.applyCoexistence(
                SetupAssistantService.MODE_STANDALONE
            );
            Assert.isTrue(canEdit, 'Only a user with the permission gets this far');
            Assert.isTrue(
                stepByKey(state.steps, 'coexistence').completed,
                'Confirming the mode is what finishes step one'
            );
            Assert.isNotNull(
                state.elapsedMinutes,
                'The clock starts at the first change Maria makes'
            );
        } catch (AuraHandledException e) {
            Assert.isFalse(canEdit, 'Maria must be able to confirm the mode');
        }
        Test.stopTest();
    }

    @IsTest
    static void refusesAModeItDoesNotKnow() {
        Boolean refused = false;

        Test.startTest();
        try {
            SetupAssistantController.applyCoexistence('SomethingElse');
        } catch (AuraHandledException e) {
            refused = true;
        }
        Test.stopTest();

        Assert.isTrue(refused, 'A mode outside the three the plan names is refused');
    }

    @IsTest
    static void savesTheOrganizationIdentityAndFinishesStepFive() {
        SettingDefinitionSelector.stubbedRows = identityRows();
        Boolean canEdit = FeatureManagement.checkPermission(EDIT_PERMISSION);

        Test.startTest();
        try {
            SetupAssistantController.SetupState state = SetupAssistantController.saveOrganizationIdentity(
                new Map<String, Object>{
                    'Organization_Legal_Name__c' => 'Riverside Community Aid',
                    'Organization_EIN__c' => '12-3456789',
                    'Receipt_Signer_Name__c' => 'Ana Ruiz'
                }
            );
            Assert.isTrue(canEdit, 'Only a user with the permission gets this far');
            Assert.areEqual(
                'Riverside Community Aid',
                state.identity.get('Organization_Legal_Name__c'),
                'The legal name is what receipts are printed with'
            );
            Assert.isTrue(
                stepByKey(state.steps, 'identity').completed,
                'A receipt needs the legal name, so that is what finishes the step'
            );
        } catch (AuraHandledException e) {
            Assert.isFalse(canEdit, 'Maria must be able to record her receipt details');
        }
        Test.stopTest();
    }

    @IsTest
    static void refusesAnIdentitySaveWithNothingInIt() {
        Boolean refused = false;

        Test.startTest();
        try {
            SetupAssistantController.saveOrganizationIdentity(
                new Map<String, Object>{ 'Not_A_Setting__c' => 'x' }
            );
        } catch (AuraHandledException e) {
            refused = true;
        }
        Test.stopTest();

        Assert.isTrue(refused, 'Only the seven identity keys are accepted, and nothing else');
    }

    @IsTest
    static void refusesGivingDefaultsWhileTheGivingModuleIsAbsent() {
        Boolean canEdit = FeatureManagement.checkPermission(EDIT_PERMISSION);
        Boolean refused = false;
        String message;

        Test.startTest();
        try {
            SetupAssistantController.saveDefaults(null, null);
        } catch (AuraHandledException e) {
            refused = true;
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.isTrue(refused, 'There is no fund to point at until Giving is installed');
        if (canEdit) {
            Assert.areEqual(
                System.Label.Core_SetupAssistant_GivingRequiredError,
                message,
                'The message tells Maria to install the module'
            );
        }
    }

    @IsTest
    static void marksTheGivingStepUnavailableWhileGivingIsAbsent() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();

        Test.startTest();
        SetupAssistantController.SetupState state = SetupAssistantController.getState();
        Test.stopTest();

        Assert.isFalse(
            stepByKey(state.steps, 'funddefaults').isAvailable,
            'Step three waits for the Giving module'
        );
        Assert.isTrue(
            stepByKey(state.steps, 'coexistence').isAvailable,
            'Every other step can be done on a Core only org'
        );
    }

    @IsTest
    static void skipsAStepWithoutCountingItDone() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
        Boolean canEdit = FeatureManagement.checkPermission(EDIT_PERMISSION);

        Test.startTest();
        try {
            SetupAssistantController.SetupState state = SetupAssistantController.skipStep(
                'funddefaults'
            );
            Assert.isTrue(canEdit, 'Only a user with the permission gets this far');
            SetupAssistantService.Step step = stepByKey(state.steps, 'funddefaults');
            Assert.isTrue(step.skipped, 'The step is out of the way');
            Assert.isFalse(step.completed, 'Skipping is not finishing');
            Assert.areEqual(
                0,
                state.stepsCompleted,
                'A skipped step does not count towards progress'
            );
        } catch (AuraHandledException e) {
            Assert.isFalse(canEdit, 'Maria must be able to skip a step that is waiting');
        }
        Test.stopTest();
    }

    @IsTest
    static void finishesAStepThatHasNoSettingBehindIt() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
        Boolean canEdit = FeatureManagement.checkPermission(EDIT_PERMISSION);

        Test.startTest();
        try {
            SetupAssistantController.SetupState state = SetupAssistantController.completeStep(
                'modules'
            );
            Assert.isTrue(canEdit, 'Only a user with the permission gets this far');
            Assert.isTrue(
                stepByKey(state.steps, 'modules').completed,
                'Reading the module list is what finishes step six'
            );
        } catch (AuraHandledException e) {
            Assert.isFalse(canEdit, 'Maria must be able to finish a step');
        }
        Test.stopTest();
    }

    @IsTest
    static void refusesAStepTheAssistantDoesNotShip() {
        Boolean refused = false;

        Test.startTest();
        try {
            SetupAssistantController.completeStep('not-a-step');
        } catch (AuraHandledException e) {
            refused = true;
        }
        Test.stopTest();

        Assert.isTrue(refused, 'A step key the package does not ship is refused');
    }

    @IsTest
    static void givesAColleagueARoleAndFinishesStepFour() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
        Boolean canEdit = FeatureManagement.checkPermission(EDIT_PERMISSION);

        Test.startTest();
        try {
            SetupAssistantController.SetupState state = SetupAssistantController.assignAccess(
                UserInfo.getUserId(),
                'Nonprofit_Admin'
            );
            Assert.isTrue(canEdit, 'Only a user with the permission gets this far');
            Assert.isTrue(
                stepByKey(state.steps, 'access').completed,
                'Giving someone a role is what finishes step four'
            );
        } catch (AuraHandledException e) {
            Assert.isFalse(canEdit, 'Maria must be able to give a colleague a role');
        }
        Test.stopTest();
    }

    @IsTest
    static void refusesAccessWithNobodyChosen() {
        Boolean refused = false;

        Test.startTest();
        try {
            SetupAssistantController.assignAccess(null, null);
        } catch (AuraHandledException e) {
            refused = true;
        }
        Test.stopTest();

        Assert.isTrue(refused, 'A person and a role are both needed');
    }

    @IsTest
    static void startsAgainWhenTheOrganizationChanges() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
        Boolean canEdit = FeatureManagement.checkPermission(EDIT_PERMISSION);

        Test.startTest();
        try {
            SetupAssistantController.completeStep('modules');
            SetupAssistantController.SetupState state = SetupAssistantController.reset();
            Assert.isTrue(canEdit, 'Only a user with the permission gets this far');
            Assert.areEqual(0, state.stepsCompleted, 'Every step is back on the list');
            Assert.isNull(state.elapsedMinutes, 'The clock starts again with the next change');
        } catch (AuraHandledException e) {
            Assert.isFalse(canEdit, 'Maria must be able to run setup again');
        }
        Test.stopTest();
    }

    private static List<Setting_Definition__mdt> identityRows() {
        List<Setting_Definition__mdt> rows = new List<Setting_Definition__mdt>();
        for (
            String key : new List<String>{
                'Organization_Legal_Name__c',
                'Organization_EIN__c',
                'Organization_Address__c',
                'Receipt_Logo_Document_Id__c',
                'Receipt_Signature_Document_Id__c',
                'Receipt_Signer_Name__c',
                'Receipt_Signer_Title__c'
            }
        ) {
            rows.add(
                new Setting_Definition__mdt(
                    Setting_Key__c = key,
                    Settings_Object__c = 'Nonprofit_Settings__c',
                    Section__c = 'Organization',
                    Module__c = 'Core',
                    Data_Type__c = 'Text'
                )
            );
        }
        return rows;
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

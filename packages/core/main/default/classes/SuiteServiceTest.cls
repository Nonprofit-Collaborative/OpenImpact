/**
 * Maria says which suite she is setting up, and the Setup Assistant offers the modules that
 * suite has (C-30, ADR-0046). Each test says whether Giving is present, through
 * `ModuleDetectionService.stubbedPresent`, because Core is tested both on its own and with
 * Giving deployed beside it, and says which modules' steps are installed, through
 * `SetupAssistantTestExtension`, which stands in for Giving's steps.
 */
@IsTest
private class SuiteServiceTest {
    @TestSetup
    static void grantPermission() {
        SettingsTestPermissions.grantTo('C30_Suite_Test', UserInfo.getUserId());
    }

    private static void givingInstalled(Boolean installed) {
        ModuleDetectionService.stubbedPresent = installed
            ? new Set<String>{ 'giving' }
            : new Set<String>();
    }

    private static SuiteService.SuiteOption optionFor(SuiteService.SuiteModel model, String suite) {
        for (SuiteService.SuiteOption option : model.options) {
            if (option.value == suite) {
                return option;
            }
        }
        return null;
    }

    private static List<String> names(List<ModuleDetectionService.ModuleInfo> modules) {
        List<String> names = new List<String>();
        for (ModuleDetectionService.ModuleInfo module : modules) {
            names.add(module.name);
        }
        return names;
    }

    private static ModuleDetectionService.ModuleInfo byName(
        List<ModuleDetectionService.ModuleInfo> modules,
        String name
    ) {
        for (ModuleDetectionService.ModuleInfo module : modules) {
            if (module.name == name) {
                return module;
            }
        }
        return null;
    }

    @IsTest
    static void suggestsTheNonprofitSuiteWhenGivingIsInstalled() {
        givingInstalled(true);

        Test.startTest();
        SuiteService.SuiteModel model = SuiteService.model();
        Test.stopTest();

        Assert.areEqual(SuiteService.NONPROFIT, model.recommendedSuite, 'Giving means a nonprofit');
        Assert.isNull(model.chosenSuite, 'A suggestion is not a choice');
        Assert.isTrue(model.givingPresent, 'The step knows Giving is here');
        Assert.areEqual(
            new List<String>{ SuiteService.NONPROFIT, SuiteService.COMMUNITY },
            new List<String>{ model.options[0].value, model.options[1].value },
            'Both suites are offered, the Nonprofit Suite first'
        );
        for (SuiteService.SuiteOption option : model.options) {
            Assert.isTrue(String.isNotBlank(option.label), 'Each suite is named');
            Assert.isTrue(String.isNotBlank(option.description), 'Each suite says who it is for');
        }
    }

    @IsTest
    static void suggestsTheCommunitySuiteWithoutGiving() {
        givingInstalled(false);

        Test.startTest();
        SuiteService.SuiteModel model = SuiteService.model();
        Test.stopTest();

        Assert.areEqual(SuiteService.COMMUNITY, model.recommendedSuite, 'Core alone is Community');
        Assert.isFalse(model.givingPresent, 'The step knows Giving is not here');
    }

    @IsTest
    static void theNonprofitSuiteListsGivingThenTheOptionalModules() {
        givingInstalled(true);

        Test.startTest();
        List<ModuleDetectionService.ModuleInfo> modules = SuiteService.modulesFor(
            SuiteService.NONPROFIT
        );
        Test.stopTest();

        Assert.areEqual(
            new List<String>{
                'Giving',
                'Programs',
                'Logic Models',
                'Volunteers',
                'Funders',
                'Connect'
            },
            names(modules),
            'The shipped rows list Giving first, then the optional modules in order'
        );
        Assert.isTrue(modules[0].required, 'The suite needs Giving');
        Assert.isTrue(modules[0].present, 'And Giving is installed here');
        for (Integer i = 1; i < modules.size(); i++) {
            Assert.isFalse(modules[i].required, modules[i].name + ' is optional');
            Assert.isFalse(modules[i].present, modules[i].name + ' is not installed here');
        }
        for (ModuleDetectionService.ModuleInfo module : modules) {
            Assert.isNull(module.installUrl, 'No package version exists, so no install link');
            Assert.isTrue(
                module.docsUrl.endsWith('docs/admin-guide/setup-assistant.md'),
                'Learn more opens the admin guide'
            );
        }
    }

    @IsTest
    static void theCommunitySuiteNeverListsAModuleOnlyForNonprofits() {
        givingInstalled(true);

        Test.startTest();
        List<ModuleDetectionService.ModuleInfo> modules = optionFor(
                SuiteService.model(),
                SuiteService.COMMUNITY
            )
            .modules;
        Test.stopTest();

        Assert.areEqual(
            new List<String>{ 'Volunteers' },
            names(modules),
            'Only the modules that fit any organization, even with Giving installed'
        );
        Assert.isFalse(modules[0].required, 'The Community Suite needs no module');
    }

    @IsTest
    static void saysWhichOfTheSuitesModulesAreInstalled() {
        ModuleDetectionService.stubbedPresent = new Set<String>{ 'volunteers', 'logicmodels' };

        Test.startTest();
        List<ModuleDetectionService.ModuleInfo> nonprofit = SuiteService.modulesFor(
            SuiteService.NONPROFIT
        );
        List<ModuleDetectionService.ModuleInfo> community = SuiteService.modulesFor(
            SuiteService.COMMUNITY
        );
        Test.stopTest();

        Assert.isFalse(byName(nonprofit, 'Giving').present, 'Giving is not here');
        Assert.isTrue(byName(nonprofit, 'Logic Models').present, 'A two word name is matched');
        Assert.isTrue(byName(nonprofit, 'Volunteers').present, 'Volunteers is here');
        Assert.isFalse(byName(nonprofit, 'Programs').present, 'Programs is not');
        Assert.isTrue(byName(community, 'Volunteers').present, 'The same answer in each suite');
    }

    @IsTest
    static void anInstallLinkArrivesAsDataAndOnlyOnASecureAddress() {
        givingInstalled(false);
        SuiteService.stubbedRows = new List<Suite_Module__mdt>{
            new Suite_Module__mdt(
                Suite__c = SuiteService.COMMUNITY,
                Module__c = 'Events',
                Sort_Order__c = 20,
                Install_Url__c = 'javascript:alert(1)'
            ),
            new Suite_Module__mdt(
                Suite__c = SuiteService.COMMUNITY,
                Module__c = 'Volunteers',
                Sort_Order__c = 10,
                Install_Url__c = 'https://example.org/install/volunteers',
                Help_Path__c = 'setup-assistant.md'
            ),
            new Suite_Module__mdt(
                Suite__c = SuiteService.NONPROFIT,
                Module__c = 'Giving',
                Required__c = true,
                Sort_Order__c = 10
            )
        };

        Test.startTest();
        List<ModuleDetectionService.ModuleInfo> modules = SuiteService.modulesFor(
            SuiteService.COMMUNITY
        );
        Test.stopTest();

        Assert.areEqual(
            new List<String>{ 'Volunteers', 'Events' },
            names(modules),
            'A new module is a new row, placed by its order, with no code change'
        );
        Assert.areEqual(
            'https://example.org/install/volunteers',
            modules[0].installUrl,
            'A row that carries an installer address offers it'
        );
        Assert.isNull(modules[1].installUrl, 'Anything but a secure web address is never a link');
        Assert.isNull(modules[1].docsUrl, 'A row with no help path has no Learn more link');
    }

    @IsTest
    static void aSuiteNobodyChoseIsNeverReadAsAChoice() {
        SettingsService.saveSystemValue(SuiteService.SETTING_KEY, 'Enterprise');

        Test.startTest();
        String chosen = SuiteService.chosenSuite();
        Test.stopTest();

        Assert.isNull(chosen, 'A value that is not one of the two suites is no choice at all');
    }

    @IsTest
    static void refusesASuiteThatIsNotOneOfTheTwo() {
        String message;

        Test.startTest();
        try {
            SuiteService.choose('  ');
        } catch (SuiteService.SuiteException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.areEqual(System.Label.Core_SetupAssistant_UnknownSuiteError, message, 'Refused');
    }

    @IsTest
    static void choosingTheNonprofitSuiteWithoutGivingKeepsTheCoreSteps() {
        givingInstalled(false);
        SetupAssistantTestExtension.useNone();

        Test.startTest();
        SuiteService.choose(SuiteService.NONPROFIT);
        SuiteService.SuiteModel model = SuiteService.model();
        List<SetupAssistantService.Step> steps = SetupAssistantService.getSteps();
        Test.stopTest();

        Assert.areEqual(SuiteService.NONPROFIT, model.chosenSuite, 'The choice is kept');
        Assert.isFalse(model.givingPresent, 'So the step can say Giving must be installed');
        Assert.isFalse(
            optionFor(model, SuiteService.NONPROFIT).modules[0].present,
            'Giving is listed as not installed, with how to get it'
        );
        Assert.areEqual(7, steps.size(), 'Setup carries on with the seven Core steps');
        Assert.isTrue(steps[0].completed, 'And the suite step is done');
    }

    @IsTest
    static void choosingTheCommunitySuiteWithGivingKeepsGivingsSteps() {
        givingInstalled(true);
        SetupAssistantTestExtension.useThis();

        Test.startTest();
        SuiteService.choose(SuiteService.COMMUNITY);
        List<SetupAssistantService.Step> steps = SetupAssistantService.getSteps();
        Test.stopTest();

        Assert.areEqual(SuiteService.COMMUNITY, SuiteService.chosenSuite(), 'The choice is kept');
        Assert.areEqual(8, steps.size(), 'An installed module keeps its step: nothing is hidden');
        Assert.isNotNull(
            SetupAssistantService.findStep(SetupAssistantTestExtension.STEP_KEY),
            'The module step is still there'
        );
    }

    @IsTest
    static void anOrgThatNeverChoseBehavesAsBefore() {
        givingInstalled(true);
        SetupAssistantTestExtension.useThis();
        SetupAssistantService.markComplete('modules');

        Test.startTest();
        List<SetupAssistantService.Step> steps = SetupAssistantService.getSteps();
        Test.stopTest();

        Assert.isNull(SuiteService.chosenSuite(), 'Nobody chose');
        Assert.areEqual(8, steps.size(), 'The same eight steps with the module');
        Assert.isTrue(
            steps[0].completed,
            'Progress recorded on the module list still counts for the step that replaced it'
        );
    }
}

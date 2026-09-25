/**
 * A stand-in module for Core's Setup Assistant tests (C-29, ADR-NEXT). Core is tested on its
 * own, where no module is installed, and beside Giving, whose steps would change what each
 * test counts. Each test therefore says which modules it runs with: none, this one, or one
 * that fails.
 *
 * This module adds a step of its own third, with a record picker, and adds a field and its
 * own wording to Core's organization step, which is what Giving does.
 */
@IsTest
public class SetupAssistantTestExtension implements SetupAssistantExtension {
    public static final String STEP_KEY = 'moduledefaults';
    public static final String STEP_LABEL = 'Choose a default contact';
    public static final String IDENTITY_WORDING = 'The organization step, in the module words.';
    // A Core text setting stands in for the module's own: Core's tests have no other settings
    // object to write, and a record identifier fits in any text setting.
    public static final String RECORD_KEY = 'Organization_Address__c';

    private final Boolean fails;

    public SetupAssistantTestExtension() {
        this(false);
    }

    public SetupAssistantTestExtension(Boolean fails) {
        this.fails = fails;
    }

    /** Runs the assistant with no module installed: Core alone. */
    public static void useNone() {
        SetupAssistantExtensions.overrides = new List<SetupAssistantExtension>();
    }

    /** Runs the assistant with this module installed. */
    public static void useThis() {
        SetupAssistantExtensions.overrides = new List<SetupAssistantExtension>{
            new SetupAssistantTestExtension()
        };
    }

    public List<SetupAssistantService.Step> contributions() {
        if (fails) {
            throw new System.IllegalArgumentException('A module that cannot answer');
        }
        SetupAssistantService.Step moduleStep = new SetupAssistantService.Step(
                STEP_KEY,
                25,
                STEP_LABEL,
                'What the module step is for.'
            )
            .completedBy(SettingsService.CORE_SETTINGS_OBJECT, RECORD_KEY)
            .withField(
                new SetupAssistantService.StepField(
                        SetupAssistantService.FIELD_RECORD,
                        10,
                        null,
                        RECORD_KEY,
                        'Default contact'
                    )
                    .withObject('Contact')
            )
            .advancingOnSave();
        SetupAssistantService.Step identityAddition = new SetupAssistantService.Step(
                'identity',
                null,
                null,
                IDENTITY_WORDING
            )
            .withField(
                new SetupAssistantService.StepField(
                        SetupAssistantService.FIELD_NAVIGATE,
                        20,
                        null,
                        null,
                        'Open the module'
                    )
                    .withNavigationTarget('Module_Tab')
            );
        return new List<SetupAssistantService.Step>{ moduleStep, identityAddition };
    }
}

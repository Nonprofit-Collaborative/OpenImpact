/**
 * The four guarantees the fix framework makes, proven against actions written to break them
 * (feature C-21, ADR-0029).
 *
 * NOT EXECUTED. There was no Salesforce org reachable from the environment these tests were
 * written in, so they have been compiled and reviewed but never run. Run them before trusting
 * any fix action: a fix that has never been executed is the riskiest thing in this feature.
 *
 * The actions here are deliberately unlike the real ones. A real fix cannot be made to fail on
 * demand, and an action that fails halfway is exactly what the savepoint exists for.
 */
@IsTest
private class HealthCheckFixTest {
    private static final String KEY = 'testAction';
    private static final String AUDIT_NAME = 'Health Check fix: ' + KEY;

    private class SampleException extends Exception {
    }

    /** An action that reports one thing to do, and does it. */
    private class WorkingAction implements HealthCheckFix.Action {
        private Boolean setupWriter;
        private Integer applyCount = 0;

        private WorkingAction(Boolean setupWriter) {
            this.setupWriter = setupWriter;
        }

        public String key() {
            return KEY;
        }

        public Boolean writesSetupData() {
            return this.setupWriter;
        }

        public HealthCheckFix.Preview preview() {
            return new HealthCheckFix.Preview(KEY, 'A test fix', 'It will change one thing.', 1)
                .naming(new List<String>{ 'The one thing' });
        }

        public HealthCheckFix.Result apply(HealthCheckFix.Preview ignored) {
            this.applyCount++;
            return new HealthCheckFix.Result(KEY, 'A test fix', 'It changed one thing.', 1);
        }
    }

    /** An action with nothing to do, which is what every fix looks like the second time. */
    private class SatisfiedAction implements HealthCheckFix.Action {
        private Integer applyCount = 0;

        public String key() {
            return KEY;
        }

        public Boolean writesSetupData() {
            return false;
        }

        public HealthCheckFix.Preview preview() {
            return new HealthCheckFix.Preview(KEY, 'A test fix', 'Nothing to change.', 0);
        }

        public HealthCheckFix.Result apply(HealthCheckFix.Preview ignored) {
            this.applyCount++;
            return new HealthCheckFix.Result(KEY, 'A test fix', 'It should not run.', 1);
        }
    }

    /** An action that writes and then fails, which is what the savepoint is for. */
    private class HalfDoneAction implements HealthCheckFix.Action {
        public String key() {
            return KEY;
        }

        public Boolean writesSetupData() {
            return false;
        }

        public HealthCheckFix.Preview preview() {
            return new HealthCheckFix.Preview(KEY, 'A test fix', 'It will change two things.', 2);
        }

        public HealthCheckFix.Result apply(HealthCheckFix.Preview ignored) {
            SettingsService.logChange('Half done', 'before', 'after');
            throw new SampleException('The second half failed.');
        }
    }

    private static void register(HealthCheckFix.Action action) {
        HealthCheckFix.registryOverride = new Map<String, HealthCheckFix.Action>{ KEY => action };
    }

    @IsTest
    static void theSixShippedActionsAreRegistered() {
        Map<String, HealthCheckFix.Action> actions = HealthCheckFix.actions();

        Assert.areEqual(6, actions.size(), 'Six fixes pass the ADR-0029 conditions, and no more.');
        for (
            String key : new List<String>{
                HealthCheckFix.KEY_RECOMMENDED_MODE,
                HealthCheckFix.KEY_JUNCTION_MEMBERSHIP,
                HealthCheckFix.KEY_SHIPPED_ROLLUPS,
                HealthCheckFix.KEY_AUTOMATION_SWITCHES,
                HealthCheckFix.KEY_IMPORT_TEMPLATES,
                HealthCheckFix.KEY_ADMIN_ROLE
            }
        ) {
            Assert.isTrue(HealthCheckFix.isAction(key), key + ' is an action Health Check offers.');
            Assert.areEqual(key, actions.get(key).key(), 'Each action answers to its own key.');
        }
    }

    @IsTest
    static void aPreviewSaysWhatWouldChangeAndWritesNothing() {
        register(new WorkingAction(false));

        Test.startTest();
        HealthCheckFix.Preview preview = HealthCheckFix.preview(KEY);
        Test.stopTest();

        Assert.areEqual(1, preview.affected, 'It counts what it would change.');
        Assert.areEqual(false, preview.nothingToDo, 'There is something to do.');
        Assert.areEqual(1, preview.items.size(), 'It names the thing it would change.');
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Setting_Change__c],
            'A preview reads the org and writes nothing at all.'
        );
    }

    @IsTest
    static void applyingRunsTheActionAndRecordsThatItRan() {
        WorkingAction action = new WorkingAction(false);
        register(action);

        Test.startTest();
        HealthCheckFix.Result result = HealthCheckFix.apply(KEY);
        Test.stopTest();

        Assert.areEqual(1, action.applyCount, 'The action ran once.');
        Assert.areEqual(1, result.changed, 'It reports what it changed.');
        Assert.areEqual(true, result.changedAnything, 'And that it changed something.');
        List<Setting_Change__c> audit = [
            SELECT Setting_Name__c, New_Value__c
            FROM Setting_Change__c
            WHERE Setting_Name__c = :AUDIT_NAME
        ];
        Assert.areEqual(1, audit.size(), 'A fix is recorded in the same audit trail as a setting.');
        Assert.areEqual('1 changed', audit[0].New_Value__c, 'The audit says what it did.');
    }

    @IsTest
    static void pressingItTwiceIsPressingItOnce() {
        SatisfiedAction action = new SatisfiedAction();
        register(action);

        Test.startTest();
        HealthCheckFix.Result result = HealthCheckFix.apply(KEY);
        Test.stopTest();

        Assert.areEqual(0, action.applyCount, 'The action is not run when there is nothing to do.');
        Assert.areEqual(0, result.changed, 'Nothing changed.');
        Assert.areEqual(false, result.changedAnything, 'And the result says so.');
        Assert.areEqual(
            Label.Core_HealthCheckFix_NothingToDo,
            result.summary,
            'The person is told there was nothing left to do, rather than nothing at all.'
        );
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Setting_Change__c],
            'A fix with nothing to do writes no audit row either.'
        );
    }

    @IsTest
    static void aFailureLeavesNothingBehindAndReachesTheErrorLog() {
        register(new HalfDoneAction());

        Test.startTest();
        Boolean refused = false;
        try {
            HealthCheckFix.apply(KEY);
        } catch (HealthCheckFix.HealthCheckFixException e) {
            refused = true;
            Assert.areEqual(
                Label.Core_HealthCheck_FixFailed,
                e.getMessage(),
                'The person gets a sentence, not a stack trace.'
            );
        }
        Test.stopTest();

        Assert.isTrue(refused, 'A fix that fails says so rather than reporting success.');
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Setting_Change__c],
            'What the failing half wrote was rolled back: the org is not half changed.'
        );
        List<Error_Log__c> logged = [SELECT Context__c FROM Error_Log__c];
        Assert.areEqual(1, logged.size(), 'The failure is in the Error Log.');
        Assert.isTrue(
            logged[0].Context__c.contains(HealthCheckFix.ERROR_CONTEXT),
            'And it is filed under the fix that failed: ' + logged[0].Context__c
        );
    }

    @IsTest
    static void aSetupWritingActionIsNotAudited() {
        register(new WorkingAction(true));

        Test.startTest();
        HealthCheckFix.apply(KEY);
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Setting_Change__c],
            'The platform refuses setup and ordinary DML together, so this one is not audited ' +
            'here. It is visible on the Access page instead.'
        );
    }

    @IsTest
    static void anActionThatDoesNotExistChangesNothing() {
        Boolean refusedPreview = false;
        try {
            HealthCheckFix.preview('somethingNobodyShips');
        } catch (HealthCheckFix.HealthCheckFixException e) {
            refusedPreview = true;
            Assert.areEqual(Label.Core_HealthCheckFix_Unknown, e.getMessage(), 'Said plainly.');
        }

        Boolean refusedApply = false;
        try {
            HealthCheckFix.apply(null);
        } catch (HealthCheckFix.HealthCheckFixException e) {
            refusedApply = true;
        }

        Assert.isTrue(refusedPreview, 'An unknown key cannot be previewed.');
        Assert.isTrue(refusedApply, 'A blank key cannot be applied.');
        Assert.areEqual(0, [SELECT COUNT() FROM Setting_Change__c], 'And nothing was written.');
    }

    @IsTest
    static void aLongPreviewIsCutShortAndStillCountsEverything() {
        List<String> many = new List<String>();
        for (Integer index = 0; index < HealthCheckFix.PREVIEW_ITEM_LIMIT + 3; index++) {
            many.add('Thing ' + index);
        }

        HealthCheckFix.Preview preview = new HealthCheckFix.Preview(
                KEY,
                'A test fix',
                'It will change several things.',
                many.size()
            )
            .naming(many);

        Assert.areEqual(
            HealthCheckFix.PREVIEW_ITEM_LIMIT,
            preview.items.size(),
            'A long list is cut short rather than filling the page.'
        );
        Assert.areEqual(many.size(), preview.affected, 'The count is always the whole number.');
        Assert.isTrue(
            preview.moreLabel.contains('3'),
            'And the person is told how many were not listed: ' + preview.moreLabel
        );
    }
}

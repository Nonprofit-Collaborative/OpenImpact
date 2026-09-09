/**
 * The Health Check fix framework: what a fix action is, and the four guarantees every one of
 * them gets whether or not its author remembered them (feature C-21, ADR-0029).
 *
 * A fix action is a small class that can do two things: say what it would change in this org
 * right now, and change it. Everything else belongs here, once, so that no individual fix has
 * to be trusted to have got it right:
 *
 * 1. **It says what it will do before it does it.** `preview` reads the org and names the rows
 *    or the people the action would touch. The component shows that and asks for a second
 *    click. Nothing is written by a preview.
 * 2. **Pressing it twice is pressing it once.** `apply` builds the preview again, from the org,
 *    before it calls the action, and returns "there was nothing left to do" when that second
 *    preview is empty. Idempotence is therefore a property of this class, not a promise each
 *    action makes.
 * 3. **All or nothing.** The action runs inside a savepoint. Any exception rolls the whole
 *    thing back, so the org is never left half changed.
 * 4. **A failure is visible.** It goes to the Error Log through `ErrorLogger`, and comes back
 *    to the person as a sentence from a Custom Label rather than a stack trace or a silence.
 *
 * What this class deliberately does not do is delete. There is no removal path here, no action
 * may add one, and ADR-0029 condition 3 is the rule that refuses the next one to be proposed.
 *
 * Permission is enforced before this class is reached, by `HealthCheckController`, on the
 * `Manage_Nonprofit_Settings` custom permission, exactly as `RollupController` enforces it
 * before restoring the shipped rollups.
 */
public with sharing class HealthCheckFix {
    /** Raised for a fix that cannot be found, previewed, or applied. Always carries a label. */
    public class HealthCheckFixException extends Exception {
    }

    /** The context every Error Log entry from a fix carries, so they group together. */
    public static final String ERROR_CONTEXT = 'HealthCheckFix';

    /** How many things a preview names before it stops listing and starts counting. */
    public static final Integer PREVIEW_ITEM_LIMIT = 10;

    public static final String KEY_RECOMMENDED_MODE = 'applyRecommendedMode';
    public static final String KEY_JUNCTION_MEMBERSHIP = 'applyJunctionMembership';
    public static final String KEY_SHIPPED_ROLLUPS = 'restoreShippedRollups';
    public static final String KEY_AUTOMATION_SWITCHES = 'restoreAutomationSwitches';
    public static final String KEY_IMPORT_TEMPLATES = 'restoreImportTemplates';
    public static final String KEY_ADMIN_ROLE = 'finishAdminRole';

    /**
     * Lets a test register an action of its own, so that the guarantees above can be proven
     * against an action that fails on purpose. Null in every real transaction.
     */
    @TestVisible
    private static Map<String, Action> registryOverride;

    /**
     * One fix. An action is asked what it would change far more often than it is asked to
     * change it: every run of Health Check previews every action whose finding it might show.
     * So `preview` reads and never writes, and is cheap enough to call on every report.
     */
    public interface Action {
        /** The stable key the finding and the component name this action by. */
        String key();

        /** What this action would change in this org now, read fresh every time. */
        Preview preview();

        /**
         * Does it, and says what it did. Called only when a preview taken moments earlier in
         * this same transaction found something to do. An action re-reads the org rather than
         * trusting the preview it is handed, which is what makes a second press harmless even
         * if something changed in between.
         */
        Result apply(Preview preview);

        /**
         * True when the action writes a setup object such as a permission set assignment. The
         * platform refuses setup and ordinary DML in one transaction, so the framework does not
         * write its Setting Change audit row for these. They are auditable where they belong:
         * a role assignment shows on the Access page.
         */
        Boolean writesSetupData();
    }

    /** What a fix would do, counted from this org, before anybody presses anything. */
    public class Preview {
        @AuraEnabled
        public String fixKey;
        @AuraEnabled
        public String title;
        @AuraEnabled
        public String summary;
        @AuraEnabled
        public List<String> items;
        @AuraEnabled
        public String moreLabel;
        @AuraEnabled
        public Integer affected;
        @AuraEnabled
        public Boolean nothingToDo;

        public Preview(String fixKey, String title, String summary, Integer affected) {
            this.fixKey = fixKey;
            this.title = title;
            this.summary = summary;
            this.affected = affected == null ? 0 : affected;
            this.nothingToDo = this.affected <= 0;
            this.items = new List<String>();
        }

        /**
         * Names the things this fix would touch. A long list is cut short rather than filling
         * the page: the count above it is the number that matters, and it is always the whole
         * number.
         */
        public Preview naming(List<String> names) {
            if (names == null || names.isEmpty()) {
                return this;
            }
            Integer shown = Math.min(names.size(), PREVIEW_ITEM_LIMIT);
            for (Integer index = 0; index < shown; index++) {
                this.items.add(names[index]);
            }
            if (names.size() > shown) {
                this.moreLabel = String.format(
                    System.Label.Core_HealthCheckFix_AndMore,
                    new List<Object>{ String.valueOf(names.size() - shown) }
                );
            }
            return this;
        }
    }

    /** What a fix actually did, said in the same terms the preview used. */
    public class Result {
        @AuraEnabled
        public String fixKey;
        @AuraEnabled
        public String title;
        @AuraEnabled
        public String summary;
        @AuraEnabled
        public Integer changed;
        @AuraEnabled
        public Boolean changedAnything;

        public Result(String fixKey, String title, String summary, Integer changed) {
            this.fixKey = fixKey;
            this.title = title;
            this.summary = summary;
            this.changed = changed == null ? 0 : changed;
            this.changedAnything = this.changed > 0;
        }
    }

    /** The actions this version offers, by key. */
    public static Map<String, Action> actions() {
        return registryOverride == null ? HealthCheckFixCatalog.byKey() : registryOverride;
    }

    /** Whether a key names a fix action at all. */
    public static Boolean isAction(String fixKey) {
        return String.isNotBlank(fixKey) && actions().containsKey(fixKey);
    }

    /**
     * What pressing this fix would change, read from the org now. Never writes anything.
     */
    public static Preview preview(String fixKey) {
        Action action = require(fixKey);
        try {
            return action.preview();
        } catch (Exception e) {
            ErrorLogger.log(e, ERROR_CONTEXT + ': preview ' + fixKey);
            throw new HealthCheckFixException(System.Label.Core_HealthCheckFix_PreviewFailed);
        }
    }

    /**
     * Presses it. Previews again first and does nothing when there is nothing left to do, so a
     * second press, a stale page, and two administrators clicking at once all end the same way.
     */
    public static Result apply(String fixKey) {
        Action action = require(fixKey);
        Preview current = preview(fixKey);
        if (current.nothingToDo == true) {
            return new Result(
                fixKey,
                current.title,
                System.Label.Core_HealthCheckFix_NothingToDo,
                0
            );
        }

        // The savepoint is what keeps a fix from leaving the org half changed: the audit row is
        // inside it too, so a fix is either done and recorded or neither.
        System.Savepoint before = Database.setSavepoint();
        try {
            Result outcome = action.apply(current);
            audit(action, current, outcome);
            return outcome;
        } catch (Exception e) {
            Database.rollback(before);
            ErrorLogger.log(e, ERROR_CONTEXT + ': apply ' + fixKey);
            throw new HealthCheckFixException(System.Label.Core_HealthCheck_FixFailed);
        }
    }

    /**
     * Records that a fix ran, in the same audit trail every settings change uses (canonical
     * model Section 11). Skipped for an action that writes a setup object, which the platform
     * will not let us do ordinary DML alongside.
     */
    private static void audit(Action action, Preview current, Result outcome) {
        if (action.writesSetupData() == true) {
            return;
        }
        SettingsService.logChange(
            'Health Check fix: ' + action.key(),
            String.valueOf(current.affected) + ' to change',
            String.valueOf(outcome.changed) + ' changed'
        );
    }

    private static Action require(String fixKey) {
        Action action = String.isBlank(fixKey) ? null : actions().get(fixKey);
        if (action == null) {
            throw new HealthCheckFixException(System.Label.Core_HealthCheckFix_Unknown);
        }
        return action;
    }
}

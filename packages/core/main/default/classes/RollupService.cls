/**
 * The rollup engine, as the rest of Open Impact sees it.
 *
 * Everything a feature, a trigger, a batch or the console needs is here, and nothing outside this
 * package's `Rollup*` classes ever names the vendored engine (ADR-0015). Three things happen:
 *
 * - **Real time.** A trigger on a source entity calls `runRealTime`, which finds the active
 *   definitions for that entity in Real-time or Both mode, hands them to the engine as in-memory
 *   metadata, and stamps freshness when the run completes.
 * - **Scheduled.** `RollupBatch` calls `runFullRecalculation` for the definitions in Scheduled or
 *   Both mode, which is the nightly reconciliation R-R4 describes.
 * - **On demand.** `recalculate` runs one definition now, which is what the Recalculate action on
 *   the Rollups page does.
 *
 * Freshness is ours, not the engine's (ADR-0015, "Last Calculated"). The definition's own
 * `Last_Calculated__c` answers "when did this rollup last run" for the console, and the single
 * `Rollups_Last_Calculated__c` on each target entity answers "when was this record last
 * recalculated" on the record page (canonical model Section 26).
 */
@NamespaceAccessible
public with sharing class RollupService {
    /** Raised when a rollup cannot be run. */
    @NamespaceAccessible
    public class RollupServiceException extends Exception {
    }

    @NamespaceAccessible
    public static final String MODE_REAL_TIME = 'Real-time';
    @NamespaceAccessible
    public static final String MODE_SCHEDULED = 'Scheduled';
    @NamespaceAccessible
    public static final String MODE_BOTH = 'Both';

    /** The one freshness attribute every target entity carries (canonical model Section 26). */
    @NamespaceAccessible
    public static final String FRESHNESS_FIELD = 'Rollups_Last_Calculated__c';

    /** The hours after which the Hub calls the nightly run overdue (plan Section 4.10). */
    @NamespaceAccessible
    public static final Integer STALE_AFTER_HOURS = 36;

    private static final String CONTEXT_REAL_TIME = 'RollupService.runRealTime';
    private static final String CONTEXT_RECALCULATE = 'RollupService.recalculate';

    private static final Set<String> REAL_TIME_MODES = new Set<String>{ MODE_REAL_TIME, MODE_BOTH };
    private static final Set<String> SCHEDULED_MODES = new Set<String>{ MODE_SCHEDULED, MODE_BOTH };

    /** Set by a test so a run can be asserted without the engine being reachable. */
    @TestVisible
    private static Boolean skipEngine = false;

    /** What the last call handed the engine, so a test can assert the mapping end to end. */
    @TestVisible
    private static List<Rollup__mdt> lastMetadata;

    /** The modes a nightly run covers. */
    @NamespaceAccessible
    public static Set<String> scheduledModes() {
        return new Set<String>(SCHEDULED_MODES);
    }

    /** The mode a new definition starts in, from the org's default. */
    @NamespaceAccessible
    public static String defaultMode() {
        Object stored = SettingsService.getValue('Rollup_Mode_Default__c');
        String mode = stored == null ? null : String.valueOf(stored);
        return REAL_TIME_MODES.contains(mode) || MODE_SCHEDULED.equals(mode) ? mode : MODE_BOTH;
    }

    // ------------------------------------------------------------------------------- real time

    /**
     * Recalculates, in this transaction, every active real-time definition whose source entity is
     * the one that just changed.
     *
     * Called from a trigger handler, never directly, so that the automation is bypassable and
     * pausable like every other packaged automation (R-A1). A rollup that cannot be expressed is
     * logged and skipped: one broken definition must not fail the administrator's save.
     *
     * @param sourceObject the entity whose records changed
     * @param changedRecords the records in front of the trigger
     * @param oldRecords the same records as they were, or null outside an update
     */
    @NamespaceAccessible
    public static void runRealTime(
        String sourceObject,
        List<SObject> changedRecords,
        Map<Id, SObject> oldRecords
    ) {
        if (String.isBlank(sourceObject) || changedRecords == null || changedRecords.isEmpty()) {
            return;
        }
        List<Rollup_Definition__c> definitions = RollupSelector.selectActiveForSource(
            sourceObject,
            REAL_TIME_MODES
        );
        if (definitions.isEmpty()) {
            return;
        }
        List<Rollup__mdt> metadata = new List<Rollup__mdt>();
        List<Rollup_Definition__c> ran = new List<Rollup_Definition__c>();
        for (Rollup_Definition__c definition : definitions) {
            try {
                metadata.addAll(
                    RollupAdapter.toMetadata(new List<Rollup_Definition__c>{ definition })
                );
                ran.add(definition);
            } catch (Exception refused) {
                ErrorLogger.log(refused, CONTEXT_REAL_TIME, definition.Id);
            }
        }
        if (metadata.isEmpty()) {
            return;
        }
        lastMetadata = metadata;
        if (skipEngine != true) {
            // Inside a trigger the engine reads the operation from the trigger context itself,
            // which is why this entry point is only ever called from a handler.
            Rollup.runFromApex(metadata, null, changedRecords, oldRecords)?.runCalc();
        }
        stampAfterRun(ran, targetIdsFor(ran, changedRecords));
    }

    // -------------------------------------------------------------------------------- scheduled

    /**
     * A full recalculation of a set of definitions, in the engine's own batch context.
     *
     * This is the path R-R9 talks about: recalculating any set of records produces the same result
     * as calculating it the first time, so the nightly run reconciles whatever real time missed.
     *
     * @param definitions the definitions to recalculate
     * @return how many were handed to the engine
     */
    @NamespaceAccessible
    public static Integer runFullRecalculation(List<Rollup_Definition__c> definitions) {
        if (definitions == null || definitions.isEmpty()) {
            return 0;
        }
        List<Rollup__mdt> metadata = new List<Rollup__mdt>();
        List<Rollup_Definition__c> ran = new List<Rollup_Definition__c>();
        for (Rollup_Definition__c definition : definitions) {
            try {
                metadata.addAll(
                    RollupAdapter.toMetadata(new List<Rollup_Definition__c>{ definition })
                );
                ran.add(definition);
            } catch (Exception refused) {
                ErrorLogger.log(refused, CONTEXT_RECALCULATE, definition.Id);
            }
        }
        if (metadata.isEmpty()) {
            return 0;
        }
        lastMetadata = metadata;
        if (skipEngine != true) {
            Rollup.performBulkFullRecalc(
                metadata,
                Rollup.InvocationPoint.FROM_FULL_RECALC_APEX.name()
            );
        }
        stampAfterRun(ran, new Map<String, Set<Id>>());
        return ran.size();
    }

    /**
     * Recalculates one definition now. This is the Recalculate action on the Rollups page.
     *
     * @param definitionId the definition to recalculate
     */
    @NamespaceAccessible
    public static void recalculate(Id definitionId) {
        Rollup_Definition__c definition = RollupSelector.selectById(definitionId);
        if (definition == null) {
            throw new RollupServiceException(System.Label.Core_Rollups_ErrorUnknownDefinition);
        }
        runFullRecalculation(new List<Rollup_Definition__c>{ definition });
    }

    // ---------------------------------------------------------------------------- materializing

    /**
     * Creates a Rollup Definition for every shipped default that does not have one yet, and leaves
     * every existing definition exactly as the administrator left it (R-R6). Safe on every install,
     * every upgrade, and twice in a row. Returns how many it created.
     */
    @NamespaceAccessible
    public static Integer ensureDefaults() {
        List<Rollup_Definition_Default__mdt> shipped = RollupSelector.selectShippedDefaults();
        if (shipped.isEmpty()) {
            return 0;
        }
        Set<String> existingKeys = new Set<String>();
        for (Rollup_Definition__c definition : RollupSelector.selectAll()) {
            if (String.isNotBlank(definition.Definition_Key__c)) {
                existingKeys.add(definition.Definition_Key__c.toLowerCase());
            }
        }
        List<Rollup_Definition__c> toCreate = new List<Rollup_Definition__c>();
        for (Rollup_Definition_Default__mdt shippedDefault : shipped) {
            String key = shippedDefault.Definition_Key__c;
            if (String.isBlank(key) || existingKeys.contains(key.toLowerCase())) {
                continue;
            }
            if (!isShippableHere(shippedDefault)) {
                continue;
            }
            existingKeys.add(key.toLowerCase());
            toCreate.add(materialize(shippedDefault));
        }
        RollupWriter.insertDefinitions(toCreate);
        return toCreate.size();
    }

    /**
     * Whether a shipped default can be materialized in this org. A row shipped by a module that is
     * not installed has neither its source nor its target entity here, so it is skipped rather
     * than creating a definition that names objects nobody has (R-R6, plan Principle 3). Asking
     * the org what exists is the general answer: it needs no list of package names, and it is
     * right for a module Core has never heard of.
     */
    private static Boolean isShippableHere(Rollup_Definition_Default__mdt shippedDefault) {
        return SettingsService.typeByName(shippedDefault.Source_Object__c) != null &&
            SettingsService.typeByName(shippedDefault.Target_Object__c) != null;
    }

    private static Rollup_Definition__c materialize(Rollup_Definition_Default__mdt shippedDefault) {
        return new Rollup_Definition__c(
            Name = String.isBlank(shippedDefault.MasterLabel)
                ? shippedDefault.Definition_Key__c
                : shippedDefault.MasterLabel,
            Description__c = shippedDefault.Description__c,
            Definition_Key__c = shippedDefault.Definition_Key__c,
            Source_Object__c = shippedDefault.Source_Object__c,
            Target_Object__c = shippedDefault.Target_Object__c,
            Relationship_Path__c = shippedDefault.Relationship_Path__c,
            Aggregate__c = shippedDefault.Aggregate__c,
            Source_Field__c = shippedDefault.Source_Field__c,
            Order_By_Field__c = shippedDefault.Order_By_Field__c,
            Target_Field__c = shippedDefault.Target_Field__c,
            Filter_JSON__c = shippedDefault.Filter_JSON__c,
            Target_Filter_JSON__c = shippedDefault.Target_Filter_JSON__c,
            Fiscal_Year_Aware__c = shippedDefault.Fiscal_Year_Aware__c == true,
            Fiscal_Year_Offset__c = shippedDefault.Fiscal_Year_Offset__c,
            Fiscal_Date_Field__c = shippedDefault.Fiscal_Date_Field__c,
            Mode__c = String.isBlank(shippedDefault.Mode__c)
                ? defaultMode()
                : shippedDefault.Mode__c,
            Is_Package_Default__c = true,
            Active__c = shippedDefault.Default_Active__c == true
        );
    }

    // ------------------------------------------------------------------------------- freshness

    /** When the rollups were last calculated across every active definition. */
    @NamespaceAccessible
    public static Datetime lastCalculated() {
        return RollupSelector.lastCalculatedAcrossActive();
    }

    /** True when the rollups have not completed inside the freshness window. */
    @NamespaceAccessible
    public static Boolean isStale() {
        Datetime latest = lastCalculated();
        return latest == null || latest < Datetime.now().addHours(-STALE_AFTER_HOURS);
    }

    /**
     * Stamps the definitions that ran and, where the caller worked them out, the target records.
     *
     * The definition stamp lands once per call rather than once per chunk, which is what makes
     * "last calculated" mean the end of a run rather than the end of a batch.
     */
    private static void stampAfterRun(
        List<Rollup_Definition__c> ran,
        Map<String, Set<Id>> targetIdsByObject
    ) {
        if (ran.isEmpty()) {
            return;
        }
        Datetime completedAt = Datetime.now();
        Map<Id, Datetime> completedAtById = new Map<Id, Datetime>();
        for (Rollup_Definition__c definition : ran) {
            if (definition.Id != null) {
                completedAtById.put(definition.Id, completedAt);
            }
        }
        RollupWriter.stampDefinitions(completedAtById);
        for (String targetObject : targetIdsByObject.keySet()) {
            RollupWriter.stampTargets(
                targetObject,
                targetIdsByObject.get(targetObject),
                completedAt
            );
        }
    }

    /**
     * The target records a real-time run touched, grouped by entity, so their freshness attribute
     * can be stamped. Only paths the engine walks itself are resolved here; a household path is
     * resolved through `HouseholdService` by `RollupPath`, which is the same answer.
     */
    private static Map<String, Set<Id>> targetIdsFor(
        List<Rollup_Definition__c> ran,
        List<SObject> changedRecords
    ) {
        Map<String, Set<Id>> targetIdsByObject = new Map<String, Set<Id>>();
        for (Rollup_Definition__c definition : ran) {
            RollupPath.Parsed path;
            try {
                path = RollupPath.parse(definition.Relationship_Path__c);
            } catch (Exception ignored) {
                continue;
            }
            Set<Id> targetIds = new Set<Id>();
            if (path.needsHouseholdResolution()) {
                for (Set<Id> resolved : RollupPath.resolveTargets(path, changedRecords).values()) {
                    targetIds.addAll(resolved);
                }
            } else {
                RollupPath.Branch branch = path.branches[0];
                if (branch.segments.size() == 1) {
                    for (SObject changed : changedRecords) {
                        Object value = changed.get(branch.segments[0]);
                        if (value != null) {
                            targetIds.add((Id) value);
                        }
                    }
                }
            }
            if (targetIds.isEmpty()) {
                continue;
            }
            if (!targetIdsByObject.containsKey(definition.Target_Object__c)) {
                targetIdsByObject.put(definition.Target_Object__c, new Set<Id>());
            }
            targetIdsByObject.get(definition.Target_Object__c).addAll(targetIds);
        }
        return targetIdsByObject;
    }
}

/**
 * The system mode writes the rollup engine makes to package-owned data.
 *
 * DOCUMENTED EXCEPTION to the user mode DML rule (plan Section 4.13), on the same ground ADR-0021
 * records for settings and ADR-0015 records for the vendored engine's own writes. Three things are
 * written here and none of them is a user's data:
 *
 * 1. Rollup Definition records materialized from the package's own shipped defaults, which happens
 *    on install, where no permission set is assigned yet and a user mode insert fails for everyone.
 * 2. `Last_Calculated__c` on a definition, and the `Rollups_Last_Calculated__c` freshness stamp on
 *    a target record. A total that was calculated is a fact about the package's own run, not an
 *    edit the running user made, and a nightly batch runs as whoever scheduled it.
 * 3. Deactivating a definition the engine has refused, so a broken rollup stops rather than fails
 *    every save.
 *
 * Nothing an administrator types is written here: the values are datetimes this package computed
 * and values copied out of its own metadata. Permission is enforced before this class is reached,
 * by `RollupController`, for every path an administrator can start.
 */
public without sharing class RollupWriter {
    /** Inserts definitions materialized from the shipped defaults. */
    public static void insertDefinitions(List<Rollup_Definition__c> definitions) {
        if (definitions == null || definitions.isEmpty()) {
            return;
        }
        Database.insert(definitions, AccessLevel.SYSTEM_MODE);
    }

    /** Stamps `Last_Calculated__c` on the definitions a run has just completed. */
    public static void stampDefinitions(Map<Id, Datetime> completedAtById) {
        if (completedAtById == null || completedAtById.isEmpty()) {
            return;
        }
        List<Rollup_Definition__c> toStamp = new List<Rollup_Definition__c>();
        for (Id definitionId : completedAtById.keySet()) {
            toStamp.add(
                new Rollup_Definition__c(
                    Id = definitionId,
                    Last_Calculated__c = completedAtById.get(definitionId)
                )
            );
        }
        Database.update(toStamp, AccessLevel.SYSTEM_MODE);
    }

    /**
     * Stamps the one freshness attribute a target entity carries (canonical model Section 26).
     * The attribute is named rather than referenced, because Core drives rollups over objects it
     * holds no reference to (R-R7), and an entity that does not carry the attribute is skipped
     * rather than failing the run.
     */
    public static void stampTargets(String targetObject, Set<Id> targetIds, Datetime completedAt) {
        if (String.isBlank(targetObject) || targetIds == null || targetIds.isEmpty()) {
            return;
        }
        Schema.SObjectType targetType = SettingsService.typeByName(targetObject);
        if (targetType == null) {
            return;
        }
        Schema.SObjectField stamp = targetType.getDescribe(SObjectDescribeOptions.DEFERRED)
            .fields.getMap()
            .get(RollupService.FRESHNESS_FIELD);
        if (stamp == null || !stamp.getDescribe().isUpdateable()) {
            return;
        }
        List<SObject> toStamp = new List<SObject>();
        for (Id targetId : targetIds) {
            SObject target = targetType.newSObject(targetId);
            target.put(stamp, completedAt);
            toStamp.add(target);
        }
        Database.update(toStamp, false, AccessLevel.SYSTEM_MODE);
    }

    /** Turns a definition off after the engine has refused it. */
    public static void deactivate(Id definitionId) {
        if (definitionId == null) {
            return;
        }
        Database.update(
            new Rollup_Definition__c(Id = definitionId, Active__c = false),
            AccessLevel.SYSTEM_MODE
        );
    }

    /** Saves an administrator's edit to a definition, in user mode, where it belongs. */
    public static void saveAsUser(Rollup_Definition__c definition) {
        Database.upsert(definition, AccessLevel.USER_MODE);
    }
}

/**
 * Rewrites the name and greetings of every household the org has not taken over by hand.
 * Started from the settings page after a naming pattern changes. R-H14.
 */
public with sharing class HouseholdNamingBatch implements Database.Batchable<SObject>, Database.Stateful {
    public Integer householdsRead = 0;
    public Integer householdsChanged = 0;

    public Database.QueryLocator start(Database.BatchableContext context) {
        return HouseholdSelector.getHouseholdsForRecomputeLocator();
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        Set<Id> householdIds = new Map<Id, SObject>(scope).keySet();
        householdsRead += householdIds.size();
        householdsChanged += HouseholdNamingService.applyNaming(householdIds);
    }

    public void finish(Database.BatchableContext context) {
        // Counts stay on the job so that the settings page can report what happened.
        System.debug(
            LoggingLevel.INFO,
            'Household naming: ' + householdsRead + ' read, ' + householdsChanged + ' rewritten.'
        );
    }
}

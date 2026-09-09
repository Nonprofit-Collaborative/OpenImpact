/**
 * Record-level rules for `Volunteer_Job__c`.
 *
 * R-VJ1: a job that has shifts or hours against it is deactivated, not deleted, because deleting
 * it would take the record of work people actually did. This is the same rule as R-F2 for a fund,
 * and the message says what to do instead rather than leaving the platform to report a foreign
 * key.
 */
public with sharing class VolunteerJobTriggerHandler extends TriggerHandler {
    public override String getName() {
        return 'VolunteerJobTriggerHandler';
    }

    public override void beforeDelete() {
        List<Volunteer_Job__c> jobs = (List<Volunteer_Job__c>) oldRecords();
        if (jobs == null || jobs.isEmpty()) {
            return;
        }
        Set<Id> jobIds = new Map<Id, Volunteer_Job__c>(jobs).keySet();
        Map<Id, Integer> shiftCounts = VolunteerJobSelector.countShiftsByJobIds(jobIds);
        Map<Id, Integer> hoursCounts = VolunteerJobSelector.countHoursByJobIds(jobIds);
        for (Volunteer_Job__c job : jobs) {
            Integer shifts = shiftCounts.get(job.Id);
            Integer hours = hoursCounts.get(job.Id);
            if ((shifts != null && shifts > 0) || (hours != null && hours > 0)) {
                job.addError(Label.Volunteers_Job_InUseNotDeletable);
            }
        }
    }
}

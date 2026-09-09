/**
 * All SOQL against `Volunteer_Job__c`.
 */
public with sharing class VolunteerJobSelector {
    /**
     * The jobs with the given identifiers, with the attributes a handler or a screen needs.
     */
    public static List<Volunteer_Job__c> selectById(Set<Id> jobIds) {
        return [
            SELECT Id, Name, Active__c, Location__c, Coordinator__c
            FROM Volunteer_Job__c
            WHERE Id IN :jobIds
            WITH USER_MODE
        ];
    }

    /**
     * How many shifts each of these jobs has, so R-VJ1 can refuse a delete that would take the
     * schedule with it. A job with no shifts is absent from the map.
     */
    public static Map<Id, Integer> countShiftsByJobIds(Set<Id> jobIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (jobIds == null || jobIds.isEmpty()) {
            return counts;
        }
        for (AggregateResult row : [
            SELECT Volunteer_Job__c jobId, COUNT(Id) total
            FROM Volunteer_Shift__c
            WHERE Volunteer_Job__c IN :jobIds
            WITH USER_MODE
            GROUP BY Volunteer_Job__c
        ]) {
            counts.put((Id) row.get('jobId'), (Integer) row.get('total'));
        }
        return counts;
    }

    /**
     * How many hours entries each of these jobs carries, for the same rule. Hours survive their
     * shift being deleted (R-VG3), so they are counted separately rather than through the shift.
     */
    public static Map<Id, Integer> countHoursByJobIds(Set<Id> jobIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (jobIds == null || jobIds.isEmpty()) {
            return counts;
        }
        for (AggregateResult row : [
            SELECT Volunteer_Job__c jobId, COUNT(Id) total
            FROM Volunteer_Hours__c
            WHERE Volunteer_Job__c IN :jobIds
            WITH USER_MODE
            GROUP BY Volunteer_Job__c
        ]) {
            counts.put((Id) row.get('jobId'), (Integer) row.get('total'));
        }
        return counts;
    }
}

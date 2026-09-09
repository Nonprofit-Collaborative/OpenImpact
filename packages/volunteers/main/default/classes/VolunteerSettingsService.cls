/**
 * The two Volunteers settings, read once per transaction.
 *
 * Both are behavior switches an administrator sets in the Nonprofit Settings console (ADR-0017
 * gives each package its own protected hierarchy custom setting). They are read here rather than
 * in each handler so that a 200 record save asks the platform once, and so that a test can set
 * them without inserting a custom setting record.
 */
public with sharing class VolunteerSettingsService {
    /** Overrides for a test, so behavior can be driven without writing the org's settings. */
    @TestVisible
    private static Boolean hoursRequireApprovalOverride = null;
    @TestVisible
    private static Boolean attendanceCreatesHoursOverride = null;

    /**
     * R-VG6: whether an hours entry starts as Submitted and waits for a coordinator. An
     * organization that has turned approval off gets entries that are Approved as they are saved,
     * which is the same rule with the wait removed, not an exception to it.
     *
     * The default when nothing has been saved is true: approval on. A package that guessed the
     * other way would silently count hours nobody had checked.
     */
    public static Boolean hoursRequireApproval() {
        if (hoursRequireApprovalOverride != null) {
            return hoursRequireApprovalOverride;
        }
        Volunteer_Settings__c settings = Volunteer_Settings__c.getOrgDefaults();
        return settings == null || settings.Hours_Require_Approval__c == null
            ? true
            : settings.Hours_Require_Approval__c;
    }

    /**
     * R-VU3: whether marking a sign-up as Attended writes the hours for that shift. On by default,
     * because the shift already knows the date and the length, and typing them again is the work
     * V-02 exists to remove.
     */
    public static Boolean attendanceCreatesHours() {
        if (attendanceCreatesHoursOverride != null) {
            return attendanceCreatesHoursOverride;
        }
        Volunteer_Settings__c settings = Volunteer_Settings__c.getOrgDefaults();
        return settings == null || settings.Attendance_Creates_Hours__c == null
            ? true
            : settings.Attendance_Creates_Hours__c;
    }
}

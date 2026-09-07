/**
 * Queries about who can actually use Open Impact, for the access findings in Health Check
 * (plan Section 4.8). All SOQL for that question lives here (plan Section 7.1).
 *
 * Queries run in user mode: Health Check reports what the person running it can see, and the
 * admin guide says so.
 */
public with sharing class UserAccessSelector {
    /**
     * The ids of users holding any of the named packaged permission set groups.
     */
    public static Set<Id> getAssignedUserIds(Set<String> groupDeveloperNames) {
        Set<Id> assignees = new Set<Id>();
        if (groupDeveloperNames == null || groupDeveloperNames.isEmpty()) {
            return assignees;
        }

        for (PermissionSetAssignment assignment : [
            SELECT AssigneeId
            FROM PermissionSetAssignment
            WHERE PermissionSetGroup.DeveloperName IN :groupDeveloperNames
            WITH USER_MODE
        ]) {
            assignees.add(assignment.AssigneeId);
        }
        return assignees;
    }

    /**
     * How many active people hold any of the named packaged permission set groups.
     */
    public static Integer countActiveAssignees(Set<String> groupDeveloperNames) {
        if (groupDeveloperNames == null || groupDeveloperNames.isEmpty()) {
            return 0;
        }

        return [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE
                PermissionSetGroup.DeveloperName IN :groupDeveloperNames
                AND Assignee.IsActive = TRUE
            WITH USER_MODE
        ];
    }

    /**
     * How many active standard users hold none of the packaged roles. Counted rather than
     * listed: an org can have more users than a list would hold.
     */
    public static Integer countActiveStandardUsersExcluding(Set<Id> excludedUserIds) {
        Set<Id> excluded = excludedUserIds == null ? new Set<Id>() : excludedUserIds;

        return [
            SELECT COUNT()
            FROM User
            WHERE IsActive = TRUE AND UserType = 'Standard' AND Id NOT IN :excluded
            WITH USER_MODE
        ];
    }
}

/**
 * Reads permission set group assignments: who currently holds which role.
 */
public with sharing class PermissionSetAssignmentSelector {
    /**
     * Returns every active user's assignment to the given permission set groups.
     *
     * @param groupIds the permission set group Ids to report on
     * @return the assignments, ordered by the assignee's name
     */
    public List<PermissionSetAssignment> selectByGroupIds(Set<Id> groupIds) {
        if (groupIds == null || groupIds.isEmpty()) {
            return new List<PermissionSetAssignment>();
        }
        return [
            SELECT
                Id,
                AssigneeId,
                Assignee.Name,
                Assignee.Email,
                Assignee.IsActive,
                PermissionSetGroupId
            FROM PermissionSetAssignment
            WHERE PermissionSetGroupId IN :groupIds AND Assignee.IsActive = TRUE
            WITH USER_MODE
            ORDER BY Assignee.Name
        ];
    }

    /**
     * Returns the assignments that link any of the given users to any of the given groups.
     * Used to make assignment idempotent and to find the rows a removal deletes.
     *
     * @param groupIds the permission set group Ids to look in
     * @param userIds the users to look for
     * @return the matching assignments
     */
    public List<PermissionSetAssignment> selectByGroupIdsAndUserIds(
        Set<Id> groupIds,
        Set<Id> userIds
    ) {
        if (groupIds == null || groupIds.isEmpty() || userIds == null || userIds.isEmpty()) {
            return new List<PermissionSetAssignment>();
        }
        return [
            SELECT Id, AssigneeId, Assignee.Name, PermissionSetGroupId
            FROM PermissionSetAssignment
            WHERE PermissionSetGroupId IN :groupIds AND AssigneeId IN :userIds
            WITH USER_MODE
        ];
    }

    /**
     * Counts the active users assigned to one permission set group.
     * Used to stop the last Nonprofit Admin removing themselves.
     *
     * @param groupId the permission set group Id to count
     * @return how many active users hold the group
     */
    public Integer countActiveAssignees(Id groupId) {
        if (groupId == null) {
            return 0;
        }
        return [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE PermissionSetGroupId = :groupId AND Assignee.IsActive = TRUE
            WITH USER_MODE
        ];
    }
}

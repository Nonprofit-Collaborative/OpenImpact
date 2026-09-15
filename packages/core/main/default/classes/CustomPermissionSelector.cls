/**
 * Who holds a custom permission, asked for by name (feature C-11).
 *
 * ADR-0024 ships `Override_Receipt_Lock` assigned to nobody and expects an administrator to
 * grant it in Setup for one correction and take it away again. Health Check has to report a
 * standing assignment, and it has to name the people holding it, because "somebody has it"
 * is not something an administrator can act on.
 *
 * That permission lives in the Giving package and Health Check lives in Core, which must
 * still deploy and run on a Platform-only org (ADR-0009, ADR-0013). Nothing here compiles
 * against Giving: `CustomPermission`, `SetupEntityAccess`, `PermissionSet` and
 * `PermissionSetAssignment` are platform setup objects present in every Salesforce org, and
 * the permission is matched on `DeveloperName`, which is a String this class is handed. In an
 * org where Giving is not installed the first query simply returns no rows and the answer is
 * "nobody", which is the truth in that org. The name is deliberately not namespace qualified:
 * a packaged custom permission keeps its bare `DeveloperName` and carries the namespace in
 * `NamespaceName`, so qualifying it would find nothing once the namespace is registered.
 *
 * All SOQL for the question lives here (plan Section 7.1) and runs in user mode, like every
 * other Health Check query.
 */
public with sharing class CustomPermissionSelector {
    /** How many holders a finding names before it counts the rest. */
    public static final Integer NAMES_SHOWN = 3;

    /**
     * The most holders read back. An org that has handed this permission to more people than
     * this has a problem the first three names already describe.
     */
    private static final Integer HOLDER_LIMIT = 200;

    /** Injected by the tests, which cannot create a custom permission with DML. */
    @TestVisible
    private static Holders holdersOverride;

    /**
     * Who holds one custom permission. `readable` is false when the running user is not
     * allowed to see setup entities at all, which is not the same answer as "nobody holds
     * it" and is reported as no finding rather than as a clean bill of health.
     */
    public class Holders {
        public Boolean readable;
        public Integer total;
        public List<String> names;

        public Holders() {
            this.readable = true;
            this.total = 0;
            this.names = new List<String>();
        }
    }

    /**
     * The active users holding the named custom permission, through a permission set, a
     * permission set group, or the profile that owns one.
     */
    public static Holders holders(String developerName) {
        if (holdersOverride != null) {
            return holdersOverride;
        }

        Holders result = new Holders();
        if (String.isBlank(developerName)) {
            return result;
        }

        try {
            Set<Id> permissionIds = customPermissionIds(developerName);
            if (permissionIds.isEmpty()) {
                return result;
            }

            Set<Id> permissionSetIds = grantingPermissionSetIds(permissionIds);
            if (permissionSetIds.isEmpty()) {
                return result;
            }

            Set<Id> profileIds = owningProfileIds(permissionSetIds);
            Set<Id> assignedUserIds = assigneeIds(permissionSetIds);
            if (profileIds.isEmpty() && assignedUserIds.isEmpty()) {
                return result;
            }

            for (User holder : [
                SELECT Name
                FROM User
                WHERE IsActive = TRUE AND (Id IN :assignedUserIds OR ProfileId IN :profileIds)
                WITH USER_MODE
                ORDER BY Name
                LIMIT :HOLDER_LIMIT
            ]) {
                result.total++;
                if (result.names.size() < NAMES_SHOWN) {
                    result.names.add(holder.Name);
                }
            }
        } catch (QueryException cannotSeeSetup) {
            result.readable = false;
            result.total = 0;
            result.names = new List<String>();
        }

        return result;
    }

    /** The named custom permission, or nothing at all in an org without the package. */
    private static Set<Id> customPermissionIds(String developerName) {
        Set<Id> permissionIds = new Set<Id>();
        for (CustomPermission permission : [
            SELECT Id
            FROM CustomPermission
            WHERE DeveloperName = :developerName
            WITH USER_MODE
        ]) {
            permissionIds.add(permission.Id);
        }
        return permissionIds;
    }

    /**
     * The permission sets that grant the permission. A permission set group grants it through
     * its own aggregate permission set, which is what an assignment made from a group points
     * at, so both routes are covered by the assignment query below.
     */
    private static Set<Id> grantingPermissionSetIds(Set<Id> permissionIds) {
        Set<Id> permissionSetIds = new Set<Id>();
        for (SetupEntityAccess access : [
            SELECT ParentId
            FROM SetupEntityAccess
            WHERE SetupEntityId IN :permissionIds
            WITH USER_MODE
        ]) {
            permissionSetIds.add(access.ParentId);
        }
        return permissionSetIds;
    }

    /**
     * The profiles that grant it. A permission granted on a profile has no assignment row of
     * its own: everyone on that profile holds it, which is the widest way to leave this
     * permission lying around and the one worth reporting most.
     */
    private static Set<Id> owningProfileIds(Set<Id> permissionSetIds) {
        Set<Id> profileIds = new Set<Id>();
        for (PermissionSet owner : [
            SELECT ProfileId
            FROM PermissionSet
            WHERE Id IN :permissionSetIds AND IsOwnedByProfile = TRUE
            WITH USER_MODE
        ]) {
            if (owner.ProfileId != null) {
                profileIds.add(owner.ProfileId);
            }
        }
        return profileIds;
    }

    /** The people assigned one of the granting permission sets. */
    private static Set<Id> assigneeIds(Set<Id> permissionSetIds) {
        Set<Id> assignees = new Set<Id>();
        for (PermissionSetAssignment assignment : [
            SELECT AssigneeId
            FROM PermissionSetAssignment
            WHERE PermissionSetId IN :permissionSetIds
            WITH USER_MODE
        ]) {
            assignees.add(assignment.AssigneeId);
        }
        return assignees;
    }
}

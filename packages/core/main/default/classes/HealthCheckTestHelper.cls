/**
 * Test users for the Health Check and coexistence tests (features C-07 and C-11).
 *
 * Two people appear in these tests: Maria, the operations manager, who holds the Manage
 * Nonprofit Settings permission, and Priya, the program coordinator, who does not and who is
 * the reason the access checks are gated at all.
 *
 * The permission comes from the packaged custom permission, not from a copy of it, and its
 * absence fails loudly. A test that quietly does nothing because a dependency has not merged
 * yet is the one failure mode a test exists to prevent.
 */
@IsTest
public class HealthCheckTestHelper {
    /**
     * Maria: a user holding the Manage Nonprofit Settings custom permission.
     */
    public static User mariaWithManageSettings() {
        List<CustomPermission> permissions = [
            SELECT Id
            FROM CustomPermission
            WHERE DeveloperName = :HealthCheckService.MANAGE_SETTINGS
            LIMIT 1
        ];
        System.assert(
            !permissions.isEmpty(),
            'The Manage Nonprofit Settings custom permission is not in this org. It ships with ' +
            'the settings console (C-03), which has to merge before these tests mean anything.'
        );

        User maria = newUser('maria');
        String suffix = String.valueOf(System.now().getTime());
        PermissionSet grant = new PermissionSet(
            Name = 'Health_Check_Test_' + suffix,
            Label = 'Health Check test ' + suffix
        );

        System.runAs(currentUser()) {
            insert grant;
            insert new SetupEntityAccess(ParentId = grant.Id, SetupEntityId = permissions[0].Id);
            insert maria;
            insert new PermissionSetAssignment(AssigneeId = maria.Id, PermissionSetId = grant.Id);
        }
        return maria;
    }

    /**
     * Priya: an ordinary user with no packaged permission at all.
     */
    public static User priyaWithoutManageSettings() {
        User priya = newUser('priya');
        System.runAs(currentUser()) {
            insert priya;
        }
        return priya;
    }

    /**
     * The user running the test, used to keep setup object DML out of the same context as
     * ordinary record DML.
     */
    public static User currentUser() {
        return new User(Id = UserInfo.getUserId());
    }

    private static User newUser(String alias) {
        String unique =
            alias +
            '.' +
            String.valueOf(System.now().getTime()) +
            Crypto.getRandomInteger();
        return new User(
            Alias = alias.left(8),
            Email = alias + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            FirstName = alias.capitalize(),
            LastName = 'Nonprofit',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = UserInfo.getProfileId(),
            TimeZoneSidKey = 'America/New_York',
            Username = unique + '@example.invalid'
        );
    }
}

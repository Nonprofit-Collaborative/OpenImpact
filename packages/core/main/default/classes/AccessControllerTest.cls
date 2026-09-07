/**
 * Tests for AccessController: what the Access page gets back when Maria uses it, and
 * what David gets back when he opens it without the Manage Nonprofit Settings permission.
 */
@IsTest
private class AccessControllerTest {
    private static final String FUNDRAISING_ROLE = 'Fundraising_Staff';

    /**
     * Inserts one active user.
     *
     * @param firstName the person's first name
     * @param lastName the person's last name
     * @return the inserted user
     */
    private static User insertUser(String firstName, String lastName) {
        Profile standardProfile = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
        String suffix = String.valueOf(Math.abs(Crypto.getRandomLong()));
        User person = new User(
            FirstName = firstName,
            LastName = lastName,
            Alias = 'oi' + suffix.right(6),
            Email = firstName.toLowerCase() + '.' + suffix + '@example.invalid',
            Username = firstName.toLowerCase() + '.' + suffix + '@openimpact.test.invalid',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            IsActive = true
        );
        insert person;
        return person;
    }

    /**
     * Creates Maria: a person who holds the Nonprofit Admin role, and therefore the
     * Manage Nonprofit Settings custom permission that the Access page requires.
     *
     * @return the inserted user, already in the Nonprofit Admin role
     */
    private static User insertAdminUser() {
        Test.calculatePermissionSetGroup(AccessService.ADMIN_ROLE);
        User maria = insertUser('Maria', 'Alvarez');
        PermissionSetGroup adminGroup = [
            SELECT Id
            FROM PermissionSetGroup
            WHERE DeveloperName = :AccessService.ADMIN_ROLE
            LIMIT 1
        ];
        insert new PermissionSetAssignment(
            AssigneeId = maria.Id,
            PermissionSetGroupId = adminGroup.Id
        );
        return maria;
    }

    @IsTest
    static void getAccessOverviewTellsThePageWhoMayChangeRoles() {
        User david = insertUser('David', 'Okafor');
        AccessController.AccessResult result;

        Test.startTest();
        System.runAs(david) {
            result = AccessController.getAccessOverview();
        }
        Test.stopTest();

        Assert.isFalse(
            result.canManage,
            'David has no Manage Nonprofit Settings permission, so the page opens read only for him.'
        );
        Assert.isTrue(result.success, 'Opening the page read only is not an error.');
    }

    @IsTest
    static void getAccessOverviewReturnsTheRolesAndTheirMembers() {
        User maria = insertAdminUser();
        AccessController.AccessResult result;

        Test.startTest();
        System.runAs(maria) {
            result = AccessController.getAccessOverview();
        }
        Test.stopTest();

        Assert.isTrue(result.success, 'Maria should be able to open the Access page.');
        Assert.isTrue(
            result.canManage,
            'Maria holds the Nonprofit Admin role, so she may change roles.'
        );
        Assert.isNotNull(result.roles, 'The page needs the list of roles.');
        Assert.isNotNull(result.assignments, 'The page needs to know who holds each role.');
        Assert.areEqual(
            UserInfo.getUserId(),
            result.currentUserId,
            'The page needs to know who is looking at it.'
        );
    }

    @IsTest
    static void assignRoleIsRefusedWithoutThePermission() {
        User david = insertUser('David', 'Okafor');
        AccessController.AccessResult result;

        Test.startTest();
        System.runAs(david) {
            result = AccessController.assignRole(david.Id, FUNDRAISING_ROLE);
        }
        Test.stopTest();

        Assert.isFalse(result.success, 'David may not give himself a role.');
        Assert.areEqual(
            AccessController.ERROR_NO_PERMISSION,
            result.errorCode,
            'The page needs a code it can branch on, not only a message.'
        );
        Assert.areEqual(
            Label.Core_Access_ErrorNoPermission,
            result.message,
            'The message should name the permission that is missing.'
        );
    }

    @IsTest
    static void assignRoleRejectsSomethingThatIsNotAUserId() {
        User maria = insertAdminUser();
        AccessController.AccessResult result;

        Test.startTest();
        System.runAs(maria) {
            result = AccessController.assignRole('not an id', FUNDRAISING_ROLE);
        }
        Test.stopTest();

        Assert.isFalse(result.success, 'A value that is not a person should be refused.');
        Assert.areEqual(
            AccessController.ERROR_INVALID_INPUT,
            result.errorCode,
            'The refusal should say why.'
        );
    }

    @IsTest
    static void assignRoleRejectsAMissingRole() {
        User maria = insertAdminUser();
        AccessController.AccessResult result;

        Test.startTest();
        System.runAs(maria) {
            result = AccessController.assignRole(maria.Id, '');
        }
        Test.stopTest();

        Assert.isFalse(result.success, 'Choosing nobody and no role should be refused.');
        Assert.areEqual(
            AccessController.ERROR_INVALID_INPUT,
            result.errorCode,
            'The refusal should say why.'
        );
    }

    @IsTest
    static void assignRoleAndRemoveRoleWorkForMaria() {
        User maria = insertAdminUser();
        User david = insertUser('David', 'Okafor');
        Test.calculatePermissionSetGroup(FUNDRAISING_ROLE);
        AccessController.AccessResult assigned;
        AccessController.AccessResult removed;

        Test.startTest();
        System.runAs(maria) {
            assigned = AccessController.assignRole(david.Id, FUNDRAISING_ROLE);
            removed = AccessController.removeRole(david.Id, FUNDRAISING_ROLE);
        }
        Test.stopTest();

        Assert.isTrue(
            assigned.success,
            'Maria should be able to give David the Fundraising Staff role.'
        );
        Assert.isTrue(removed.success, 'Maria should be able to take the role away again.');
        Assert.areEqual(
            0,
            [
                SELECT COUNT()
                FROM PermissionSetAssignment
                WHERE
                    AssigneeId = :david.Id
                    AND PermissionSetGroup.DeveloperName = :FUNDRAISING_ROLE
            ],
            'David should not hold the role after Maria removes it.'
        );
    }

    @IsTest
    static void assignRoleReportsARoleThatIsNotPackaged() {
        User maria = insertAdminUser();
        AccessController.AccessResult result;

        Test.startTest();
        System.runAs(maria) {
            result = AccessController.assignRole(maria.Id, 'Some_Other_Group');
        }
        Test.stopTest();

        Assert.isFalse(result.success, 'A role Open Impact does not ship should be refused.');
        Assert.areEqual(
            AccessController.ERROR_FAILED,
            result.errorCode,
            'The page needs a code it can branch on.'
        );
        Assert.areEqual(
            Label.Core_Access_ErrorRoleNotFound,
            result.message,
            'The message should match the one in the admin guide.'
        );
    }

    @IsTest
    static void searchUsersReturnsMatchingPeople() {
        User maria = insertAdminUser();
        User david = insertUser('Davidcontroller', 'Okafor');
        AccessController.AccessResult result;

        Test.startTest();
        System.runAs(maria) {
            result = AccessController.searchUsers('Davidcontroller');
        }
        Test.stopTest();

        Assert.isTrue(result.success, 'Searching should not fail.');
        Set<Id> foundIds = new Set<Id>();
        for (AccessService.UserSummary summary : result.users) {
            foundIds.add(summary.userId);
        }
        Assert.isTrue(foundIds.contains(david.Id), 'Maria should find David in the search box.');
    }

    @IsTest
    static void searchUsersReturnsNothingForABlankTerm() {
        AccessController.AccessResult result;

        Test.startTest();
        result = AccessController.searchUsers(null);
        Test.stopTest();

        Assert.isTrue(result.success, 'An empty search box is not an error.');
        Assert.areEqual(
            0,
            result.users.size(),
            'An empty search box should not list the whole org.'
        );
    }
}

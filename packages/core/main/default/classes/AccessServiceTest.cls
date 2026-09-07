/**
 * Tests for AccessService: Maria giving David a role, giving it twice, taking it away,
 * finding people, a person who is not allowed to change roles, and fifty people at once.
 */
@IsTest
private class AccessServiceTest {
    private static final String FUNDRAISING_ROLE = 'Fundraising_Staff';

    /**
     * Builds an unassigned active user without inserting it.
     *
     * @param firstName the person's first name
     * @param lastName the person's last name
     * @param suffix a value that makes the username unique in the org
     * @return the user, ready to insert
     */
    private static User buildUser(String firstName, String lastName, String suffix) {
        Profile standardProfile = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
        return new User(
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
    }

    /**
     * Inserts one active user.
     *
     * @param firstName the person's first name
     * @param lastName the person's last name
     * @return the inserted user
     */
    private static User insertUser(String firstName, String lastName) {
        User person = buildUser(
            firstName,
            lastName,
            String.valueOf(Math.abs(Crypto.getRandomLong()))
        );
        insert person;
        return person;
    }

    /**
     * Counts how many rows link a person to a role.
     *
     * @param userId the person
     * @param roleDeveloperName the role's DeveloperName
     * @return the number of assignment rows
     */
    private static Integer countAssignments(Id userId, String roleDeveloperName) {
        return [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSetGroup.DeveloperName = :roleDeveloperName
        ];
    }

    @IsTest
    static void assignRoleGivesThePersonTheRole() {
        Test.calculatePermissionSetGroup(FUNDRAISING_ROLE);
        User david = insertUser('David', 'Okafor');

        Test.startTest();
        AccessService.assignRole(david.Id, FUNDRAISING_ROLE);
        Test.stopTest();

        Assert.areEqual(
            1,
            countAssignments(david.Id, FUNDRAISING_ROLE),
            'David should hold the Fundraising Staff role once Maria has given it to him.'
        );
    }

    @IsTest
    static void assignRoleTwiceChangesNothingTheSecondTime() {
        Test.calculatePermissionSetGroup(FUNDRAISING_ROLE);
        User david = insertUser('David', 'Okafor');
        AccessService.assignRole(david.Id, FUNDRAISING_ROLE);

        Test.startTest();
        AccessService.assignRole(david.Id, FUNDRAISING_ROLE);
        Test.stopTest();

        Assert.areEqual(
            1,
            countAssignments(david.Id, FUNDRAISING_ROLE),
            'Giving David a role he already holds should leave exactly one assignment.'
        );
    }

    @IsTest
    static void removeRoleTakesTheRoleAway() {
        Test.calculatePermissionSetGroup(FUNDRAISING_ROLE);
        User david = insertUser('David', 'Okafor');
        AccessService.assignRole(david.Id, FUNDRAISING_ROLE);

        Test.startTest();
        AccessService.removeRole(david.Id, FUNDRAISING_ROLE);
        Test.stopTest();

        Assert.areEqual(
            0,
            countAssignments(david.Id, FUNDRAISING_ROLE),
            'David should not hold the Fundraising Staff role after Maria removes it.'
        );
    }

    @IsTest
    static void removeRoleThePersonDoesNotHoldIsNotAnError() {
        Test.calculatePermissionSetGroup(FUNDRAISING_ROLE);
        User david = insertUser('David', 'Okafor');

        Test.startTest();
        AccessService.removeRole(david.Id, FUNDRAISING_ROLE);
        Test.stopTest();

        Assert.areEqual(
            0,
            countAssignments(david.Id, FUNDRAISING_ROLE),
            'Removing a role nobody holds should leave the org unchanged.'
        );
    }

    @IsTest
    static void searchUsersFindsAPersonByName() {
        User david = insertUser('Davidsearch', 'Okafor');

        Test.startTest();
        List<AccessService.UserSummary> found = AccessService.searchUsers('Davidsearch');
        Test.stopTest();

        Set<Id> foundIds = new Set<Id>();
        for (AccessService.UserSummary summary : found) {
            foundIds.add(summary.userId);
        }
        Assert.isTrue(
            foundIds.contains(david.Id),
            'Maria should find David by typing the start of his name.'
        );
    }

    @IsTest
    static void searchUsersReturnsNothingForABlankTerm() {
        Test.startTest();
        List<AccessService.UserSummary> found = AccessService.searchUsers('   ');
        Test.stopTest();

        Assert.areEqual(0, found.size(), 'An empty search box should not list the whole org.');
    }

    @IsTest
    static void assignRoleRejectsARoleThatIsNotOurs() {
        User david = insertUser('David', 'Okafor');
        String message;

        Test.startTest();
        try {
            AccessService.assignRole(david.Id, 'Some_Other_Group');
            Assert.fail('A role that Open Impact does not ship should be refused.');
        } catch (AccessService.AccessException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.areEqual(
            Label.Core_Access_ErrorRoleNotFound,
            message,
            'An unknown role should be reported in the words the admin guide uses.'
        );
    }

    @IsTest
    static void removeRoleRefusesToRemoveTheLastNonprofitAdmin() {
        Test.calculatePermissionSetGroup(AccessService.ADMIN_ROLE);
        User maria = insertUser('Maria', 'Alvarez');
        AccessService.assignRole(maria.Id, AccessService.ADMIN_ROLE);
        String message;

        Test.startTest();
        try {
            AccessService.removeRole(maria.Id, AccessService.ADMIN_ROLE);
            Assert.fail('Removing the only Nonprofit Admin should be refused.');
        } catch (AccessService.AccessException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.areEqual(
            Label.Core_Access_ErrorLastAdmin,
            message,
            'Maria should be told to give the role to someone else first.'
        );
        Assert.areEqual(
            1,
            countAssignments(maria.Id, AccessService.ADMIN_ROLE),
            'Maria should still hold the Nonprofit Admin role.'
        );
    }

    @IsTest
    static void getRolesReturnsThePackagedRoles() {
        Test.startTest();
        List<AccessService.Role> roles = AccessService.getRoles();
        Test.stopTest();

        Set<String> names = new Set<String>();
        for (AccessService.Role role : roles) {
            names.add(role.developerName);
            Assert.isNotNull(role.label, 'Every role needs a label the page can show.');
        }
        Assert.isTrue(
            names.contains(AccessService.ADMIN_ROLE),
            'The Nonprofit Admin role should be one of the packaged roles.'
        );
        Assert.isTrue(
            names.contains(FUNDRAISING_ROLE),
            'The Fundraising Staff role should be packaged.'
        );
    }

    @IsTest
    static void getAssignmentsListsThePeopleInEachRole() {
        Test.calculatePermissionSetGroup(FUNDRAISING_ROLE);
        User david = insertUser('David', 'Okafor');
        AccessService.assignRole(david.Id, FUNDRAISING_ROLE);

        Test.startTest();
        List<AccessService.RoleAssignments> assignments = AccessService.getAssignments();
        Test.stopTest();

        Boolean davidIsListed = false;
        for (AccessService.RoleAssignments entry : assignments) {
            if (FUNDRAISING_ROLE.equals(entry.roleDeveloperName)) {
                for (AccessService.UserSummary summary : entry.users) {
                    davidIsListed = davidIsListed || summary.userId == david.Id;
                }
            }
        }
        Assert.isTrue(
            davidIsListed,
            'David should appear under Fundraising Staff on the Access page.'
        );
    }

    @IsTest
    static void aPersonWithoutThePermissionCannotChangeRoles() {
        Test.calculatePermissionSetGroup(FUNDRAISING_ROLE);
        User david = insertUser('David', 'Okafor');
        User priya = insertUser('Priya', 'Nair');
        Boolean refused = false;

        Test.startTest();
        System.runAs(priya) {
            try {
                AccessService.assignRole(david.Id, FUNDRAISING_ROLE);
            } catch (AccessService.AccessException e) {
                refused = true;
            }
        }
        Test.stopTest();

        Assert.isTrue(
            refused,
            'A person without the Manage Nonprofit Settings permission should be refused.'
        );
        Assert.areEqual(
            0,
            countAssignments(david.Id, FUNDRAISING_ROLE),
            'A refused attempt should leave no assignment behind.'
        );
    }

    @IsTest
    static void fiftyPeopleCanBeGivenARoleInOneOperation() {
        Test.calculatePermissionSetGroup(FUNDRAISING_ROLE);
        List<User> staff = new List<User>();
        for (Integer i = 0; i < 50; i++) {
            staff.add(
                buildUser('Staff' + i, 'Bulk', String.valueOf(Math.abs(Crypto.getRandomLong())) + i)
            );
        }
        insert staff;
        Set<Id> staffIds = new Map<Id, User>(staff).keySet();

        Test.startTest();
        AccessService.assignRole(staffIds, FUNDRAISING_ROLE);
        Integer dmlAfter = Limits.getDmlStatements();
        Test.stopTest();

        Integer assigned = [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId IN :staffIds AND PermissionSetGroup.DeveloperName = :FUNDRAISING_ROLE
        ];
        Assert.areEqual(50, assigned, 'All fifty people should have been given the role.');
        Assert.isTrue(dmlAfter <= 2, 'Fifty assignments should cost one DML statement, not fifty.');
    }

    @IsTest
    static void fiftyPeopleCanHaveARoleTakenAwayInOneOperation() {
        Test.calculatePermissionSetGroup(FUNDRAISING_ROLE);
        List<User> staff = new List<User>();
        for (Integer i = 0; i < 50; i++) {
            staff.add(
                buildUser('Staff' + i, 'Bulk', String.valueOf(Math.abs(Crypto.getRandomLong())) + i)
            );
        }
        insert staff;
        Set<Id> staffIds = new Map<Id, User>(staff).keySet();
        AccessService.assignRole(staffIds, FUNDRAISING_ROLE);

        Test.startTest();
        AccessService.removeRole(staffIds, FUNDRAISING_ROLE);
        Test.stopTest();

        Integer assigned = [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId IN :staffIds AND PermissionSetGroup.DeveloperName = :FUNDRAISING_ROLE
        ];
        Assert.areEqual(0, assigned, 'All fifty assignments should have been removed.');
    }
}

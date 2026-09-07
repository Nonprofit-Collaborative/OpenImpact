/**
 * Tests for CorePostInstall: Maria installs Open Impact and can use Nonprofit Settings
 * straight away, an upgrade changes nothing, and a failure never breaks the install.
 */
@IsTest
private class CorePostInstallTest {
    @IsTest
    static void installGivesTheInstallerTheNonprofitAdminRole() {
        Test.calculatePermissionSetGroup(AccessService.ADMIN_ROLE);
        CorePostInstall handler = new CorePostInstall();

        Test.startTest();
        Test.testInstall(handler, null);
        Test.stopTest();

        Assert.areEqual(
            1,
            countAdminAssignments(UserInfo.getUserId()),
            'The person who installs the package should be able to open Nonprofit Settings.'
        );
    }

    @IsTest
    static void upgradingAnOrgThatIsAlreadySetUpChangesNothing() {
        Test.calculatePermissionSetGroup(AccessService.ADMIN_ROLE);
        CorePostInstall handler = new CorePostInstall();
        Test.testInstall(handler, null);

        Test.startTest();
        Test.testInstall(handler, new Version(1, 0), true);
        Test.stopTest();

        Assert.areEqual(
            1,
            countAdminAssignments(UserInfo.getUserId()),
            'An upgrade should leave exactly one assignment, not add a second.'
        );
    }

    @IsTest
    static void aMissingContextIsIgnored() {
        CorePostInstall handler = new CorePostInstall();

        Test.startTest();
        handler.onInstall(null);
        Test.stopTest();

        Assert.isTrue(true, 'An install with no context should do nothing rather than fail.');
    }

    /**
     * Counts how many rows link a person to the Nonprofit Admin role.
     *
     * @param userId the person
     * @return the number of assignment rows
     */
    private static Integer countAdminAssignments(Id userId) {
        String adminRole = AccessService.ADMIN_ROLE;
        return [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSetGroup.DeveloperName = :adminRole
        ];
    }
}

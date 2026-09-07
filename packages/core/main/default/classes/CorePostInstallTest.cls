/**
 * Tests for CorePostInstall and its retry job: Maria installs Open Impact and can use
 * Nonprofit Settings straight away, an upgrade changes nothing, the role follows when the
 * platform has finished preparing it, and nothing here ever breaks an install.
 */
@IsTest
private class CorePostInstallTest {
    @IsTest
    static void installAlwaysGivesTheInstallerTheAdminPermissionSet() {
        // The permission set is the step that must never depend on timing: it has no
        // calculation status, so it works the moment the install finishes.
        CorePostInstall handler = new CorePostInstall();

        Test.startTest();
        Test.testInstall(handler, null);
        Test.stopTest();

        Assert.areEqual(
            1,
            countPermissionSetAssignments(UserInfo.getUserId()),
            'The person who installs the package should hold the Nonprofit Admin permission set.'
        );
    }

    @IsTest
    static void installGivesTheInstallerTheRoleWhenItIsReady() {
        Test.calculatePermissionSetGroup(AccessService.ADMIN_ROLE);
        CorePostInstall handler = new CorePostInstall();

        Test.startTest();
        Test.testInstall(handler, null);
        Test.stopTest();

        Assert.areEqual(
            1,
            countRoleAssignments(UserInfo.getUserId()),
            'A prepared role should be given during the install itself.'
        );
        Assert.areEqual(
            0,
            countRetryJobs(),
            'Nothing needs to wait in the background when the role is already prepared.'
        );
    }

    @IsTest
    static void installQueuesARetryWhenTheRoleIsNotReadyYet() {
        // Test.calculatePermissionSetGroup is deliberately not called, so the group is in
        // the state a real org is in during the minutes after an install.
        CorePostInstall handler = new CorePostInstall();

        Test.startTest();
        Test.testInstall(handler, null);
        Test.stopTest();

        Assert.areEqual(
            1,
            countPermissionSetAssignments(UserInfo.getUserId()),
            'The installer is working regardless, because the permission set does not wait.'
        );
        Assert.areEqual(
            1,
            countRetryJobs(),
            'A role that is not prepared yet should be picked up by a background job.'
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
            countPermissionSetAssignments(UserInfo.getUserId()),
            'An upgrade should leave exactly one permission set assignment, not add a second.'
        );
        Assert.areEqual(
            1,
            countRoleAssignments(UserInfo.getUserId()),
            'An upgrade should leave exactly one role assignment, not add a second.'
        );
    }

    @IsTest
    static void aMissingContextChangesNothing() {
        Integer permissionSetsBefore = countPermissionSetAssignments(UserInfo.getUserId());
        Integer rolesBefore = countRoleAssignments(UserInfo.getUserId());
        CorePostInstall handler = new CorePostInstall();

        Test.startTest();
        handler.onInstall(null);
        Test.stopTest();

        Assert.areEqual(
            permissionSetsBefore,
            countPermissionSetAssignments(UserInfo.getUserId()),
            'An install with no context should assign no permission set.'
        );
        Assert.areEqual(
            rolesBefore,
            countRoleAssignments(UserInfo.getUserId()),
            'An install with no context should assign no role.'
        );
        Assert.areEqual(0, countRetryJobs(), 'An install with no context should queue nothing.');
    }

    @IsTest
    static void theRetryJobAssignsTheRoleOnceItIsPrepared() {
        Test.calculatePermissionSetGroup(AccessService.ADMIN_ROLE);

        Test.startTest();
        System.enqueueJob(new CorePostInstallRetryQueueable(UserInfo.getUserId()));
        Test.stopTest();

        Assert.areEqual(
            1,
            countRoleAssignments(UserInfo.getUserId()),
            'The background job should hand out the role once the platform has prepared it.'
        );
    }

    @IsTest
    static void theRetryJobGivesUpQuietlyOnItsLastAttempt() {
        // One attempt left and a role that is not prepared: the job records a warning and
        // stops rather than queueing for ever or throwing.
        CorePostInstallRetryQueueable job = new CorePostInstallRetryQueueable(
            UserInfo.getUserId(),
            1
        );

        Test.startTest();
        job.execute(null);
        Test.stopTest();

        Assert.areEqual(
            0,
            countRoleAssignments(UserInfo.getUserId()),
            'Giving up should leave the org as it was, with the permission set doing the work.'
        );
        Assert.areEqual(0, countRetryJobs(), 'The last attempt should not queue another.');
    }

    @IsTest
    static void theRetryJobIgnoresAMissingPerson() {
        CorePostInstallRetryQueueable job = new CorePostInstallRetryQueueable(null);

        Test.startTest();
        job.execute(null);
        Test.stopTest();

        Assert.areEqual(0, countRetryJobs(), 'With nobody to assign, the job should do nothing.');
    }

    /**
     * Counts how many rows link a person to the Nonprofit Admin permission set.
     *
     * @param userId the person
     * @return the number of assignment rows
     */
    private static Integer countPermissionSetAssignments(Id userId) {
        String permissionSetName = AccessService.ADMIN_PERMISSION_SET;
        return [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE
                AssigneeId = :userId
                AND PermissionSetGroupId = NULL
                AND PermissionSet.Name = :permissionSetName
        ];
    }

    /**
     * Counts how many rows link a person to the Nonprofit Admin role.
     *
     * @param userId the person
     * @return the number of assignment rows
     */
    private static Integer countRoleAssignments(Id userId) {
        String adminRole = AccessService.ADMIN_ROLE;
        return [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSetGroup.DeveloperName = :adminRole
        ];
    }

    /**
     * Counts the background jobs waiting for the role to be prepared.
     *
     * @return the number of queued retry jobs
     */
    private static Integer countRetryJobs() {
        return [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'Queueable' AND ApexClass.Name = 'CorePostInstallRetryQueueable'
        ];
    }
}

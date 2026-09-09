/**
 * Tests for CorePostInstall and its retry job: Maria installs Open Impact and can use
 * Nonprofit Settings straight away, the shipped rollups are in the org when she gets there,
 * an upgrade changes nothing, the role follows when the platform has finished preparing it,
 * and nothing here ever breaks an install.
 */
@IsTest
private class CorePostInstallTest {
    private static final String ROLLUP_CONTEXT = 'CorePostInstall.ensureRollupDefaults';
    private static final String RETRY_CONTEXT = 'CorePostInstallRetryQueueable.execute';

    /**
     * The Nonprofit Admin group as the platform leaves it in the minutes after an install:
     * present, but still being calculated, so it cannot be assigned yet.
     *
     * Built by deserializing rather than by construction because Status is written by the
     * platform and Apex cannot assign it, and because Test.calculatePermissionSetGroup only
     * ever moves a group forwards to Updated. There is no other way to prove what the install
     * does while it waits.
     *
     * @return a permission set group that is not ready to be assigned
     */
    private static PermissionSetGroup groupStillBeingCalculated() {
        return (PermissionSetGroup) JSON.deserialize(
            '{"attributes":{"type":"PermissionSetGroup"},"DeveloperName":"' +
                AccessService.ADMIN_ROLE +
                '","Status":"Updating"}',
            PermissionSetGroup.class
        );
    }

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
        TestDataFactory.prepareRoleGroup(AccessService.ADMIN_ROLE);
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
        // The state a real org is in during the minutes after an install: the packaged group
        // is there, but the platform is still calculating it and will refuse to assign it.
        // Leaving Test.calculatePermissionSetGroup uncalled does not produce that state, which
        // is what this test used to assume: in any org where the metadata is deployed the
        // group is already Updated, the install assigns the role outright, and nothing is
        // queued. The state has to be stated rather than hoped for.
        PermissionSetGroupSelector.systemModeOverride = groupStillBeingCalculated();
        CorePostInstall handler = new CorePostInstall();

        // The queued job runs at Test.stopTest, finds the group still not ready, and tries to
        // queue the next attempt. The platform does not allow a queueable to chain inside a
        // test, so that attempt fails and the job logs it, which is why this asserts on the
        // one job the install itself queued rather than on the whole chain.
        Test.startTest();
        Test.testInstall(handler, null);
        Test.stopTest();

        Assert.areEqual(
            1,
            countPermissionSetAssignments(UserInfo.getUserId()),
            'The installer is working regardless, because the permission set does not wait.'
        );
        Assert.areEqual(
            0,
            countRoleAssignments(UserInfo.getUserId()),
            'A role the platform is still calculating cannot be handed out during the install.'
        );
        Assert.areEqual(
            1,
            countRetryJobs(),
            'A role that is not prepared yet should be picked up by a background job.'
        );
    }

    @IsTest
    static void upgradingAnOrgThatIsAlreadySetUpChangesNothing() {
        TestDataFactory.prepareRoleGroup(AccessService.ADMIN_ROLE);
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
        TestDataFactory.prepareRoleGroup(AccessService.ADMIN_ROLE);

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
        // One attempt left and a role the platform is still calculating: the job records a
        // warning and stops rather than queueing for ever or throwing. The state is stated
        // rather than assumed, for the reason given in installQueuesARetryWhenTheRoleIsNotReadyYet.
        PermissionSetGroupSelector.systemModeOverride = groupStillBeingCalculated();
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
        List<Error_Log__c> logged = [
            SELECT Technical_Detail__c
            FROM Error_Log__c
            WHERE Context__c = :RETRY_CONTEXT
        ];
        Assert.areEqual(
            1,
            logged.size(),
            'Giving up quietly still means leaving Maria a note in the Error Log.'
        );
        Assert.isTrue(
            logged[0].Technical_Detail__c.contains('Nonprofit Admin role'),
            'The note names the role that was never handed out, so Maria knows what to finish.'
        );
    }

    @IsTest
    static void theRetryJobIgnoresAMissingPerson() {
        CorePostInstallRetryQueueable job = new CorePostInstallRetryQueueable(null);

        Test.startTest();
        job.execute(null);
        Test.stopTest();

        Assert.areEqual(0, countRetryJobs(), 'With nobody to assign, the job should do nothing.');
    }

    @IsTest
    static void installCreatesTheShippedRollupsSoTheTotalsAreNotBlank() {
        // The defect this covers: nothing called ensureDefaults, so a fresh org had no
        // Rollup Definition records at all and every giving total stayed empty (ADR-0029).
        RollupSelector.defaultsOverride = new List<Rollup_Definition_Default__mdt>{
            memberCountDefault()
        };
        CorePostInstall handler = new CorePostInstall();

        Test.startTest();
        Test.testInstall(handler, null);
        Test.stopTest();

        List<Rollup_Definition__c> created = [
            SELECT Definition_Key__c, Is_Package_Default__c, Active__c
            FROM Rollup_Definition__c
        ];
        Assert.areEqual(1, created.size(), 'The install creates the shipped rollup.');
        Assert.areEqual(
            'Core_Household_Member_Count',
            created[0].Definition_Key__c,
            'It is the shipped default, matched by its Definition Key.'
        );
        Assert.isTrue(
            created[0].Active__c,
            'It arrives switched on, so the total is calculated without a second step.'
        );
        Assert.isTrue(
            created[0].Is_Package_Default__c,
            'It is marked as shipped, so the Rollups page can tell it from an admin rollup.'
        );
    }

    @IsTest
    static void upgradingDoesNotCreateASecondCopyOrUndoAnEdit() {
        RollupSelector.defaultsOverride = new List<Rollup_Definition_Default__mdt>{
            memberCountDefault()
        };
        CorePostInstall handler = new CorePostInstall();
        Test.testInstall(handler, null);
        Rollup_Definition__c afterInstall = [
            SELECT Id, Active__c, Mode__c
            FROM Rollup_Definition__c
            LIMIT 1
        ];
        // Maria switches it off and changes its mode, which is what R-R6 protects.
        update new Rollup_Definition__c(
            Id = afterInstall.Id,
            Active__c = false,
            Mode__c = RollupService.MODE_SCHEDULED
        );

        Test.startTest();
        Test.testInstall(handler, new Version(1, 0), true);
        Test.stopTest();

        List<Rollup_Definition__c> afterUpgrade = [
            SELECT Id, Active__c, Mode__c
            FROM Rollup_Definition__c
        ];
        Assert.areEqual(1, afterUpgrade.size(), 'An upgrade adds no second copy of a rollup.');
        Assert.areEqual(
            afterInstall.Id,
            afterUpgrade[0].Id,
            'It is the same record, not a new one.'
        );
        Assert.isFalse(
            afterUpgrade[0].Active__c,
            'A rollup the admin switched off stays off across an upgrade (R-R6).'
        );
        Assert.areEqual(
            RollupService.MODE_SCHEDULED,
            afterUpgrade[0].Mode__c,
            'And the mode she chose is not reset to the shipped one.'
        );
    }

    @IsTest
    static void anOrgWithoutTheModuleGetsNoneOfItsRollups() {
        // Core installs before any module, so on a Core-only org a module's shipped rows name
        // objects the org does not have. That is the case this stands for: the source entity
        // named here is in no package, so the giving total must not be materialized.
        RollupSelector.defaultsOverride = new List<Rollup_Definition_Default__mdt>{
            new Rollup_Definition_Default__mdt(
                DeveloperName = 'Household_Total_Giving',
                MasterLabel = 'Household total giving',
                Definition_Key__c = 'Household_Total_Giving',
                Source_Object__c = 'A_Module_That_Is_Not_Installed__c',
                Target_Object__c = 'Account',
                Relationship_Path__c = 'Household__c',
                Aggregate__c = 'SUM',
                Source_Field__c = 'Amount__c',
                Target_Field__c = 'Total_Giving__c',
                Mode__c = RollupService.MODE_BOTH,
                Default_Active__c = true,
                Package__c = 'Giving'
            )
        };
        CorePostInstall handler = new CorePostInstall();

        Test.startTest();
        Test.testInstall(handler, null);
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Rollup_Definition__c],
            'A rollup over an object nobody has must not be created (R-R6).'
        );
        Assert.areEqual(
            1,
            countPermissionSetAssignments(UserInfo.getUserId()),
            'And skipping it leaves the rest of the install alone.'
        );
    }

    @IsTest
    static void aRollupThatCannotBeCreatedIsLoggedRatherThanFailingTheInstall() {
        // A shipped row whose label is longer than the Rollup Name attribute allows, which is
        // the shape of any bad packaged row: the insert throws where nobody can see it.
        Rollup_Definition_Default__mdt tooLong = memberCountDefault();
        tooLong.MasterLabel = 'x'.repeat(100);
        RollupSelector.defaultsOverride = new List<Rollup_Definition_Default__mdt>{ tooLong };
        CorePostInstall handler = new CorePostInstall();

        Test.startTest();
        // No try/catch here on purpose: an exception escaping this call fails the test, which
        // is the assertion that an install is never aborted by this step.
        Test.testInstall(handler, null);
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Rollup_Definition__c],
            'The bad row is not created.'
        );
        List<Error_Log__c> logged = [
            SELECT Context__c, Technical_Detail__c, Severity__c
            FROM Error_Log__c
            WHERE Context__c = :ROLLUP_CONTEXT
        ];
        Assert.areEqual(
            1,
            logged.size(),
            'The failure is in the Error Log where Maria can read it.'
        );
        Assert.areEqual(
            ErrorLogger.SEVERITY_ERROR,
            logged[0].Severity__c,
            'It is recorded as an error rather than as information.'
        );
        Assert.isTrue(
            logged[0].Technical_Detail__c.contains('DmlException'),
            'The technical detail names what the platform refused.'
        );
        Assert.areEqual(
            1,
            countPermissionSetAssignments(UserInfo.getUserId()),
            'And the rest of the install still ran, so the installer can open the console.'
        );
    }

    /**
     * The one shipped default these tests materialize: Core shaped, over objects Core has.
     *
     * @return an in-memory shipped default, since custom metadata cannot be inserted by a test
     */
    private static Rollup_Definition_Default__mdt memberCountDefault() {
        return new Rollup_Definition_Default__mdt(
            DeveloperName = 'Core_Household_Member_Count',
            MasterLabel = 'Household member count',
            Definition_Key__c = 'Core_Household_Member_Count',
            Source_Object__c = 'Household_Member__c',
            Target_Object__c = 'Account',
            Relationship_Path__c = 'Household__c',
            Aggregate__c = 'COUNT',
            Target_Field__c = 'Member_Count__c',
            Mode__c = RollupService.MODE_BOTH,
            Fiscal_Year_Aware__c = false,
            Default_Active__c = true,
            Package__c = 'Core'
        );
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

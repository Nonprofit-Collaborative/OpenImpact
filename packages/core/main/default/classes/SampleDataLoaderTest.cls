/**
 * Tests SampleDataLoader and the two load stages against a small inline JSON payload
 * injected through the @TestVisible jsonOverride hook, so the tests never depend on the
 * real SampleData static resource or its size.
 *
 * The stages are called directly (SampleDataLoadQueueable.loadHouseholdsAndOrganizations
 * and loadContactChunk) rather than through the queueable chain, because an Apex test
 * context runs only the first enqueued job. One test still enqueues the first queueable
 * inside Test.startTest and Test.stopTest and asserts stage one's effects only.
 */
@IsTest
private class SampleDataLoaderTest {
    /**
     * Builds a minimal but structurally faithful sample data JSON string: householdCount
     * households, each with membersPerHousehold members, plus one organization. When
     * customNameFirst is true the first household carries a custom name so both the
     * computed-name and custom-name insert paths are exercised across the suite.
     */
    private static String buildJson(
        Integer householdCount,
        Integer membersPerHousehold,
        Boolean customNameFirst
    ) {
        List<Object> households = new List<Object>();
        Integer emailIndex = 1;

        for (Integer h = 0; h < householdCount; h++) {
            Boolean isCustomName = customNameFirst && h == 0;
            List<Object> members = new List<Object>();
            for (Integer m = 0; m < membersPerHousehold; m++) {
                Map<String, Object> member = buildMember(h, m, emailIndex);
                if (h == 0 && m == membersPerHousehold - 1) {
                    member.put('deceased', true);
                }
                members.add(member);
                emailIndex++;
            }
            households.add(buildHousehold(h, isCustomName, members));
        }

        Map<String, Object> root = new Map<String, Object>();
        root.put('households', households);
        root.put('organizations', new List<Object>{ buildOrganization() });
        return JSON.serialize(root);
    }

    private static Map<String, Object> buildMember(
        Integer householdIndex,
        Integer memberIndex,
        Integer emailIndex
    ) {
        Map<String, Object> member = new Map<String, Object>();
        member.put('firstName', 'Test' + emailIndex);
        member.put('lastName', 'Household' + householdIndex);
        member.put('salutation', 'Mr.');
        member.put('householdRole', memberIndex == 0 ? 'Head' : 'Other');
        member.put('email', 'test' + emailIndex + '@example.org');
        member.put('phone', '(555) 555-0100');
        member.put('mailingStreet', '1 Test St');
        member.put('mailingCity', 'Testville');
        member.put('mailingState', 'CA');
        member.put('mailingPostalCode', '90000');
        member.put('birthdate', '1980-01-01');
        if (memberIndex == 0) {
            member.put('preferredName', 'Testy');
        }
        return member;
    }

    private static Map<String, Object> buildHousehold(
        Integer householdIndex,
        Boolean isCustomName,
        List<Object> members
    ) {
        Map<String, Object> address = new Map<String, Object>();
        address.put('street', '1 Test St');
        address.put('city', 'Testville');
        address.put('state', 'CA');
        address.put('postalCode', '90000');

        Map<String, Object> household = new Map<String, Object>();
        household.put('key', 'H' + householdIndex);
        household.put('customName', isCustomName);
        household.put('name', isCustomName ? 'The Test Family' : null);
        household.put('anniversary', isCustomName ? '2001-06-01' : null);
        household.put('address', address);
        household.put('members', members);
        return household;
    }

    private static Map<String, Object> buildOrganization() {
        Map<String, Object> organization = new Map<String, Object>();
        organization.put('key', 'O1');
        organization.put('name', 'Test Foundation');
        organization.put('website', 'https://www.example.org');
        organization.put('phone', '(555) 555-0199');
        return organization;
    }

    /** Runs both stages in order, the way the queueable chain does in an org. */
    private static SampleDataSet loadEverything(String jsonBody) {
        SampleDataSet data = SampleDataSet.parse(jsonBody);
        SampleDataLoadQueueable.loadHouseholdsAndOrganizations(data);
        for (Integer chunk = 0; chunk < data.chunkCount(); chunk++) {
            SampleDataLoadQueueable.loadContactChunk(data, chunk);
        }
        return data;
    }

    @IsTest
    static void testStagesInsertHouseholdsOrganizationsAndContacts() {
        loadEverything(buildJson(3, 2, true));

        SampleDataLoader.Counts status = SampleDataLoader.status();
        System.assertEquals(3, status.householdCount, 'three households should be inserted');
        System.assertEquals(1, status.organizationCount, 'one organization should be inserted');
        System.assertEquals(6, status.contactCount, 'three households of two members each');
        System.assertEquals(
            true,
            status.loaded,
            'status should report loaded once both stages run'
        );
        System.assertEquals(false, status.loading, 'no load job should still be queued');
    }

    @IsTest
    static void testFirstQueueableRunsTheHouseholdStage() {
        // The only chaining-dependent assertion the platform allows: a test context runs
        // the first enqueued job and nothing it enqueues, so only stage one's effects
        // exist afterwards.
        SampleDataLoader.jsonOverride = buildJson(2, 2, false);

        Test.startTest();
        SampleDataLoader.load();
        Test.stopTest();

        SampleDataLoader.Counts status = SampleDataLoader.status();
        System.assertEquals(2, status.householdCount, 'stage one should insert the households');
        System.assertEquals(
            1,
            status.organizationCount,
            'stage one should insert the organization'
        );
        System.assertEquals(
            0,
            status.contactCount,
            'the contact stage is a second queueable, which a test context does not run'
        );
    }

    @IsTest
    static void testContactChunksAtOneHundred() {
        // Five households of fifty members each: 250 contacts, three chunks of 100, 100
        // and 50, matching the governor-limit rule in plan Section 7.2.
        SampleDataSet data = SampleDataSet.parse(buildJson(5, 50, false));
        System.assertEquals(250, data.members.size(), 'the payload should hold 250 members');
        System.assertEquals(3, data.chunkCount(), '250 contacts should need three chunks');

        SampleDataLoadQueueable.loadHouseholdsAndOrganizations(data);

        System.assertEquals(
            100,
            SampleDataLoadQueueable.loadContactChunk(data, 0),
            'the first chunk should insert a full 100 contacts'
        );
        System.assertEquals(
            100,
            SampleDataLoadQueueable.loadContactChunk(data, 1),
            'the second chunk should insert a full 100 contacts'
        );
        System.assertEquals(
            50,
            SampleDataLoadQueueable.loadContactChunk(data, 2),
            'the last chunk should insert the remaining 50 contacts'
        );
        System.assertEquals(
            0,
            SampleDataLoadQueueable.loadContactChunk(data, 3),
            'a chunk past the end should insert nothing'
        );

        SampleDataLoader.Counts status = SampleDataLoader.status();
        System.assertEquals(5, status.householdCount);
        System.assertEquals(250, status.contactCount, 'all 250 contacts should be inserted');
        System.assertEquals(true, status.loaded);
    }

    @IsTest
    static void testLoadThrowsWhenAlreadyLoaded() {
        loadEverything(buildJson(1, 1, false));
        SampleDataLoader.jsonOverride = buildJson(1, 1, false);

        Boolean threw = false;
        try {
            SampleDataLoader.load();
        } catch (SampleDataException e) {
            threw = true;
            System.assertEquals(
                Label.Core_SampleData_AlreadyLoaded,
                e.getMessage(),
                'the already-loaded error should use the packaged label'
            );
        }
        System.assertEquals(true, threw, 'loading twice should throw SampleDataException');
    }

    @IsTest
    static void testLoadRefusesWhenHouseholdMembershipIsJunction() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
        SettingsService.clearCaches();
        SampleDataLoader.jsonOverride = buildJson(1, 1, false);

        Boolean threw = false;
        try {
            SampleDataLoader.load();
        } catch (SampleDataException e) {
            threw = true;
            System.assertEquals(
                Label.Core_SampleData_ContactModeOnly,
                e.getMessage(),
                'a junction membership org should be told why sample data cannot load'
            );
        }
        System.assertEquals(true, threw, 'loading in junction mode should throw');
        System.assertEquals(
            false,
            SampleDataLoader.status().contactMembership,
            'the card is told the org keeps membership in junction records'
        );
    }

    @IsTest
    static void testLoadRefusesWhileALoadIsRunning() {
        SampleDataLoader.jsonOverride = buildJson(1, 1, false);
        SampleDataLoader.runningJobOverride = true;

        Boolean threw = false;
        try {
            SampleDataLoader.load();
        } catch (SampleDataException e) {
            threw = true;
            System.assertEquals(
                Label.Core_SampleData_LoadInProgress,
                e.getMessage(),
                'a second load should be refused with the load-in-progress label'
            );
        }
        System.assertEquals(true, threw, 'loading during a running load should throw');
    }

    @IsTest
    static void testRemoveRefusesWhileALoadIsRunning() {
        loadEverything(buildJson(1, 1, false));
        SampleDataLoader.runningJobOverride = true;

        Boolean threw = false;
        try {
            SampleDataLoader.remove();
        } catch (SampleDataException e) {
            threw = true;
            System.assertEquals(
                Label.Core_SampleData_LoadInProgress,
                e.getMessage(),
                'removing during a load should be refused with the load-in-progress label'
            );
        }
        System.assertEquals(true, threw, 'removing during a running load should throw');

        SampleDataLoader.runningJobOverride = false;
        SampleDataLoader.Counts status = SampleDataLoader.status();
        System.assertEquals(1, status.householdCount, 'the refused remove should delete nothing');
    }

    @IsTest
    static void testStatusReportsLoadingWhileAJobRuns() {
        loadEverything(buildJson(1, 1, false));
        SampleDataLoader.runningJobOverride = true;

        SampleDataLoader.Counts status = SampleDataLoader.status();
        System.assertEquals(true, status.loading, 'status should report a running load');
        System.assertEquals(false, status.loaded, 'a running load is not a finished load');
    }

    @IsTest
    static void testRemoveDeletesEverythingFlagged() {
        loadEverything(buildJson(2, 2, false));

        SampleDataLoader.Counts removed = SampleDataLoader.remove();
        System.assertEquals(2, removed.householdCount);
        System.assertEquals(1, removed.organizationCount);
        System.assertEquals(4, removed.contactCount);

        SampleDataLoader.Counts afterStatus = SampleDataLoader.status();
        System.assertEquals(
            0,
            afterStatus.householdCount,
            'households should be gone after remove'
        );
        System.assertEquals(
            0,
            afterStatus.organizationCount,
            'organizations should be gone after remove'
        );
        System.assertEquals(0, afterStatus.contactCount, 'contacts should be gone after remove');
        System.assertEquals(false, afterStatus.loaded);
    }

    @IsTest
    static void testRemoveLeavesRecordsTheLoaderDidNotCreate() {
        loadEverything(buildJson(1, 1, false));
        Account ownRecord = new Account(Name = 'A real household');
        insert ownRecord;

        SampleDataLoader.remove();

        List<Account> remaining = [SELECT Id FROM Account WHERE Id = :ownRecord.Id];
        System.assertEquals(1, remaining.size(), 'records the admin entered are not touched');
    }

    @IsTest
    static void testStatusReportsNotLoadedBeforeAnyLoad() {
        SampleDataLoader.Counts status = SampleDataLoader.status();
        System.assertEquals(0, status.householdCount);
        System.assertEquals(0, status.organizationCount);
        System.assertEquals(0, status.contactCount);
        System.assertEquals(false, status.loaded);
        System.assertEquals(false, status.loading);
    }
}

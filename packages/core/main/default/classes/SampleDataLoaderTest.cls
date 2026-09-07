/**
 * Tests SampleDataLoader against a small inline JSON payload injected through the
 * @TestVisible jsonOverride hook, so the test never depends on the real
 * SampleData static resource or its size.
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

    @IsTest
    static void testLoadInsertsHouseholdsOrganizationsAndContacts() {
        SampleDataLoader.jsonOverride = buildJson(3, 2, true);

        Test.startTest();
        SampleDataLoader.load();
        Test.stopTest();

        SampleDataLoader.Counts status = SampleDataLoader.status();
        System.assertEquals(3, status.householdCount, 'three households should be inserted');
        System.assertEquals(1, status.organizationCount, 'one organization should be inserted');
        System.assertEquals(6, status.contactCount, 'three households of two members each');
        System.assertEquals(
            true,
            status.loaded,
            'status should report loaded once the chain finishes'
        );
        System.assertEquals(false, status.loading, 'no load job should still be queued');
    }

    @IsTest
    static void testLoadThrowsWhenAlreadyLoaded() {
        SampleDataLoader.jsonOverride = buildJson(1, 1, false);

        Test.startTest();
        SampleDataLoader.load();
        Test.stopTest();

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
    static void testRemoveDeletesEverythingFlagged() {
        SampleDataLoader.jsonOverride = buildJson(2, 2, false);

        Test.startTest();
        SampleDataLoader.load();
        Test.stopTest();

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
    static void testStatusReportsNotLoadedBeforeAnyLoad() {
        SampleDataLoader.Counts status = SampleDataLoader.status();
        System.assertEquals(0, status.householdCount);
        System.assertEquals(0, status.organizationCount);
        System.assertEquals(0, status.contactCount);
        System.assertEquals(false, status.loaded);
        System.assertEquals(false, status.loading);
    }

    @IsTest
    static void testLoadChunksTwoHundredFiftyContacts() {
        // Five households of fifty members each: 250 contacts total, exercising three
        // SampleDataLoadQueueable contact chunks (100, 100, 50) after the household and
        // organization stage.
        SampleDataLoader.jsonOverride = buildJson(5, 50, false);

        Test.startTest();
        SampleDataLoader.load();
        Test.stopTest();

        SampleDataLoader.Counts status = SampleDataLoader.status();
        System.assertEquals(5, status.householdCount);
        System.assertEquals(
            250,
            status.contactCount,
            'all 250 contacts should insert across three chunks'
        );
        System.assertEquals(true, status.loaded);
    }
}

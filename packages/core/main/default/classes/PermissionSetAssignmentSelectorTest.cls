/**
 * Tests for PermissionSetAssignmentSelector: who holds a role, and how many people do.
 */
@IsTest
private class PermissionSetAssignmentSelectorTest {
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

    @IsTest
    static void selectByGroupIdsListsThePeopleInTheRole() {
        Test.calculatePermissionSetGroup(FUNDRAISING_ROLE);
        User david = insertUser('David', 'Okafor');
        PermissionSetGroup groupRecord = [
            SELECT Id
            FROM PermissionSetGroup
            WHERE DeveloperName = :FUNDRAISING_ROLE
            LIMIT 1
        ];
        insert new PermissionSetAssignment(
            AssigneeId = david.Id,
            PermissionSetGroupId = groupRecord.Id
        );
        PermissionSetAssignmentSelector selector = new PermissionSetAssignmentSelector();

        Test.startTest();
        List<PermissionSetAssignment> assignments = selector.selectByGroupIds(
            new Set<Id>{ groupRecord.Id }
        );
        Test.stopTest();

        Set<Id> assignees = new Set<Id>();
        for (PermissionSetAssignment assignment : assignments) {
            assignees.add(assignment.AssigneeId);
        }
        Assert.isTrue(
            assignees.contains(david.Id),
            'David should be listed under the role he holds.'
        );
    }

    @IsTest
    static void selectByGroupIdsAndUserIdsFindsAnExistingAssignment() {
        Test.calculatePermissionSetGroup(FUNDRAISING_ROLE);
        User david = insertUser('David', 'Okafor');
        PermissionSetGroup groupRecord = [
            SELECT Id
            FROM PermissionSetGroup
            WHERE DeveloperName = :FUNDRAISING_ROLE
            LIMIT 1
        ];
        insert new PermissionSetAssignment(
            AssigneeId = david.Id,
            PermissionSetGroupId = groupRecord.Id
        );
        PermissionSetAssignmentSelector selector = new PermissionSetAssignmentSelector();

        Test.startTest();
        List<PermissionSetAssignment> found = selector.selectByGroupIdsAndUserIds(
            new Set<Id>{ groupRecord.Id },
            new Set<Id>{ david.Id }
        );
        Integer count = selector.countActiveAssignees(groupRecord.Id);
        Test.stopTest();

        Assert.areEqual(
            1,
            found.size(),
            'The one assignment linking David to the role should be found.'
        );
        Assert.areEqual(1, count, 'One active person holds the role.');
    }

    @IsTest
    static void emptyInputQueriesNothing() {
        PermissionSetAssignmentSelector selector = new PermissionSetAssignmentSelector();

        Test.startTest();
        List<PermissionSetAssignment> byGroup = selector.selectByGroupIds(new Set<Id>());
        List<PermissionSetAssignment> byBoth = selector.selectByGroupIdsAndUserIds(
            new Set<Id>(),
            new Set<Id>()
        );
        Integer count = selector.countActiveAssignees(null);
        Test.stopTest();

        Assert.areEqual(0, byGroup.size(), 'Asking about no groups should return nothing.');
        Assert.areEqual(
            0,
            byBoth.size(),
            'Asking about no groups and no people should return nothing.'
        );
        Assert.areEqual(0, count, 'Counting nobody should return zero without querying.');
    }
}

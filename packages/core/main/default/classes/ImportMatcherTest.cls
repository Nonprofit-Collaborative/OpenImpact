/**
 * Matching: each rule finds what it should, is bulk (one query per key set), and answers
 * "nothing" rather than throwing where the org cannot support the rule.
 */
@IsTest
private class ImportMatcherTest {
    @TestSetup
    static void setUp() {
        TestDataFactory.defaultSettings();
        insert new List<Contact>{
            new Contact(
                FirstName = 'Ana',
                LastName = 'Ramirez',
                Email = 'ana@example.org',
                MailingPostalCode = '97201'
            ),
            new Contact(
                FirstName = 'Ben',
                LastName = 'Okafor',
                Email = 'ben@example.org',
                MailingPostalCode = '97202'
            )
        };
    }

    @IsTest
    static void findsContactsByEmailIgnoringCase() {
        Test.startTest();
        Map<String, Id> found = ImportMatcher.contactsByEmail(
            new Set<String>{ 'ana@example.org', 'BEN@EXAMPLE.ORG', 'nobody@example.org' }
        );
        Test.stopTest();
        Assert.areEqual(2, found.size(), 'Both known emails match and the unknown one does not.');
        Assert.isNotNull(found.get('ana@example.org'), 'Keyed by the email folded to lower case.');
    }

    @IsTest
    static void findsContactsByLastNameAndPostalCode() {
        Test.startTest();
        Map<String, Id> found = ImportMatcher.contactsByNameAndPostalCode(
            new Set<String>{
                ImportMatcher.nameAndPostalKey('Ramirez', '97201'),
                ImportMatcher.nameAndPostalKey('Ramirez', '99999')
            }
        );
        Test.stopTest();
        Assert.areEqual(1, found.size(), 'Only the name at the right postal code matches.');
    }

    @IsTest
    static void oneQueryPerKeySetNoMatterHowManyKeys() {
        Set<String> emails = new Set<String>();
        for (Integer i = 0; i < 300; i++) {
            emails.add('person' + i + '@example.org');
        }
        Test.startTest();
        ImportMatcher.contactsByEmail(emails);
        Assert.areEqual(
            1,
            Limits.getQueries(),
            'Three hundred keys are one query, not three hundred: the matcher is bulk.'
        );
        Test.stopTest();
    }

    @IsTest
    static void aCompositeKeyNeedsBothOfItsParts() {
        Assert.isNull(
            ImportMatcher.nameAndPostalKey('Ramirez', null),
            'A row with no postal code cannot be matched on name plus postal code.'
        );
        Assert.isNull(ImportMatcher.nameAndPostalKey(null, '97201'), 'Nor one with no name.');
        Assert.isNotNull(ImportMatcher.nameAndPostalKey('Ramirez', '97201'), 'Both parts, a key.');
    }

    @IsTest
    static void matchesOrganizationsByNameWithinTheirRecordType() {
        Id organizationRecordType = Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
            .getRecordTypeInfosByDeveloperName()
            .get('Organization')
            .getRecordTypeId();
        insert new Account(Name = 'Rose City Foundation', RecordTypeId = organizationRecordType);

        Test.startTest();
        Map<String, Id> found = ImportMatcher.accountsByName(
            new Set<String>{ 'rose city foundation' },
            organizationRecordType
        );
        Test.stopTest();
        Assert.areEqual(1, found.size(), 'The organization is found by its name, ignoring case.');
    }

    @IsTest
    static void personAccountMatchingIsEmptyOnAnOrgWithoutThem() {
        Test.startTest();
        Map<String, Id> found = ImportMatcher.personAccountsByEmail(
            new Set<String>{ 'ana@example.org' },
            new Set<Id>()
        );
        Test.stopTest();
        Assert.isTrue(
            found.isEmpty(),
            'A platform-only org answers "nothing matched" rather than failing to compile.'
        );
    }

    @IsTest
    static void anEmptyKeySetQueriesNothing() {
        Test.startTest();
        Map<String, Id> found = ImportMatcher.contactsByEmail(new Set<String>());
        Assert.areEqual(0, Limits.getQueries(), 'Nothing to look up, nothing queried.');
        Test.stopTest();
        Assert.isTrue(found.isEmpty(), 'And nothing found.');
    }

    @IsTest
    static void blankKeysAreDroppedBeforeTheQuery() {
        Test.startTest();
        Map<String, Id> found = ImportMatcher.contactsByEmail(
            new Set<String>{ null, '', '   ', 'ana@example.org' }
        );
        Test.stopTest();
        Assert.areEqual(1, found.size(), 'Only the real key was looked up.');
    }
}

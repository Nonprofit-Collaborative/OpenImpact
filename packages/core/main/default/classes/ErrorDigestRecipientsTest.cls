/**
 * Who receives the error digest (C-23, R-E5): active users of this org only, the
 * administrators unless somebody is listed, and a listed address that is not a user's is refused
 * when the setting is saved.
 */
@IsTest
private class ErrorDigestRecipientsTest {
    private static User maria() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'Nonprofit_Admin' });
    }

    private static Nonprofit_Settings__c settings() {
        return Nonprofit_Settings__c.getOrgDefaults();
    }

    @IsTest
    static void theDefaultRecipientsAreTheAdministrators() {
        TestDataFactory.defaultSettings();
        User admin = maria();
        User staff = TestDataFactory.createUser('David', new List<String>{ 'Nonprofit_Staff' });

        List<User> recipients;
        System.runAs(admin) {
            Test.startTest();
            recipients = ErrorDigestRecipients.resolve(null);
            Test.stopTest();
        }

        Set<Id> ids = new Map<Id, User>(recipients).keySet();
        Assert.isTrue(ids.contains(admin.Id), 'Maria holds Manage Nonprofit Settings.');
        Assert.isFalse(ids.contains(staff.Id), 'David does not.');
    }

    @IsTest
    static void anAddressThatIsNotAUserIsRefusedWhenSaved() {
        TestDataFactory.defaultSettings();
        TestDataFactory.createUser('Jen', new List<String>{ 'Nonprofit_Staff' });
        User admin = maria();

        System.runAs(admin) {
            Test.startTest();
            try {
                SettingsService.saveValues(
                    new Map<String, Object>{
                        'Error_Digest_Recipients__c' => 'Jen@openimpact.example.invalid, donor@example.com'
                    }
                );
                Assert.fail('An address outside the org must be refused.');
            } catch (SettingsService.SettingsException expected) {
                Assert.isTrue(
                    expected.getMessage().contains('donor@example.com'),
                    'The refusal names the address.'
                );
                Assert.isFalse(
                    expected.getMessage().contains('jen@'),
                    'And only the address that is wrong.'
                );
            }
            SettingsService.saveValues(
                new Map<String, Object>{
                    'Error_Digest_Recipients__c' => 'Jen@openimpact.example.invalid'
                }
            );
            Test.stopTest();
        }

        Assert.areEqual(
            'Jen@openimpact.example.invalid',
            settings().Error_Digest_Recipients__c,
            'A user of the org is accepted.'
        );
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Setting_Change__c],
            'And audited once; the refused save wrote nothing.'
        );
    }

    @IsTest
    static void listedUsersAreFoundByEmailInTheOrderListed() {
        User jen = TestDataFactory.createUser('Jen', new List<String>{ 'Nonprofit_Staff' });
        User admin = maria();

        List<User> recipients;
        System.runAs(admin) {
            Test.startTest();
            recipients = ErrorDigestRecipients.resolve(
                'JEN@openimpact.example.invalid; Maria@openimpact.example.invalid'
            );
            Test.stopTest();
        }

        Assert.areEqual(2, recipients.size(), 'Both addresses belong to users.');
        Assert.areEqual(jen.Id, recipients[0].Id, 'Found whatever the case of the address.');
        Assert.areEqual(admin.Id, recipients[1].Id, 'And in the order listed.');
    }

    @IsTest
    static void anInactiveUserIsNotARecipient() {
        User gone = TestDataFactory.createUser('Former', new List<String>{ 'Nonprofit_Staff' });
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = gone.Id, IsActive = false);
        }

        Test.startTest();
        String refusal = ErrorDigestRecipients.refusal('Former@openimpact.example.invalid');
        Test.stopTest();

        Assert.isNotNull(refusal, 'A deactivated user cannot receive the digest.');
    }
}

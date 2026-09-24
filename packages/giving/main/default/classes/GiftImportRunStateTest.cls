/**
 * What a gift import run carries from chunk to chunk (R-DM1, R-DM4): a repeat of an external
 * ID loaded by an earlier chunk is Matched, in the dry run as in the commit, and under Never
 * match too.
 */
@IsTest
private class GiftImportRunStateTest {
    private static User maria() {
        return TestDataFactory.createUser(
            'Maria',
            new List<String>{ 'Nonprofit_Admin', 'Giving_Admin' }
        );
    }

    /** Runs each row as a chunk of its own, the state carried between them as the batch does. */
    private static List<Import_Row__c> runInChunks(
        Import_Batch__c batch,
        Import_Template__c template,
        Boolean dryRun
    ) {
        ImportEntityProcessors.carriedState = null;
        for (Import_Row__c row : ImportTestDataFactory.reload(batch.Id)) {
            ImportRowProcessor.process(
                batch,
                template,
                ImportMapping.parse(template.Column_Mapping_JSON__c),
                new List<Import_Row__c>{ row },
                dryRun
            );
        }
        return [
            SELECT Status__c, Error_Message__c
            FROM Import_Row__c
            WHERE Import_Batch__c = :batch.Id
            ORDER BY Row_Number__c
        ];
    }

    @IsTest
    static void aRepeatInALaterChunkIsMatchedInTheDryRunAsInTheCommit() {
        TestDataFactory.defaultSettings();
        insert new Fund__c(Name = 'General', Active__c = true, Is_Default__c = true);
        // Ana is already here, so each row's status is its gift's: a dry run cannot know that an
        // earlier chunk would create a person either.
        insert new Contact(LastName = 'Ramirez', Email = 'ana@example.org');
        ImportMapping mapping = new ImportMapping();
        for (
            String target : new List<String>{
                'Contact1.Email',
                'Contact1.LastName',
                'Gift.Amount__c',
                'Gift.Gift_Date__c',
                'Gift.Type__c',
                'Gift.External_Id__c'
            }
        ) {
            mapping.columns.add(new ImportMapping.Column(target, target));
        }
        Import_Template__c template = ImportTestDataFactory.template(
            mapping.serialize(),
            ImportTemplateService.RULE_EMAIL
        );
        template.Donation_Matching__c = DonationMatcher.NEVER_MATCH;
        update template;
        Import_Batch__c batch = ImportTestDataFactory.batch(template);
        List<Map<String, String>> rows = new List<Map<String, String>>();
        for (String externalId : new List<String>{ 'order-1', 'ORDER-1' }) {
            rows.add(
                new Map<String, String>{
                    'Contact1.Email' => 'ana@example.org',
                    'Contact1.LastName' => 'Ramirez',
                    'Gift.Amount__c' => '25',
                    'Gift.Gift_Date__c' => '2026-03-15',
                    'Gift.Type__c' => 'cash',
                    'Gift.External_Id__c' => externalId
                }
            );
        }
        ImportTestDataFactory.rows(batch, rows);
        List<Import_Row__c> dryRun;
        List<Import_Row__c> committed;

        System.runAs(maria()) {
            Test.startTest();
            dryRun = runInChunks(batch, template, true);
            committed = runInChunks(batch, template, false);
            Test.stopTest();
        }

        Assert.areEqual(ImportRowProcessor.STATUS_CREATED, dryRun[0].Status__c, 'Would be new.');
        Assert.areEqual(
            ImportRowProcessor.STATUS_MATCHED,
            dryRun[1].Status__c,
            'The repeat would be the same gift: ' + dryRun[1].Error_Message__c
        );
        for (Integer index = 0; index < 2; index++) {
            Assert.areEqual(
                dryRun[index].Status__c,
                committed[index].Status__c,
                'The commit agrees on row ' + index + ': ' + committed[index].Error_Message__c
            );
        }
        Assert.areEqual(1, [SELECT COUNT() FROM Gift__c], 'One gift, not two.');
    }

    @IsTest
    static void aStateItDidNotWriteCarriesNothing() {
        ImportEntityProcessors.carriedState = 'not a state';
        GiftImportRunState state = GiftImportRunState.carried();
        Assert.isTrue(state.claimedInstallments.isEmpty(), 'No payments.');
        Assert.isTrue(state.seenExternalIds.isEmpty(), 'No external IDs.');

        state.seenExternalIds.add(GiftImportRunState.key('Order-7'));
        state.carry();

        Assert.isTrue(
            GiftImportRunState.carried()
                .seenExternalIds.contains(GiftImportRunState.key('ORDER-7')),
            'Carried, whatever the case.'
        );
    }
}

/**
 * DuplicateScanBatch: the scan over records already in the org (R-DP3). What the matcher
 * finds is the org's own rules' business, so these tests assert what the scan does with any
 * answer: it writes only new, actionable pairs, and never touches the records it examines.
 */
@IsTest
private class DuplicateScanBatchTest {
    private static List<SObject> insertAllowingDuplicates(List<SObject> records) {
        Database.DMLOptions options = new Database.DMLOptions();
        options.DuplicateRuleHeader.allowSave = true;
        Database.insert(records, options);
        return records;
    }

    private static Boolean ruleActiveFor(String objectName) {
        return DuplicateSelector.objectsWithActiveRules(new Set<String>{ objectName })
            .contains(objectName);
    }

    @IsTest
    static void aChunkRecordsEachNewPairOnceAndASecondPassAddsNothing() {
        List<Contact> twins = (List<Contact>) insertAllowingDuplicates(
            new List<Contact>{
                new Contact(
                    FirstName = 'Rosa',
                    LastName = 'Dupscan',
                    Email = 'rosa.dupscan@example.org'
                ),
                new Contact(
                    FirstName = 'Rosa',
                    LastName = 'Dupscan',
                    Email = 'rosa.dupscan@example.org'
                )
            }
        );
        Map<String, Id> rules = DuplicateSelector.activeRuleIdsByName(new Set<String>{ 'Contact' });

        Test.startTest();
        Integer first = DuplicateScanBatch.scanChunk(twins, rules);
        Integer second = DuplicateScanBatch.scanChunk(twins, rules);
        Test.stopTest();

        Assert.areEqual(0, second, 'A pair already waiting for a reviewer is not suggested twice.');
        Assert.areEqual(
            first,
            [SELECT COUNT() FROM DuplicateRecordSet],
            'Every pair written is one suggestion.'
        );
        Assert.isTrue(first <= 1, 'Two records make at most one pair, whichever side found it.');
        if (!ruleActiveFor('Contact')) {
            Assert.areEqual(0, first, 'With no active rule nothing is invented.');
        }
        Assert.areEqual(
            2,
            [SELECT COUNT() FROM Contact WHERE Id IN :twins],
            'The scan changes no record.'
        );
    }

    @IsTest
    static void aDismissedPairIsNotWrittenAgain() {
        List<Contact> twins = (List<Contact>) insertAllowingDuplicates(
            new List<Contact>{
                new Contact(
                    FirstName = 'Iris',
                    LastName = 'Dupscan',
                    Email = 'iris.dupscan@example.org'
                ),
                new Contact(
                    FirstName = 'Iris',
                    LastName = 'Dupscan',
                    Email = 'iris.dupscan@example.org'
                )
            }
        );
        insert new Duplicate_Dismissal__c(
            Pair_Key__c = DuplicateService.pairKey(twins[0].Id, twins[1].Id)
        );

        Test.startTest();
        Integer written = DuplicateScanBatch.scanChunk(twins, null);
        Test.stopTest();

        Assert.areEqual(0, written, 'A pair somebody dismissed is passed over (R-DP5).');
    }

    @IsTest
    static void theHouseholdPassRunsToTheEndAndSaysWhatItFound() {
        insertAllowingDuplicates(
            new List<Account>{
                HouseholdTestDataFactory.newHousehold('The Dupscan Family'),
                HouseholdTestDataFactory.newHousehold('The Dupscan Family'),
                new Account(Name = 'The Dupscan Family')
            }
        );

        Test.startTest();
        Database.executeBatch(
            new DuplicateScanBatch('Account', null),
            DuplicateService.MAX_RECORDS_PER_CALL
        );
        Test.stopTest();
        Test.getEventBus().deliver();

        for (DuplicateRecordItem item : [SELECT RecordId FROM DuplicateRecordItem]) {
            Assert.areEqual(
                HouseholdService.householdRecordTypeId(),
                [SELECT RecordTypeId FROM Account WHERE Id = :item.RecordId].RecordTypeId,
                'Only households are ever paired (R-DP2).'
            );
        }
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'Duplicate scan'],
            'A finished pass says so, even when it found nothing.'
        );
    }

    @IsTest
    static void aScanStartsOnlyWhenThereIsARuleToRun() {
        Boolean anyActive = ruleActiveFor('Contact') || ruleActiveFor('Account');
        Test.startTest();
        Id jobId = DuplicateScanBatch.start();
        // No stopTest: a scan chains its second object, which a test method cannot run.
        Assert.areEqual(
            anyActive,
            jobId != null,
            'A scan starts exactly when a rule is active (R-DP3).'
        );
    }
}

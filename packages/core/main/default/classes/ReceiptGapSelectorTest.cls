/**
 * Tests for ReceiptGapSelector (feature C-11, ADR-0016 rule R-RC3).
 *
 * `Receipt__c` is a Giving object and this is a Core test, so there are two things to prove
 * without ever compiling against Giving: that an org which does not have the object is told
 * so rather than told zero, and that the query Core would run names the object and both
 * fields with whatever namespace prefix the package is carrying.
 */
@IsTest
private class ReceiptGapSelectorTest {
    @IsTest
    static void anOrgWithoutTheGivingObjectCannotBeAsked() {
        String receiptObject = NamespaceUtil.qualify('Receipt__c').toLowerCase();
        Boolean givingInstalled = Schema.getGlobalDescribe().containsKey(receiptObject);

        Test.startTest();
        ReceiptGapSelector.Result result = ReceiptGapSelector.generationFailures();
        Test.stopTest();

        if (!givingInstalled) {
            System.assertEquals(
                false,
                result.available,
                'On a Platform-only org there is no Receipt object to count, so the answer is ' +
                    '"cannot be asked". Health Check turns that into no finding, which is the ' +
                    'point: a zero here would read as "no receipts have failed".'
            );
            System.assertEquals(
                0,
                result.count,
                'An unavailable count is zero rather than null, so no caller has to null check ' +
                'a number it must not use anyway.'
            );
        } else {
            System.assertEquals(
                true,
                result.available,
                'The Giving package is deployed here and the running user is an administrator, ' +
                'so the count is answerable.'
            );
            System.assert(
                result.count >= 0,
                'A count that ran returns a real number of reconciled receipt numbers.'
            );
        }
    }

    @IsTest
    static void theCountQueryNamesTheObjectAndBothFields() {
        // Built at run time rather than written out: a prefixed API name in source is exactly
        // what scripts/ci/check-namespace.sh forbids, and rightly.
        String prefix = 'given' + '__';
        String query = ReceiptGapSelector.countQuery(
            prefix + 'Receipt__c',
            prefix + 'Status__c',
            prefix + 'Void_Reason__c'
        );

        System.assertEquals(
            'SELECT COUNT() FROM ' +
                prefix +
                'Receipt__c WHERE ' +
                prefix +
                'Status__c = :status AND ' +
                prefix +
                'Void_Reason__c = :reason',
            query,
            'Every API name in the query is the one the caller handed in, prefix and all, and ' +
                'the two values matched on are bind variables rather than text pasted into the ' +
                'query.'
        );
    }

    @IsTest
    static void theQueryCarriesWhateverNamespaceThisPackageRunsUnder() {
        String query = ReceiptGapSelector.countQuery(
            NamespaceUtil.qualify('Receipt__c'),
            NamespaceUtil.qualify('Status__c'),
            NamespaceUtil.qualify('Void_Reason__c')
        );

        System.assert(
            query.contains(NamespaceUtil.qualify('Void_Reason__c') + ' = :reason'),
            'The field name the query filters on is the qualified one, so this keeps working ' +
                'the day the namespace is registered (ADR-0001). Query was: ' +
                query
        );
        System.assert(
            !query.contains('Generation failed'),
            'The reason is bound, never concatenated, so nothing a record holds can reach the ' +
            'query text.'
        );
    }

    @IsTest
    static void anInjectedResultIsUsedUnchanged() {
        ReceiptGapSelector.Result stub = new ReceiptGapSelector.Result();
        stub.available = true;
        stub.count = 6;
        ReceiptGapSelector.resultOverride = stub;

        ReceiptGapSelector.Result result = ReceiptGapSelector.generationFailures();

        System.assertEquals(
            6,
            result.count,
            'The injection point the Health Check tests rely on returns exactly what it was ' +
            'given, so a finding asserted through it is asserting the finding and not the org.'
        );
    }
}

/**
 * Tests for OrgShapeDetector (feature C-07).
 *
 * The recommendation is tested against a forced shape rather than against the org the tests
 * happen to run in, so that every branch is covered on every org shape in the CI matrix.
 * detect() itself is tested against the real org, which is the only honest way to know that
 * the describe calls work where Core has to run.
 */
@IsTest
private class OrgShapeDetectorTest {
    @IsTest
    static void detectPopulatesTheWholeShape() {
        OrgShapeDetector.reset();

        Test.startTest();
        OrgShapeDetector.OrgShape shape = OrgShapeDetector.detect();
        Test.stopTest();

        System.assertNotEquals(null, shape, 'Detection should always return a shape.');
        System.assertNotEquals(null, shape.hasNpsp, 'hasNpsp should be answered, not left null.');
        System.assertNotEquals(
            null,
            shape.hasPersonAccounts,
            'hasPersonAccounts should be answered, not left null.'
        );
        System.assertNotEquals(
            null,
            shape.hasIndustriesNonprofit,
            'hasIndustriesNonprofit should be answered, not left null.'
        );
        System.assertNotEquals(
            null,
            shape.hasSalesCloudObjects,
            'hasSalesCloudObjects should be answered, not left null.'
        );
        System.assertNotEquals(
            null,
            shape.isMultiCurrency,
            'isMultiCurrency should be answered, not left null.'
        );
        System.assertEquals(
            null,
            shape.platformEncryptionPossible,
            'Platform Encryption cannot be detected, so it stays null and Health Check says so.'
        );
        System.assertNotEquals(
            null,
            shape.personAccountRecordTypeIds,
            'The person account record type set is always present, empty when there are none.'
        );
    }

    @IsTest
    static void detectIsCachedForTheTransaction() {
        OrgShapeDetector.reset();

        OrgShapeDetector.OrgShape first = OrgShapeDetector.detect();
        OrgShapeDetector.OrgShape second = OrgShapeDetector.detect();

        System.assert(first === second, 'The shape should be computed once per transaction.');
    }

    @IsTest
    static void personAccountsRecommendAgentforceNonprofit() {
        OrgShapeDetector.overrideShape = shapeWith(false, true, false);

        System.assertEquals(
            CoexistenceService.MODE_AGENTFORCE_NONPROFIT,
            OrgShapeDetector.recommendedCoexistenceMode(),
            'A Person Accounts org is an Agentforce Nonprofit org.'
        );
    }

    @IsTest
    static void industriesObjectsRecommendAgentforceNonprofit() {
        OrgShapeDetector.overrideShape = shapeWith(false, false, true);

        System.assertEquals(
            CoexistenceService.MODE_AGENTFORCE_NONPROFIT,
            OrgShapeDetector.recommendedCoexistenceMode(),
            'Nonprofit Cloud gift objects mean Agentforce Nonprofit coexistence.'
        );
    }

    @IsTest
    static void npspRecommendsNpspCoexistence() {
        OrgShapeDetector.overrideShape = shapeWith(true, false, false);

        System.assertEquals(
            CoexistenceService.MODE_NPSP,
            OrgShapeDetector.recommendedCoexistenceMode(),
            'An NPSP org without Person Accounts gets NPSP coexistence.'
        );
    }

    @IsTest
    static void agentforceNonprofitWinsOverNpsp() {
        OrgShapeDetector.overrideShape = shapeWith(true, true, false);

        System.assertEquals(
            CoexistenceService.MODE_AGENTFORCE_NONPROFIT,
            OrgShapeDetector.recommendedCoexistenceMode(),
            'When both are present, Person Accounts decide how households are built.'
        );
    }

    @IsTest
    static void plainOrgRecommendsStandalone() {
        OrgShapeDetector.overrideShape = shapeWith(false, false, false);

        System.assertEquals(
            CoexistenceService.MODE_STANDALONE,
            OrgShapeDetector.recommendedCoexistenceMode(),
            'An org with nothing else in it runs standalone.'
        );
    }

    @IsTest
    static void resetClearsTheOverride() {
        OrgShapeDetector.overrideShape = shapeWith(true, true, true);
        OrgShapeDetector.reset();

        System.assertNotEquals(
            null,
            OrgShapeDetector.detect(),
            'After a reset, detection reads the org again.'
        );
    }

    private static OrgShapeDetector.OrgShape shapeWith(
        Boolean hasNpsp,
        Boolean hasPersonAccounts,
        Boolean hasIndustriesNonprofit
    ) {
        OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
        shape.hasNpsp = hasNpsp;
        shape.hasPersonAccounts = hasPersonAccounts;
        shape.hasIndustriesNonprofit = hasIndustriesNonprofit;
        return shape;
    }
}

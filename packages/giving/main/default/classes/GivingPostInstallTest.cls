/**
 * Tests for GivingPostInstall: installing the Giving module puts the giving totals in the
 * org, upgrading it does not create them twice and does not undo an administrator's edit,
 * and every definition it creates names objects this org actually has.
 *
 * These run against the shipped `Rollup_Definition_Default__mdt` rows rather than against
 * in-memory substitutes, because the thing being tested is exactly that the rows Giving
 * ships reach the org: a test that supplied its own rows would pass in a package that
 * shipped none.
 *
 * These tests have not been executed: no Salesforce org exists in this environment. What a
 * real install has still to confirm is named in ADR-0029.
 */
@IsTest
private class GivingPostInstallTest {
    @IsTest
    static void installingGivingCreatesTheGivingTotals() {
        // The defect this covers: nothing called ensureDefaults, so a fresh install had no
        // Rollup Definition records and every giving total on every donor was blank.
        GivingPostInstall handler = new GivingPostInstall();

        Test.startTest();
        Test.testInstall(handler, null);
        Test.stopTest();

        Map<String, Rollup_Definition__c> byKey = definitionsByKey();
        List<String> shippedKeys = shippedGivingKeys();
        Assert.isFalse(shippedKeys.isEmpty(), 'The package ships rollup defaults to materialize.');
        for (String key : shippedKeys) {
            Assert.isTrue(
                byKey.containsKey(key),
                'Every rollup Giving ships is created by its own install, including ' + key
            );
        }
        Assert.isTrue(
            byKey.containsKey('Household_Total_Giving'),
            'A household has its total giving, which is the number every gift screen shows.'
        );

        Rollup_Definition__c householdGiving = byKey.get('Household_Total_Giving');
        Assert.areEqual(
            'Total_Giving__c',
            householdGiving.Target_Field__c,
            'It writes the attribute the record page and the donor level read.'
        );
        Assert.isTrue(
            householdGiving.Active__c,
            'It arrives switched on, so the total is calculated without a second step.'
        );
        Assert.isTrue(
            householdGiving.Is_Package_Default__c,
            'It is marked as shipped, so the Rollups page can tell it from an admin rollup.'
        );
    }

    @IsTest
    static void upgradingCreatesNothingAndKeepsWhatTheAdminChanged() {
        GivingPostInstall handler = new GivingPostInstall();
        Test.testInstall(handler, null);
        Integer afterInstall = [SELECT COUNT() FROM Rollup_Definition__c];
        Rollup_Definition__c householdGiving = definitionsByKey().get('Household_Total_Giving');
        // Maria decides she does not want this one, which R-R6 says is done by switching it
        // off rather than by deleting it.
        update new Rollup_Definition__c(Id = householdGiving.Id, Active__c = false);

        Test.startTest();
        Test.testInstall(handler, new Version(1, 0), true);
        Test.stopTest();

        Assert.areEqual(
            afterInstall,
            [SELECT COUNT() FROM Rollup_Definition__c],
            'An upgrade creates no second copy of a rollup that is already here.'
        );
        Rollup_Definition__c afterUpgrade = definitionsByKey().get('Household_Total_Giving');
        Assert.areEqual(
            householdGiving.Id,
            afterUpgrade.Id,
            'It is the same record, not a replacement.'
        );
        Assert.isFalse(
            afterUpgrade.Active__c,
            'A rollup the admin switched off stays off across an upgrade (R-R6).'
        );
    }

    @IsTest
    static void everyDefinitionCreatedNamesObjectsThisOrgHas() {
        // The guard that keeps a Core-only org clean is the same one that would let a broken
        // row through here: a definition naming an object nobody has can never calculate.
        Test.startTest();
        Test.testInstall(new GivingPostInstall(), null);
        Test.stopTest();

        List<Rollup_Definition__c> created = [
            SELECT Definition_Key__c, Source_Object__c, Target_Object__c
            FROM Rollup_Definition__c
        ];
        Assert.isFalse(created.isEmpty(), 'There is something to check.');
        for (Rollup_Definition__c definition : created) {
            Assert.isNotNull(
                SettingsService.typeByName(definition.Source_Object__c),
                'Source of ' +
                    definition.Definition_Key__c +
                    ' is an object this org has: ' +
                    definition.Source_Object__c
            );
            Assert.isNotNull(
                SettingsService.typeByName(definition.Target_Object__c),
                'Target of ' +
                    definition.Definition_Key__c +
                    ' is an object this org has: ' +
                    definition.Target_Object__c
            );
        }
    }

    /**
     * The Definition Keys of the rollup defaults this package ships.
     *
     * @return one key per shipped Giving row
     */
    private static List<String> shippedGivingKeys() {
        List<String> keys = new List<String>();
        for (Rollup_Definition_Default__mdt shipped : [
            SELECT Definition_Key__c
            FROM Rollup_Definition_Default__mdt
            WHERE Package__c = 'Giving'
            WITH SYSTEM_MODE
            LIMIT 1000
        ]) {
            keys.add(shipped.Definition_Key__c);
        }
        return keys;
    }

    /**
     * The definitions in the org, keyed by the Definition Key the shipped rows are matched on.
     *
     * @return every Rollup Definition, by key
     */
    private static Map<String, Rollup_Definition__c> definitionsByKey() {
        Map<String, Rollup_Definition__c> byKey = new Map<String, Rollup_Definition__c>();
        for (Rollup_Definition__c definition : [
            SELECT Id, Definition_Key__c, Target_Field__c, Active__c, Is_Package_Default__c, Mode__c
            FROM Rollup_Definition__c
        ]) {
            byKey.put(definition.Definition_Key__c, definition);
        }
        return byKey;
    }
}

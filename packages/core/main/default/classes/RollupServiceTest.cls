/**
 * The engine as the rest of Open Impact sees it: materializing shipped defaults, running a
 * definition, and stamping freshness.
 *
 * These tests have not been executed: no Salesforce org exists in this environment. The engine
 * itself is stood down with `RollupService.skipEngine`, because what is being asserted here is
 * Open Impact's side of ADR-0015: which definitions are selected, what metadata they become, and
 * what is stamped afterwards. The engine's own behaviour is upstream's, and upstream tests it.
 */
@IsTest
private class RollupServiceTest {
    private static Rollup_Definition__c memberCount(String mode, Boolean active) {
        return new Rollup_Definition__c(
            Name = 'Household member count',
            Definition_Key__c = 'Core_Household_Member_Count',
            Source_Object__c = 'Household_Member__c',
            Target_Object__c = 'Account',
            Relationship_Path__c = 'Household__c',
            Aggregate__c = 'COUNT',
            Target_Field__c = 'Member_Count__c',
            Mode__c = mode,
            Fiscal_Year_Aware__c = false,
            Active__c = active
        );
    }

    @IsTest
    static void theDefaultModeComesFromTheOrgSetting() {
        SettingsService.saveSystemValue('Rollup_Mode_Default__c', RollupService.MODE_SCHEDULED);
        SettingsService.clearCaches();

        System.Assert.areEqual(
            RollupService.MODE_SCHEDULED,
            RollupService.defaultMode(),
            'A new rollup starts in the mode the org chose'
        );
    }

    @IsTest
    static void anOrgThatHasNotChosenGetsBoth() {
        SettingsService.saveSystemValue('Rollup_Mode_Default__c', 'Nonsense');
        SettingsService.clearCaches();

        System.Assert.areEqual(
            RollupService.MODE_BOTH,
            RollupService.defaultMode(),
            'Both is the mode R-R4 says keeps the numbers visibly right'
        );
    }

    @IsTest
    static void shippedDefaultsAreMaterializedOnceAndNeverOverwritten() {
        RollupSelector.defaultsOverride = new List<Rollup_Definition_Default__mdt>{
            new Rollup_Definition_Default__mdt(
                DeveloperName = 'Core_Household_Member_Count',
                MasterLabel = 'Household member count',
                Definition_Key__c = 'Core_Household_Member_Count',
                Source_Object__c = 'Household_Member__c',
                Target_Object__c = 'Account',
                Relationship_Path__c = 'Household__c',
                Aggregate__c = 'COUNT',
                Target_Field__c = 'Member_Count__c',
                Mode__c = 'Both',
                Fiscal_Year_Aware__c = false,
                Default_Active__c = true,
                Package__c = 'Core'
            )
        };

        Test.startTest();
        Integer firstRun = RollupService.ensureDefaults();
        Integer secondRun = RollupService.ensureDefaults();
        Test.stopTest();

        System.Assert.areEqual(1, firstRun, 'The shipped default is created once');
        System.Assert.areEqual(
            0,
            secondRun,
            'And never again, so an upgrade leaves an edit alone (R-R6)'
        );

        List<Rollup_Definition__c> created = [
            SELECT Definition_Key__c, Is_Package_Default__c, Active__c, Mode__c
            FROM Rollup_Definition__c
        ];
        System.Assert.areEqual(1, created.size(), 'One definition');
        System.Assert.isTrue(created[0].Is_Package_Default__c, 'It is marked as shipped');
        System.Assert.isTrue(created[0].Active__c, 'And it is on');
    }

    @IsTest
    static void aDefaultForAPackageThatIsNotInstalledIsSkipped() {
        RollupSelector.defaultsOverride = new List<Rollup_Definition_Default__mdt>{
            new Rollup_Definition_Default__mdt(
                DeveloperName = 'Not_Installed',
                MasterLabel = 'A rollup for something that is not here',
                Definition_Key__c = 'Not_Installed',
                Source_Object__c = 'Nothing_Like_This__c',
                Target_Object__c = 'Account',
                Aggregate__c = 'COUNT',
                Relationship_Path__c = 'Account__c',
                Target_Field__c = 'Member_Count__c',
                Mode__c = 'Both',
                Default_Active__c = true,
                Package__c = 'Volunteers'
            )
        };

        System.Assert.areEqual(
            0,
            RollupService.ensureDefaults(),
            'A rollup whose records are not in this org names objects nobody has'
        );
    }

    @IsTest
    static void onlyTheActiveDefinitionsForTheChangedEntityRunInRealTime() {
        insert new List<Rollup_Definition__c>{
            memberCount(RollupService.MODE_REAL_TIME, true),
            memberCountNamed(
                'Scheduled only',
                'Core_Scheduled_Only',
                RollupService.MODE_SCHEDULED,
                true
            ),
            memberCountNamed('Turned off', 'Core_Turned_Off', RollupService.MODE_REAL_TIME, false)
        };

        List<Rollup_Definition__c> forRealTime = RollupSelector.selectActiveForSource(
            'Household_Member__c',
            new Set<String>{ RollupService.MODE_REAL_TIME, RollupService.MODE_BOTH }
        );

        System.Assert.areEqual(
            1,
            forRealTime.size(),
            'A scheduled rollup and an inactive one both stay out'
        );
        System.Assert.areEqual(
            'Core_Household_Member_Count',
            forRealTime[0].Definition_Key__c,
            'The right one runs'
        );
    }

    @IsTest
    static void aRunStampsTheDefinitionSoTheConsoleCanSayWhen() {
        Rollup_Definition__c definition = memberCount(RollupService.MODE_BOTH, true);
        insert definition;
        RollupService.skipEngine = true;

        Test.startTest();
        RollupService.recalculate(definition.Id);
        Test.stopTest();

        Rollup_Definition__c stamped = [
            SELECT Last_Calculated__c
            FROM Rollup_Definition__c
            WHERE Id = :definition.Id
        ];
        System.Assert.isNotNull(
            stamped.Last_Calculated__c,
            'R-R5: the console can say when this rollup last ran'
        );
        System.Assert.isFalse(RollupService.isStale(), 'A rollup that just ran is not overdue');
    }

    @IsTest
    static void anOrgThatHasNeverCalculatedIsReportedAsOverdue() {
        insert memberCount(RollupService.MODE_BOTH, true);

        System.Assert.isNull(RollupService.lastCalculated(), 'Nothing has run');
        System.Assert.isTrue(
            RollupService.isStale(),
            'Which the Hub tile says out loud (plan Section 4.10)'
        );
    }

    @IsTest
    static void aBrokenDefinitionIsLoggedAndTheRestStillRun() {
        Rollup_Definition__c broken = memberCount(RollupService.MODE_BOTH, true);
        broken.Aggregate__c = 'SUM';
        broken.Source_Field__c = null;
        insert broken;
        RollupService.skipEngine = true;

        Test.startTest();
        Integer ran = RollupService.runFullRecalculation(new List<Rollup_Definition__c>{ broken });
        Test.stopTest();

        System.Assert.areEqual(
            0,
            ran,
            'A definition that cannot be expressed is skipped, not thrown'
        );
    }

    @IsTest
    static void recalculatingSomethingThatIsNotThereSaysSo() {
        try {
            RollupService.recalculate(null);
            System.Assert.fail(
                'An unknown definition is refused with a message an admin can act on'
            );
        } catch (RollupService.RollupServiceException expected) {
            System.Assert.isNotNull(expected.getMessage(), 'The message names the problem');
        }
    }

    private static Rollup_Definition__c memberCountNamed(
        String name,
        String key,
        String mode,
        Boolean active
    ) {
        Rollup_Definition__c definition = memberCount(mode, active);
        definition.Name = name;
        definition.Definition_Key__c = key;
        return definition;
    }
}

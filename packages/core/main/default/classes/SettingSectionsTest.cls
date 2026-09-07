/** One vocabulary of section names, so a setup step and a shipped row can agree on one. */
@IsTest
private class SettingSectionsTest {
    @IsTest
    static void namesEverySectionTheConsoleGroupsBy() {
        Test.startTest();
        List<String> sections = SettingSections.all();
        Test.stopTest();

        Assert.areEqual(8, sections.size(), 'Eight sections ship in v0.1');
        Assert.areEqual(
            SettingSections.GENERAL,
            sections[0],
            'General comes first, because it is where a new org starts'
        );
        Assert.isTrue(SettingSections.isKnown('households'), 'The check ignores case');
        Assert.isTrue(SettingSections.isKnown('  Health '), 'The check ignores spacing');
        Assert.isFalse(
            SettingSections.isKnown('Household names and greetings'),
            'A section name nobody agreed on is not one of ours'
        );
        Assert.isFalse(SettingSections.isKnown(null), 'Nothing is not a section');
    }

    @IsTest
    static void everySetupStepPointsAtASectionThatExists() {
        Test.startTest();
        List<SetupAssistantService.Step> steps = SetupAssistantService.getSteps();
        Test.stopTest();

        for (SetupAssistantService.Step step : steps) {
            Assert.isTrue(
                SettingSections.isKnown(step.target),
                'Step ' + step.key + ' opens section ' + step.target + ', which has to exist'
            );
        }
    }
}

/**
 * The Hub error tile is a number, and it is zero rather than an error when the Error Log
 * is not part of this package build.
 */
@IsTest
private class HubErrorCountSelectorTest {
    @IsTest
    static void countsWithoutFailingWhenTheErrorLogIsAbsent() {
        Test.startTest();
        Integer count = HubErrorCountSelector.countNewErrors();
        Test.stopTest();

        Assert.isNotNull(count, 'The tile always has a number to show');
        Assert.isTrue(count >= 0, 'A count is never negative');
    }
}

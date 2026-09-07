/**
 * A trigger handler the shipped registry can name, used only by the trigger framework's tests.
 *
 * It is a top-level public class with a no-argument constructor because that is what
 * `Type.forName` needs in order to build a handler a registry record names (ADR-0017). It counts
 * its own runs on a static, since the dispatcher builds the instance and the test never sees it.
 */
@IsTest
public class TestRegisteredHandler extends TriggerHandler {
    public static Integer runCount = 0;

    public static void reset() {
        runCount = 0;
    }

    public override void afterInsert(List<SObject> newRecords, Map<Id, SObject> newRecordsById) {
        runCount++;
    }
}

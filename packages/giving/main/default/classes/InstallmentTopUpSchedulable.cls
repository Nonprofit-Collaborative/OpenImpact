/**
 * The daily job that extends the schedules of active recurring commitments up to the
 * org's generation horizon, so an open-ended schedule always has the next year of
 * expected payments in front of it without ever generating rows forever (R-CM2).
 *
 * It records when it last finished on Giving Settings, which is what the Hub shows.
 */
public with sharing class InstallmentTopUpSchedulable implements Schedulable {
    public void execute(SchedulableContext context) {
        try {
            CommitmentService.topUpRecurringSchedules();
            CommitmentService.recordTopUpRun(System.now());
        } catch (Exception jobFailure) {
            ErrorLogger.log('InstallmentTopUpSchedulable', jobFailure);
        }
    }
}

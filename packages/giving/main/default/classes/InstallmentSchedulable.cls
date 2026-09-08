/**
 * The daily job that marks unpaid installments Overdue once the org's grace period has
 * passed (R-IN2). Scheduled by GivingScheduler when the Giving module is turned on.
 */
public with sharing class InstallmentSchedulable implements Schedulable {
    public void execute(SchedulableContext context) {
        try {
            CommitmentService.markOverdue();
        } catch (Exception jobFailure) {
            ErrorLogger.log(jobFailure, 'InstallmentSchedulable');
        }
    }
}

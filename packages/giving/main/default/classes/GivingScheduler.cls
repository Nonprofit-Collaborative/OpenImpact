/**
 * Schedules the Giving module's daily jobs. The module turn-on step in the Settings
 * console calls scheduleAll, so Maria never opens Setup to schedule Apex (Principle 1).
 *
 * Both jobs are safe to run twice on the same day: topping up a schedule adds only the
 * installments that are missing, and marking overdue is a recalculation.
 */
public with sharing class GivingScheduler {
    @TestVisible
    private static final String TOP_UP_JOB_NAME = 'Open Impact Giving: installment top up';
    @TestVisible
    private static final String OVERDUE_JOB_NAME = 'Open Impact Giving: installments overdue';
    // Both run in the small hours, the top up first so the overdue pass sees every row.
    private static final String TOP_UP_CRON = '0 15 1 * * ?';
    private static final String OVERDUE_CRON = '0 45 1 * * ?';

    /**
     * Schedules both daily jobs and returns the identifiers of the scheduled jobs, so the
     * caller can show what it started. A job already scheduled under the same name is left
     * as it is.
     */
    public static List<Id> scheduleAll() {
        List<Id> jobIds = new List<Id>();
        jobIds.add(scheduleJob(TOP_UP_JOB_NAME, TOP_UP_CRON, new InstallmentTopUpSchedulable()));
        jobIds.add(scheduleJob(OVERDUE_JOB_NAME, OVERDUE_CRON, new InstallmentSchedulable()));
        return jobIds;
    }

    private static Id scheduleJob(String jobName, String cron, Schedulable job) {
        try {
            return System.schedule(jobName, cron, job);
        } catch (Exception scheduleFailure) {
            // Already scheduled, or the running user cannot schedule Apex.
            ErrorLogger.log('GivingScheduler.' + jobName, scheduleFailure);
            return null;
        }
    }
}

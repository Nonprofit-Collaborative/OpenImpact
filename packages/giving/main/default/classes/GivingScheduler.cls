/**
 * Schedules the Giving module's daily jobs. The module turn-on step in the Settings
 * console calls scheduleAll, so Maria never opens Setup to schedule Apex (Principle 1).
 *
 * All three jobs are safe to run twice on the same day: topping up a schedule adds only the
 * installments that are missing, and marking overdue and placing donors on their giving level are
 * both recalculations.
 */
public with sharing class GivingScheduler {
    @TestVisible
    private static final String TOP_UP_JOB_NAME = 'Open Impact Giving: installment top up';
    @TestVisible
    private static final String OVERDUE_JOB_NAME = 'Open Impact Giving: installments overdue';
    @TestVisible
    private static final String LEVELS_JOB_NAME = 'Open Impact Giving: donor levels';
    // All three run in the small hours, the top up first so the overdue pass sees every row, and
    // the levels last so that the night's rollups have settled before donors are re-placed.
    private static final String TOP_UP_CRON = '0 15 1 * * ?';
    private static final String OVERDUE_CRON = '0 45 1 * * ?';
    private static final String LEVELS_CRON = '0 15 2 * * ?';

    /**
     * Schedules both daily jobs and returns the identifiers of the scheduled jobs, so the
     * caller can show what it started. A job already scheduled under the same name is left
     * as it is.
     */
    public static List<Id> scheduleAll() {
        List<Id> jobIds = new List<Id>();
        jobIds.add(scheduleJob(TOP_UP_JOB_NAME, TOP_UP_CRON, new InstallmentTopUpSchedulable()));
        jobIds.add(scheduleJob(OVERDUE_JOB_NAME, OVERDUE_CRON, new InstallmentSchedulable()));
        jobIds.add(scheduleJob(LEVELS_JOB_NAME, LEVELS_CRON, new DonorLevelSchedulable()));
        return jobIds;
    }

    private static Id scheduleJob(String jobName, String cron, Schedulable job) {
        try {
            return System.schedule(jobName, cron, job);
        } catch (Exception scheduleFailure) {
            // Already scheduled, or the running user cannot schedule Apex.
            ErrorLogger.log(scheduleFailure, 'GivingScheduler.' + jobName);
            return null;
        }
    }
}

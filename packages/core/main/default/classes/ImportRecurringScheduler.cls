/**
 * The daily schedule for recurring sources, and the two buttons on the import page that start
 * and stop it (R-IT6).
 *
 * The schedule is started from the app, not from Setup, for the reason the seasonal address
 * job records: a job with no in-app way to schedule it is a job nobody schedules. The switch
 * that decides whether the job does anything is the ordinary settings key
 * `Import_Recurring_Enabled__c`, which the Nonprofit Settings console also shows, so turning
 * the feature off never depends on finding this page.
 */
public with sharing class ImportRecurringScheduler implements Schedulable {
    /** The name the scheduled job carries, so the import page can find it again. */
    public static final String JOB_NAME = 'Open Impact Recurring Imports';

    /**
     * A quarter past one in the morning. After the seasonal address swap at half past
     * midnight and before the rollups at two, so the three packaged jobs are not competing
     * for the org's batch slots.
     */
    private static final String NIGHTLY_CRON = '0 15 1 * * ?';

    public void execute(SchedulableContext context) {
        try {
            ImportRecurringService.run();
        } catch (Exception e) {
            ErrorLogger.log(e, 'ImportRecurringScheduler.execute');
        }
    }

    /** Starts the daily look for new files, or does nothing when it is already scheduled. */
    public static Id start() {
        Id existing = scheduledJobId();
        if (existing != null) {
            return existing;
        }
        return System.schedule(JOB_NAME, NIGHTLY_CRON, new ImportRecurringScheduler());
    }

    /** Stops it. Imports already loaded stay exactly as they are. */
    public static void stop() {
        Id existing = scheduledJobId();
        if (existing != null) {
            System.abortJob(existing);
        }
    }

    /** Looks now, without waiting for tonight. */
    public static Integer runNow() {
        return ImportRecurringService.run();
    }

    /** True when the daily look is scheduled. */
    public static Boolean isScheduled() {
        return scheduledJobId() != null;
    }

    /** When it is next due, or null when it is not scheduled. */
    public static Datetime nextRunAt() {
        Id jobId = scheduledJobId();
        if (jobId == null) {
            return null;
        }
        List<CronTrigger> triggers = [
            SELECT NextFireTime
            FROM CronTrigger
            WHERE Id = :jobId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return triggers.isEmpty() ? null : triggers[0].NextFireTime;
    }

    private static Id scheduledJobId() {
        List<CronJobDetail> details = [
            SELECT Id
            FROM CronJobDetail
            WHERE Name = :JOB_NAME AND JobType = '7'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (details.isEmpty()) {
            return null;
        }
        List<CronTrigger> triggers = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetailId = :details[0].Id
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return triggers.isEmpty() ? null : triggers[0].Id;
    }
}

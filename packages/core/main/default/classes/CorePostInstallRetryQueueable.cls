/**
 * Waits for the platform to finish calculating the Nonprofit Admin permission set group,
 * then gives it to the person who installed the package.
 *
 * Salesforce recalculates a packaged permission set group in the background after an
 * install or an upgrade, and it refuses to assign one while that is running. The install
 * has already given the installer the permission set itself, so they are not blocked; this
 * job exists to finish the job properly, so that the Access page lists them under the
 * Nonprofit Admin role rather than showing an org where nobody holds it.
 *
 * It re-checks a few times, a job at a time, a minute apart, and then stops. It never
 * throws: an install or an upgrade must not fail because of a background tidy-up.
 */
public with sharing class CorePostInstallRetryQueueable implements Queueable {
    /** How many times to look before giving up. */
    @TestVisible
    private static final Integer MAX_ATTEMPTS = 5;

    /**
     * How long to wait between attempts.
     *
     * A Queueable cannot sleep, so the wait is the job re-enqueueing itself with the
     * delayed-execution overload of System.enqueueJob (available since API 60; this package
     * is on 67). A minute is well under the few minutes the platform typically takes to
     * finish calculating a packaged group, and MAX_ATTEMPTS gives five of them before the
     * job gives up.
     */
    @TestVisible
    private static final Integer RETRY_DELAY_MINUTES = 1;

    private static final String CONTEXT = 'CorePostInstallRetryQueueable.execute';

    private final Id installerId;
    private final Integer attemptsLeft;

    /**
     * Starts the wait with the full number of attempts.
     *
     * @param installerId the person who installed or upgraded the package
     */
    public CorePostInstallRetryQueueable(Id installerId) {
        this(installerId, MAX_ATTEMPTS);
    }

    /**
     * Continues the wait with the attempts that are left.
     *
     * @param installerId the person who installed or upgraded the package
     * @param attemptsLeft how many more times to look
     */
    public CorePostInstallRetryQueueable(Id installerId, Integer attemptsLeft) {
        this.installerId = installerId;
        this.attemptsLeft = attemptsLeft;
    }

    /**
     * Looks once. Assigns the role if the group is ready, queues another look if it is
     * not, and writes a warning to the Error Log if the attempts run out.
     *
     * @param jobContext the platform's queueable context, not used
     */
    public void execute(QueueableContext jobContext) {
        try {
            if (installerId == null) {
                return;
            }
            if (AccessService.tryAssignRoleDuringInstall(installerId, AccessService.ADMIN_ROLE)) {
                return;
            }
            if (attemptsLeft > 1) {
                System.enqueueJob(
                    new CorePostInstallRetryQueueable(installerId, attemptsLeft - 1),
                    RETRY_DELAY_MINUTES
                );
                return;
            }
            giveUp();
        } catch (Exception e) {
            ErrorLogger.log(e, CONTEXT);
        }
    }

    /**
     * Records that the role was never handed out, and what to do about it.
     *
     * The Error Log takes an exception, so the warning is carried as one. Nothing rethrows
     * it: this is a note for the administrator, not a failure.
     */
    private void giveUp() {
        ErrorLogger.log(
            new AccessService.AccessException(
                'Warning: the Nonprofit Admin role was still being prepared after ' +
                    MAX_ATTEMPTS +
                    ' attempts, so it was not given to the person who installed Open Impact. ' +
                    'They already have the Nonprofit Admin permission set, so Nonprofit Settings ' +
                    'works. To finish, open Nonprofit Settings, then Access, and give them the ' +
                    'Nonprofit Admin role.'
            ),
            CONTEXT
        );
    }
}

/**
 * The business rules of commitments: building a schedule, generating and regenerating
 * installments, applying gifts to them, marking them overdue, and moving a commitment
 * between statuses (canonical model Sections 22 and 23, features G-07 and G-11).
 *
 * Paid To Date on the commitment and Paid Amount on the installment are rollup targets
 * written by the Core engine. This service never writes them. It reads the gifts itself
 * so that an installment's status is right in the same transaction as the gift, which is
 * what staff see immediately after saving.
 */
public with sharing class CommitmentService {
    @TestVisible
    private static final String TYPE_PLEDGE = 'Pledge';
    @TestVisible
    private static final String TYPE_RECURRING = 'Recurring';
    @TestVisible
    private static final String STATUS_ACTIVE = 'Active';
    @TestVisible
    private static final String STATUS_PAUSED = 'Paused';
    @TestVisible
    private static final String STATUS_COMPLETED = 'Completed';
    @TestVisible
    private static final String STATUS_CANCELLED = 'Cancelled';
    @TestVisible
    private static final String INSTALLMENT_SCHEDULED = 'Scheduled';
    @TestVisible
    private static final String INSTALLMENT_PAID = 'Paid';
    @TestVisible
    private static final String INSTALLMENT_PARTIALLY_PAID = 'Partially paid';
    @TestVisible
    private static final String INSTALLMENT_OVERDUE = 'Overdue';
    @TestVisible
    private static final String INSTALLMENT_SKIPPED = 'Skipped';

    private static final String SETTINGS_OBJECT = 'Giving_Settings__c';
    private static final String KEY_HORIZON = 'Installment_Generation_Horizon_Months__c';
    private static final String KEY_GRACE = 'Installment_Overdue_Grace_Days__c';
    private static final String KEY_AUTO_APPLY = 'Auto_Apply_Gifts_To_Installments__c';
    private static final Integer DEFAULT_HORIZON_MONTHS = 12;
    private static final Integer DEFAULT_GRACE_DAYS = 5;
    private static final Integer MAX_SCHEDULE_LENGTH = 520;
    private static final Integer MAX_OVERDUE_ROWS = 5000;
    private static final Integer MAX_TOP_UP_COMMITMENTS = 500;

    /** Gifts this transaction has already linked to an installment, so it does not loop. */
    @TestVisible
    private static Set<Id> giftsLinkedThisTransaction = new Set<Id>();

    // ------------------------------------------------------------------ schedule shape

    /**
     * The schedule a commitment implies, as unsaved installments in sequence order.
     * Nothing is queried and nothing is saved, so the same method serves the preview on
     * screen and the generation behind it.
     */
    public static List<Installment__c> buildSchedule(Commitment__c commitment) {
        List<Installment__c> plan = new List<Installment__c>();
        if (
            commitment == null ||
            commitment.Amount__c == null ||
            commitment.Start_Date__c == null
        ) {
            return plan;
        }
        if (commitment.Amount__c <= 0) {
            return plan;
        }
        Integer count = plannedCount(commitment);
        if (count <= 0) {
            return plan;
        }
        Decimal expectedTotal = TYPE_PLEDGE.equals(commitment.Type__c)
            ? commitment.Expected_Total__c
            : null;
        Decimal runningTotal = 0;
        for (Integer index = 0; index < count; index++) {
            Date dueDate = dueDateFor(commitment, index);
            if (commitment.End_Date__c != null && dueDate > commitment.End_Date__c) {
                break;
            }
            Decimal amount = commitment.Amount__c;
            Boolean isLast = index == count - 1;
            if (isLast && expectedTotal != null) {
                // The last installment absorbs whatever the even amounts left over.
                amount = (expectedTotal - runningTotal).setScale(2);
            }
            runningTotal += amount;
            plan.add(
                new Installment__c(
                    Commitment__c = commitment.Id,
                    Sequence__c = index + 1,
                    Due_Date__c = dueDate,
                    Expected_Amount__c = amount,
                    Status__c = INSTALLMENT_SCHEDULED
                )
            );
        }
        return plan;
    }

    /**
     * How many installments the schedule holds: what the pledge planned, or the total
     * divided by the amount, or as far ahead as the horizon reaches for a recurring gift.
     */
    @TestVisible
    private static Integer plannedCount(Commitment__c commitment) {
        if (TYPE_PLEDGE.equals(commitment.Type__c)) {
            if (
                commitment.Installments_Planned__c != null &&
                commitment.Installments_Planned__c > 0
            ) {
                return Math.min(commitment.Installments_Planned__c.intValue(), MAX_SCHEDULE_LENGTH);
            }
            if (commitment.Expected_Total__c != null && commitment.Expected_Total__c > 0) {
                Decimal divided = commitment.Expected_Total__c / commitment.Amount__c;
                Integer rounded = divided.setScale(0, System.RoundingMode.HALF_UP).intValue();
                return Math.min(Math.max(rounded, 1), MAX_SCHEDULE_LENGTH);
            }
            return 0;
        }
        // Recurring: as many installments as fit between the start date and the horizon.
        Date horizon = Date.today().addMonths(horizonMonths());
        if (commitment.End_Date__c != null && commitment.End_Date__c < horizon) {
            horizon = commitment.End_Date__c;
        }
        Integer count = 0;
        while (count < MAX_SCHEDULE_LENGTH) {
            Date dueDate = dueDateFor(commitment, count);
            if (dueDate > horizon) {
                break;
            }
            count++;
        }
        return count;
    }

    /**
     * The date of the installment at a position in the schedule. A day of month past the
     * end of a short month falls on that month's last day, and the month after that it is
     * back where it belongs, because every date is computed from the start rather than
     * from the date before it.
     */
    @TestVisible
    private static Date dueDateFor(Commitment__c commitment, Integer index) {
        Date start = commitment.Start_Date__c;
        String frequency = commitment.Frequency__c;
        if ('Weekly'.equals(frequency)) {
            return start.addDays(7 * index);
        }
        if ('Every two weeks'.equals(frequency)) {
            return start.addDays(14 * index);
        }
        Integer monthStep = 1;
        if ('Quarterly'.equals(frequency)) {
            monthStep = 3;
        } else if ('Twice a year'.equals(frequency)) {
            monthStep = 6;
        } else if ('Yearly'.equals(frequency)) {
            monthStep = 12;
        }
        return monthlyDate(start, monthStep * index, commitment.Day_of_Month__c);
    }

    /**
     * The start date moved on by whole months, landing on the day of month asked for and
     * never past the end of a short month.
     */
    @TestVisible
    private static Date monthlyDate(Date start, Integer monthsToAdd, Decimal dayOfMonth) {
        Date firstOfMonth = Date.newInstance(start.year(), start.month(), 1).addMonths(monthsToAdd);
        Integer daysInMonth = Date.daysInMonth(firstOfMonth.year(), firstOfMonth.month());
        Integer day = dayOfMonth == null ? start.day() : dayOfMonth.intValue();
        if (day < 1) {
            day = 1;
        }
        return Date.newInstance(
            firstOfMonth.year(),
            firstOfMonth.month(),
            Math.min(day, daysInMonth)
        );
    }

    // ------------------------------------------------------------------- generation

    /**
     * Fills in the installments a commitment is missing and leaves every existing one
     * alone, including one a person has edited (R-IN1). Safe to run repeatedly.
     */
    public static void generateInstallments(Set<Id> commitmentIds) {
        applySchedule(commitmentIds, false);
    }

    /**
     * Rebuilds the installments that are still unpaid, because the amount, the frequency,
     * the day of month, or the end date changed (R-CM6). Paid and partly paid rows are
     * never rewritten, because a gift already refers to them.
     */
    public static void regenerateFutureInstallments(Set<Id> commitmentIds) {
        applySchedule(commitmentIds, true);
    }

    private static void applySchedule(Set<Id> commitmentIds, Boolean rewriteUnpaid) {
        if (commitmentIds == null || commitmentIds.isEmpty()) {
            return;
        }
        List<Commitment__c> commitments = new CommitmentSelector().selectByIds(commitmentIds);
        Map<Id, List<Installment__c>> existingByCommitment = groupByCommitment(
            new InstallmentSelector().selectByCommitmentIds(commitmentIds)
        );

        List<Installment__c> toInsert = new List<Installment__c>();
        List<Installment__c> toUpdate = new List<Installment__c>();
        List<Installment__c> toDelete = new List<Installment__c>();

        for (Commitment__c commitment : commitments) {
            if (
                STATUS_CANCELLED.equals(commitment.Status__c) ||
                STATUS_PAUSED.equals(commitment.Status__c)
            ) {
                continue;
            }
            List<Installment__c> plan = buildSchedule(commitment);
            Map<Decimal, Installment__c> existingBySequence = new Map<Decimal, Installment__c>();
            List<Installment__c> existing = existingByCommitment.get(commitment.Id);
            if (existing != null) {
                for (Installment__c installment : existing) {
                    existingBySequence.put(installment.Sequence__c, installment);
                }
            }
            for (Installment__c planned : plan) {
                Installment__c current = existingBySequence.remove(planned.Sequence__c);
                if (current == null) {
                    toInsert.add(planned);
                    continue;
                }
                if (!rewriteUnpaid || !isUnpaid(current)) {
                    continue;
                }
                if (
                    current.Due_Date__c != planned.Due_Date__c ||
                    current.Expected_Amount__c != planned.Expected_Amount__c
                ) {
                    current.Due_Date__c = planned.Due_Date__c;
                    current.Expected_Amount__c = planned.Expected_Amount__c;
                    toUpdate.add(current);
                }
            }
            // Anything left over sits beyond the schedule the commitment now implies.
            for (Installment__c leftOver : existingBySequence.values()) {
                if (rewriteUnpaid && isUnpaid(leftOver)) {
                    toDelete.add(leftOver);
                }
            }
        }

        if (!toInsert.isEmpty()) {
            Database.insert(toInsert, true, AccessLevel.USER_MODE);
        }
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, true, AccessLevel.USER_MODE);
        }
        if (!toDelete.isEmpty()) {
            Database.delete(toDelete, true, AccessLevel.USER_MODE);
        }
    }

    /**
     * Extends the schedules of active recurring commitments up to the horizon, and is what
     * the daily job calls.
     */
    public static Integer topUpRecurringSchedules() {
        List<Commitment__c> commitments = new CommitmentSelector()
            .selectActiveRecurring(MAX_TOP_UP_COMMITMENTS);
        Set<Id> commitmentIds = new Map<Id, Commitment__c>(commitments).keySet();
        generateInstallments(commitmentIds);
        return commitmentIds.size();
    }

    // ------------------------------------------------------------ gift application

    /**
     * Applies received gifts to the commitment they pay: links a gift that names only a
     * commitment to that commitment's earliest unpaid installment (R-IN3), then sets each
     * touched installment's status from the gifts against it (R-IN2), then completes a
     * pledge that is fully paid (R-CM4).
     */
    public static void applyGift(List<Gift__c> gifts) {
        if (gifts == null || gifts.isEmpty()) {
            return;
        }
        Set<Id> commitmentIds = new Set<Id>();
        Set<Id> installmentIds = new Set<Id>();
        List<Gift__c> awaitingInstallment = new List<Gift__c>();

        for (Gift__c gift : gifts) {
            if (gift.Commitment__c != null) {
                commitmentIds.add(gift.Commitment__c);
            }
            if (gift.Installment__c != null) {
                installmentIds.add(gift.Installment__c);
            } else if (
                gift.Commitment__c != null && !giftsLinkedThisTransaction.contains(gift.Id)
            ) {
                awaitingInstallment.add(gift);
            }
        }

        if (!awaitingInstallment.isEmpty() && autoApplyGifts()) {
            installmentIds.addAll(linkToEarliestUnpaid(awaitingInstallment));
        }

        refreshInstallmentStatuses(installmentIds);
        completeFullyPaidPledges(commitmentIds);
    }

    /**
     * Links each gift to the earliest installment of its commitment that is not yet paid,
     * and returns the installments it touched.
     */
    private static Set<Id> linkToEarliestUnpaid(List<Gift__c> gifts) {
        Set<Id> commitmentIds = new Set<Id>();
        for (Gift__c gift : gifts) {
            commitmentIds.add(gift.Commitment__c);
        }
        Map<Id, List<Installment__c>> byCommitment = groupByCommitment(
            new InstallmentSelector().selectByCommitmentIds(commitmentIds)
        );

        Set<Id> touched = new Set<Id>();
        Set<Id> claimed = new Set<Id>();
        List<Gift__c> updates = new List<Gift__c>();
        for (Gift__c gift : gifts) {
            List<Installment__c> candidates = byCommitment.get(gift.Commitment__c);
            if (candidates == null) {
                continue;
            }
            for (Installment__c candidate : candidates) {
                Boolean open =
                    INSTALLMENT_SCHEDULED.equals(candidate.Status__c) ||
                    INSTALLMENT_OVERDUE.equals(candidate.Status__c) ||
                    INSTALLMENT_PARTIALLY_PAID.equals(candidate.Status__c);
                if (!open || claimed.contains(candidate.Id)) {
                    continue;
                }
                claimed.add(candidate.Id);
                touched.add(candidate.Id);
                updates.add(new Gift__c(Id = gift.Id, Installment__c = candidate.Id));
                giftsLinkedThisTransaction.add(gift.Id);
                break;
            }
        }
        if (!updates.isEmpty()) {
            Database.update(updates, true, AccessLevel.USER_MODE);
        }
        return touched;
    }

    /**
     * Sets each installment's status from the received gifts linked to it. Skipped is left
     * alone, because it is the one status only a person sets.
     */
    public static void refreshInstallmentStatuses(Set<Id> installmentIds) {
        if (installmentIds == null || installmentIds.isEmpty()) {
            return;
        }
        InstallmentSelector selector = new InstallmentSelector();
        Map<Id, Decimal> paidByInstallment = selector.sumReceivedGifts(installmentIds);
        Date cutoff = Date.today().addDays(-graceDays());
        List<Installment__c> changed = new List<Installment__c>();
        for (Installment__c installment : selector.selectByIds(installmentIds)) {
            if (INSTALLMENT_SKIPPED.equals(installment.Status__c)) {
                continue;
            }
            Decimal paid = paidByInstallment.get(installment.Id);
            String status = statusFor(installment, paid == null ? 0 : paid, cutoff);
            if (!status.equals(installment.Status__c)) {
                installment.Status__c = status;
                changed.add(installment);
            }
        }
        if (!changed.isEmpty()) {
            Database.update(changed, true, AccessLevel.USER_MODE);
        }
    }

    @TestVisible
    private static String statusFor(Installment__c installment, Decimal paid, Date cutoff) {
        Decimal expected = installment.Expected_Amount__c == null
            ? 0
            : installment.Expected_Amount__c;
        if (expected > 0 && paid >= expected) {
            return INSTALLMENT_PAID;
        }
        if (paid > 0) {
            return INSTALLMENT_PARTIALLY_PAID;
        }
        if (installment.Due_Date__c != null && installment.Due_Date__c < cutoff) {
            return INSTALLMENT_OVERDUE;
        }
        return INSTALLMENT_SCHEDULED;
    }

    /**
     * A pledge whose received gifts reach its expected total is Completed (R-CM4). A
     * recurring commitment is never completed automatically.
     */
    private static void completeFullyPaidPledges(Set<Id> commitmentIds) {
        if (commitmentIds == null || commitmentIds.isEmpty()) {
            return;
        }
        CommitmentSelector selector = new CommitmentSelector();
        Map<Id, Decimal> paidByCommitment = selector.sumReceivedGifts(commitmentIds);
        List<Commitment__c> changed = new List<Commitment__c>();
        for (Commitment__c commitment : selector.selectByIds(commitmentIds)) {
            if (
                !TYPE_PLEDGE.equals(commitment.Type__c) ||
                !STATUS_ACTIVE.equals(commitment.Status__c)
            ) {
                continue;
            }
            if (commitment.Expected_Total__c == null || commitment.Expected_Total__c <= 0) {
                continue;
            }
            Decimal paid = paidByCommitment.get(commitment.Id);
            if (paid != null && paid >= commitment.Expected_Total__c) {
                changed.add(new Commitment__c(Id = commitment.Id, Status__c = STATUS_COMPLETED));
            }
        }
        if (!changed.isEmpty()) {
            Database.update(changed, true, AccessLevel.USER_MODE);
        }
    }

    // ------------------------------------------------------------------- overdue job

    /**
     * Marks unpaid installments Overdue once their due date is further in the past than the
     * org's grace period, and is what the daily job calls. Returns how many changed.
     */
    public static Integer markOverdue() {
        Date cutoff = Date.today().addDays(-graceDays());
        List<Installment__c> candidates = new InstallmentSelector()
            .selectUnpaidDueBefore(cutoff, MAX_OVERDUE_ROWS);
        if (candidates.isEmpty()) {
            return 0;
        }
        Set<Id> installmentIds = new Map<Id, Installment__c>(candidates).keySet();
        Map<Id, Decimal> paidByInstallment = new InstallmentSelector()
            .sumReceivedGifts(installmentIds);
        List<Installment__c> changed = new List<Installment__c>();
        for (Installment__c installment : candidates) {
            Decimal paid = paidByInstallment.get(installment.Id);
            String status = statusFor(installment, paid == null ? 0 : paid, cutoff);
            if (!status.equals(installment.Status__c)) {
                installment.Status__c = status;
                changed.add(installment);
            }
        }
        if (!changed.isEmpty()) {
            Database.update(changed, true, AccessLevel.USER_MODE);
        }
        return changed.size();
    }

    // ------------------------------------------------------------------ transitions

    /** Stops generation and leaves the installments already scheduled where they are. */
    public static void pause(Set<Id> commitmentIds) {
        transition(commitmentIds, STATUS_PAUSED, new Set<String>{ STATUS_ACTIVE });
    }

    /** Starts generation again and fills in whatever the pause left missing. */
    public static void resume(Set<Id> commitmentIds) {
        transition(commitmentIds, STATUS_ACTIVE, new Set<String>{ STATUS_PAUSED });
        generateInstallments(commitmentIds);
    }

    /** Stops generation and marks the unpaid installments Skipped (R-CM3). */
    public static void cancel(Set<Id> commitmentIds) {
        transition(
            commitmentIds,
            STATUS_CANCELLED,
            new Set<String>{ STATUS_ACTIVE, STATUS_PAUSED }
        );
        skipUnpaidInstallments(commitmentIds);
    }

    /** Ends a commitment that has been paid in full or that staff consider finished. */
    public static void complete(Set<Id> commitmentIds) {
        transition(
            commitmentIds,
            STATUS_COMPLETED,
            new Set<String>{ STATUS_ACTIVE, STATUS_PAUSED }
        );
    }

    private static void transition(Set<Id> commitmentIds, String target, Set<String> allowedFrom) {
        if (commitmentIds == null || commitmentIds.isEmpty()) {
            return;
        }
        List<Commitment__c> changed = new List<Commitment__c>();
        for (Commitment__c commitment : new CommitmentSelector().selectByIds(commitmentIds)) {
            if (target.equals(commitment.Status__c)) {
                continue;
            }
            if (!allowedFrom.contains(commitment.Status__c)) {
                throw new CommitmentException(System.Label.Giving_Commitment_TransitionNotAllowed);
            }
            changed.add(new Commitment__c(Id = commitment.Id, Status__c = target));
        }
        if (!changed.isEmpty()) {
            Database.update(changed, true, AccessLevel.USER_MODE);
        }
    }

    private static void skipUnpaidInstallments(Set<Id> commitmentIds) {
        List<Installment__c> changed = new List<Installment__c>();
        for (
            Installment__c installment : new InstallmentSelector()
                .selectByCommitmentIds(commitmentIds)
        ) {
            if (isUnpaid(installment)) {
                installment.Status__c = INSTALLMENT_SKIPPED;
                changed.add(installment);
            }
        }
        if (!changed.isEmpty()) {
            Database.update(changed, true, AccessLevel.USER_MODE);
        }
    }

    /**
     * Records when the top up job last finished, which is what the Hub shows.
     */
    public static void recordTopUpRun(Datetime completedAt) {
        Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
        settings.Installment_Top_Up_Last_Run__c = completedAt;
        List<Giving_Settings__c> records = new List<Giving_Settings__c>{ settings };
        if (settings.Id == null) {
            settings.SetupOwnerId = UserInfo.getOrganizationId();
            Database.insert(records, true, AccessLevel.USER_MODE);
        } else {
            Database.update(records, true, AccessLevel.USER_MODE);
        }
    }

    // ---------------------------------------------------------------------- helpers

    /** True when nothing has been received against this installment. */
    @TestVisible
    private static Boolean isUnpaid(Installment__c installment) {
        if (
            INSTALLMENT_PAID.equals(installment.Status__c) ||
            INSTALLMENT_PARTIALLY_PAID.equals(installment.Status__c)
        ) {
            return false;
        }
        return installment.Paid_Amount__c == null || installment.Paid_Amount__c == 0;
    }

    private static Map<Id, List<Installment__c>> groupByCommitment(
        List<Installment__c> installments
    ) {
        Map<Id, List<Installment__c>> grouped = new Map<Id, List<Installment__c>>();
        for (Installment__c installment : installments) {
            if (!grouped.containsKey(installment.Commitment__c)) {
                grouped.put(installment.Commitment__c, new List<Installment__c>());
            }
            grouped.get(installment.Commitment__c).add(installment);
        }
        return grouped;
    }

    @TestVisible
    private static Integer horizonMonths() {
        Integer months = readInteger(KEY_HORIZON);
        return months == null || months <= 0 ? DEFAULT_HORIZON_MONTHS : months;
    }

    @TestVisible
    private static Integer graceDays() {
        Integer days = readInteger(KEY_GRACE);
        return days == null || days < 0 ? DEFAULT_GRACE_DAYS : days;
    }

    @TestVisible
    private static Boolean autoApplyGifts() {
        String value = SettingsService.getValue(SETTINGS_OBJECT, KEY_AUTO_APPLY);
        return String.isBlank(value) ? true : Boolean.valueOf(value);
    }

    private static Integer readInteger(String key) {
        String value = SettingsService.getValue(SETTINGS_OBJECT, key);
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Integer.valueOf(value.trim());
        } catch (System.TypeException parseFailure) {
            ErrorLogger.log('CommitmentService.' + key, parseFailure);
            return null;
        }
    }

    /** Raised when a status change is not one the commitment allows. */
    public class CommitmentException extends Exception {
    }
}

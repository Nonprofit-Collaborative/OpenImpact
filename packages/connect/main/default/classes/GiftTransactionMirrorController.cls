/**
 * The Gift Transaction mirror page (feature X-07, R-GT5, R-GT10): says whether the mirror can work
 * in this org and for this person and what it still needs, starts Run now, schedules and stops the
 * nightly run, compares a range, and copies a range again. Every refusal is in words the page
 * shows as they are.
 */
public with sharing class GiftTransactionMirrorController {
    private static final String CONTEXT = 'GiftTransactionMirrorController';
    /**
     * Held through the Gift Transaction Mirror permission set. Reading the page's status and the
     * reconciliation needs it, as the page's entry in the settings console does (ADR-0038).
     */
    private static final String USE_PERMISSION = 'Use_Gift_Transaction_Mirror';

    /** What the page shows. */
    public class Status {
        @AuraEnabled
        public Boolean available;
        @AuraEnabled
        public String direction;
        /** The paid status as set, and the start date as a date in the org's time zone. */
        @AuraEnabled
        public String paidStatus;
        @AuraEnabled
        public Date startDate;
        /** What is still missing before anything is mirrored (R-GT2), or null when nothing is. */
        @AuraEnabled
        public String notReady;
        @AuraEnabled
        public Boolean canRun;
        @AuraEnabled
        public Boolean canManage;
        @AuraEnabled
        public Boolean running;
        @AuraEnabled
        public Datetime nextRunAt;
        /** When the last completed run started, and what it did (ADR-0038 point 4). */
        @AuraEnabled
        public Datetime lastRunAt;
        @AuraEnabled
        public String lastSummary;
    }

    @AuraEnabled
    public static Status getStatus() {
        requireUse();
        try {
            return status();
        } catch (Exception unexpected) {
            throw failed(unexpected);
        }
    }

    /** Starts a run in the chosen direction, or says in words why it cannot start. */
    @AuraEnabled
    public static Status runNow() {
        Status current = checked(false);
        try {
            GiftTransactionMirrorBatch.run();
        } catch (Exception unexpected) {
            throw failed(unexpected);
        }
        current.running = true;
        return current;
    }

    /** Copies again every gift of R-GT3 dated in the range (Gifts to Gift Transactions only). */
    @AuraEnabled
    public static Status copyRangeAgain(Date fromDate, Date toDate) {
        Status current = checked(false);
        if (current.direction != GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS) {
            throw asAuraException(Label.Connect_GiftTransactionMirror_CopyAgainGiftsOnly);
        }
        if (fromDate == null || toDate == null) {
            throw asAuraException(Label.Connect_GiftTransactionMirror_ErrorDatesRequired);
        }
        if (fromDate > toDate) {
            throw asAuraException(Label.Connect_GiftTransactionMirror_ErrorDateOrder);
        }
        try {
            GiftTransactionMirrorBatch.runRange(fromDate, toDate);
        } catch (Exception unexpected) {
            throw failed(unexpected);
        }
        current.running = true;
        return current;
    }

    /** Schedules the nightly run at 01:35, as the person clicking (ADR-0038). */
    @AuraEnabled
    public static Status schedule() {
        checked(true);
        try {
            GiftTransactionMirrorSchedulable.schedule();
            return status();
        } catch (Exception unexpected) {
            throw failed(unexpected);
        }
    }

    @AuraEnabled
    public static Status stop() {
        requireUse();
        Status current;
        try {
            current = status();
        } catch (Exception unexpected) {
            throw failed(unexpected);
        }
        if (!current.canManage) {
            throw asAuraException(Label.Connect_GiftTransactionMirror_NoManagePermission);
        }
        try {
            GiftTransactionMirrorSchedulable.stop();
            return status();
        } catch (Exception unexpected) {
            throw failed(unexpected);
        }
    }

    /** The reconciliation for a range, as the person viewing can see it (R-GT10). */
    @AuraEnabled
    public static GiftTransactionMirrorReconciliation.Comparison compare(
        Date fromDate,
        Date toDate
    ) {
        requireUse();
        try {
            return GiftTransactionMirrorReconciliation.compare(fromDate, toDate);
        } catch (GiftTransactionMirrorReconciliation.ReconciliationException refused) {
            throw asAuraException(refused.getMessage());
        } catch (Exception unexpected) {
            throw failed(unexpected);
        }
    }

    private static void requireUse() {
        if (!FeatureManagement.checkPermission(USE_PERMISSION)) {
            throw asAuraException(Label.Connect_GiftTransactionMirror_NoUsePermission);
        }
    }

    /** The current status when a run may start, or the refusal in words. */
    private static Status checked(Boolean scheduling) {
        requireUse();
        Status current;
        try {
            current = status();
        } catch (Exception unexpected) {
            throw failed(unexpected);
        }
        String refusal = refusal(current, scheduling);
        if (refusal != null) {
            throw asAuraException(refusal);
        }
        return current;
    }

    @TestVisible
    private static String refusal(Status current, Boolean scheduling) {
        if (!current.available) {
            return Label.Connect_GiftTransactionMirror_Unavailable;
        }
        if (current.direction == GiftTransactionMirrorService.OFF) {
            return Label.Connect_GiftTransactionMirror_SwitchedOff;
        }
        if (current.notReady != null) {
            return current.notReady;
        }
        if (!current.canManage) {
            return Label.Connect_GiftTransactionMirror_NoManagePermission;
        }
        if (!current.canRun) {
            return Label.Connect_GiftTransactionMirror_NoAccess;
        }
        if (current.running && !scheduling) {
            return Label.Connect_GiftTransactionMirror_Running;
        }
        return null;
    }

    private static Status status() {
        Status current = new Status();
        current.available = GiftTransactionMirrorService.isAvailable();
        current.direction = GiftTransactionMirrorService.direction();
        current.paidStatus = GiftTransactionMirrorService.paidStatus();
        current.startDate = GiftTransactionMirrorService.startDate();
        current.notReady = current.available ? GiftTransactionMirrorService.notReadyReason() : null;
        current.canManage = AutomationControl.canManage();
        current.canRun = GiftTransactionMirrorService.canRun(current.direction);
        current.running = GiftTransactionMirrorSchedulable.isRunning();
        current.nextRunAt = GiftTransactionMirrorSchedulable.nextRunAt();
        Connect_Settings__c settings = Connect_Settings__c.getOrgDefaults();
        current.lastRunAt = settings?.Gift_Transaction_Mirror_Last_Run__c;
        current.lastSummary = settings?.Gift_Transaction_Mirror_Last_Summary__c;
        return current;
    }

    private static AuraHandledException failed(Exception unexpected) {
        ErrorLogger.log(unexpected, CONTEXT);
        return asAuraException(Label.Connect_GiftTransactionMirror_ErrorFailed);
    }

    private static AuraHandledException asAuraException(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}

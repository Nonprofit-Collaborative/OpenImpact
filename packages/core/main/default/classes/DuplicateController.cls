/**
 * The Duplicates page of the Nonprofit Settings console (C-20).
 *
 * It answers the three questions an administrator has: are the duplicate rules switched on,
 * what have they found, and what do I do about each one. Everything it shows was found by the
 * platform's own rules, and the only merge it offers is the household merge C-09 already
 * ships, called one pair at a time with a person confirming it (canonical model R-DP4).
 *
 * Who may do what. Starting a scan and dismissing a suggestion are configuration actions and
 * need `Manage_Nonprofit_Settings`. Merging does not: it is data cleanup, and the household
 * merge service checks record level edit access on both households itself, which is the check
 * that matters and the one sharing honors.
 */
public with sharing class DuplicateController {
    private static final String EDIT_PERMISSION = 'Manage_Nonprofit_Settings';
    private static final String SCAN_CLASS = 'DuplicateScanBatch';
    private static final Integer MAX_SUGGESTIONS = 50;
    private static final String STATUS_COMPLETED = 'Completed';

    /** One of the records in a suggestion, as the page shows it. */
    public class RecordView {
        @AuraEnabled
        public Id recordId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String detail;
        @AuraEnabled
        public String objectLabel;
        @AuraEnabled
        public Boolean isHousehold;
    }

    /** One suggestion: two or more records the platform says are the same thing. */
    public class SuggestionView {
        @AuraEnabled
        public Id setId;
        @AuraEnabled
        public Datetime foundAt;
        @AuraEnabled
        public String ruleLabel;
        @AuraEnabled
        public List<RecordView> records = new List<RecordView>();
        @AuraEnabled
        public Boolean canMerge = false;
    }

    /** One duplicate rule and whether it is switched on. */
    public class RuleView {
        @AuraEnabled
        public String objectLabel;
        @AuraEnabled
        public String ruleLabel;
        @AuraEnabled
        public Boolean active;
        @AuraEnabled
        public Boolean shippedByOpenImpact;
    }

    /** The whole page, in one round trip. */
    public class DuplicateView {
        @AuraEnabled
        public Boolean canManage;
        @AuraEnabled
        public Boolean anyRuleActive;
        @AuraEnabled
        public List<RuleView> rules = new List<RuleView>();
        @AuraEnabled
        public List<SuggestionView> suggestions = new List<SuggestionView>();
        @AuraEnabled
        public Integer dismissedCount = 0;
        @AuraEnabled
        public Boolean scanRunning = false;
        @AuraEnabled
        public Datetime lastScanFinished;
    }

    @AuraEnabled(cacheable=true)
    public static DuplicateView getView() {
        try {
            return currentView();
        } catch (Exception caught) {
            throw asUserError(caught, 'Duplicates page');
        }
    }

    /**
     * Starts a scan of the records already in the org, and answers with the page as it now
     * stands. Refused when no duplicate rule is active, because a scan would then report a
     * clean org rather than an org nobody is checking.
     */
    @AuraEnabled
    public static DuplicateView startScan() {
        try {
            requirePermission();
            Id jobId = DuplicateScanBatch.start();
            if (jobId == null) {
                throw new DuplicateService.DuplicateException(
                    Label.Core_Duplicates_ErrorNoActiveRule
                );
            }
            return currentView();
        } catch (Exception caught) {
            throw asUserError(caught, 'Start a duplicate scan');
        }
    }

    /** Records that these records are not duplicates of each other, and takes the suggestion away. */
    @AuraEnabled
    public static DuplicateView dismiss(Id duplicateRecordSetId, String reason) {
        try {
            requirePermission();
            DuplicateService.dismiss(duplicateRecordSetId, reason);
            return currentView();
        } catch (Exception caught) {
            throw asUserError(caught, 'Dismiss a duplicate suggestion');
        }
    }

    /** The two households side by side, from the merge screen's own comparison (C-09). */
    @AuraEnabled
    public static HouseholdMergeService.MergePreview previewMerge(Id survivorId, Id victimId) {
        try {
            return HouseholdMergeService.preview(survivorId, victimId);
        } catch (Exception caught) {
            throw asUserError(caught, 'Preview a household merge from the Duplicates page');
        }
    }

    /**
     * Merges the two households and takes the suggestion away.
     *
     * The merge itself is C-09's, unchanged: the members move, the survivor keeps its own
     * values unless the person chose otherwise, and the platform merge carries everything
     * hanging off the household that goes away. Nothing here merges in bulk and nothing here
     * merges without a person pressing the button (R-DP4).
     */
    @AuraEnabled
    public static DuplicateView mergeHouseholds(
        Id duplicateRecordSetId,
        Id survivorId,
        Id victimId,
        Map<String, String> fieldChoices
    ) {
        try {
            HouseholdMergeService.mergeHouseholds(
                survivorId,
                victimId,
                new HouseholdMergeService.MergeChoices(fieldChoices)
            );
            DuplicateService.closeSet(duplicateRecordSetId);
            return currentView();
        } catch (Exception caught) {
            throw asUserError(caught, 'Merge two households from the Duplicates page');
        }
    }

    // ------------------------------------------------------------------ the view

    private static DuplicateView currentView() {
        DuplicateView view = new DuplicateView();
        view.canManage = canManage();
        view.rules = rules();
        for (RuleView rule : view.rules) {
            view.anyRuleActive = view.anyRuleActive == true || rule.active == true;
        }
        view.anyRuleActive = view.anyRuleActive == true;
        view.dismissedCount = DuplicateSelector.dismissalCount();
        addScanState(view);
        view.suggestions = suggestions();
        return view;
    }

    private static List<RuleView> rules() {
        List<RuleView> result = new List<RuleView>();
        Set<String> shipped = new Set<String>{
            DuplicateSelector.CONTACT_RULE,
            DuplicateSelector.HOUSEHOLD_RULE
        };
        for (
            DuplicateRule rule : DuplicateSelector.rulesFor(
                new Set<String>(DuplicateScanBatch.SCANNED_OBJECTS)
            )
        ) {
            RuleView view = new RuleView();
            view.objectLabel = rule.SobjectType;
            view.ruleLabel = rule.MasterLabel;
            view.active = rule.IsActive;
            view.shippedByOpenImpact = shipped.contains(rule.DeveloperName);
            result.add(view);
        }
        return result;
    }

    private static void addScanState(DuplicateView view) {
        for (AsyncApexJob job : DuplicateSelector.recentScanJobs(SCAN_CLASS, 5)) {
            if (job.CompletedDate != null && view.lastScanFinished == null) {
                view.lastScanFinished = job.CompletedDate;
            }
            if (job.Status != STATUS_COMPLETED && job.Status != 'Failed' && job.Status != 'Aborted') {
                view.scanRunning = true;
            }
        }
    }

    /**
     * The suggestions, with the records in them named. A suggestion naming a record the person
     * cannot see, or one that has since been deleted, is left out rather than shown with a
     * hole in it: half a pair is not something anybody can make a decision about.
     */
    private static List<SuggestionView> suggestions() {
        List<DuplicateRecordSet> sets = DuplicateSelector.openSets(MAX_SUGGESTIONS);
        Set<Id> recordIds = new Set<Id>();
        for (DuplicateRecordSet found : sets) {
            for (DuplicateRecordItem item : found.DuplicateRecordItems) {
                recordIds.add(item.RecordId);
            }
        }
        Map<Id, RecordView> byRecord = describeRecords(recordIds);

        List<SuggestionView> result = new List<SuggestionView>();
        for (DuplicateRecordSet found : sets) {
            SuggestionView view = new SuggestionView();
            view.setId = found.Id;
            view.foundAt = found.CreatedDate;
            view.ruleLabel = found.DuplicateRule == null ? null : found.DuplicateRule.MasterLabel;
            Boolean complete = !found.DuplicateRecordItems.isEmpty();
            for (DuplicateRecordItem item : found.DuplicateRecordItems) {
                RecordView record = byRecord.get(item.RecordId);
                if (record == null) {
                    complete = false;
                    break;
                }
                view.records.add(record);
            }
            if (!complete) {
                continue;
            }
            view.canMerge =
                view.records.size() == 2 &&
                view.records[0].isHousehold == true &&
                view.records[1].isHousehold == true;
            result.add(view);
        }
        return result;
    }

    private static Map<Id, RecordView> describeRecords(Set<Id> recordIds) {
        Map<Id, RecordView> result = new Map<Id, RecordView>();
        Set<Id> accountIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        for (Id recordId : recordIds) {
            Schema.SObjectType type = recordId.getSObjectType();
            if (type == Account.SObjectType) {
                accountIds.add(recordId);
            } else if (type == Contact.SObjectType) {
                contactIds.add(recordId);
            }
        }
        Id householdRecordTypeId = HouseholdService.householdRecordTypeId();
        for (Account account : DuplicateSelector.accountsByIds(accountIds)) {
            RecordView view = new RecordView();
            view.recordId = account.Id;
            view.name = account.Name;
            view.detail = place(account.BillingCity, account.BillingPostalCode);
            view.isHousehold =
                householdRecordTypeId != null &&
                account.RecordTypeId == householdRecordTypeId;
            view.objectLabel = view.isHousehold
                ? Label.Core_Duplicates_ObjectHousehold
                : Label.Core_Duplicates_ObjectOrganization;
            result.put(account.Id, view);
        }
        for (Contact contact : DuplicateSelector.contactsByIds(contactIds)) {
            RecordView view = new RecordView();
            view.recordId = contact.Id;
            view.name = contact.Name;
            view.detail = String.isNotBlank(contact.Email)
                ? contact.Email
                : place(contact.Account == null ? null : contact.Account.Name, contact.MailingPostalCode);
            view.objectLabel = Label.Core_Duplicates_ObjectPerson;
            view.isHousehold = false;
            result.put(contact.Id, view);
        }
        return result;
    }

    private static String place(String first, String second) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(first)) {
            parts.add(first);
        }
        if (String.isNotBlank(second)) {
            parts.add(second);
        }
        return String.join(parts, ', ');
    }

    // ------------------------------------------------------------------ helpers

    private static Boolean canManage() {
        return FeatureManagement.checkPermission(EDIT_PERMISSION);
    }

    private static void requirePermission() {
        if (!canManage()) {
            throw new DuplicateService.DuplicateException(
                Label.Core_Duplicates_ErrorPermissionRequired
            );
        }
    }

    /**
     * Anything the person can act on is shown as it is. Anything else is logged with the
     * record it happened on and answered with one sentence, because a stack trace in a toast
     * helps nobody (plan Section 7.2).
     */
    private static AuraHandledException asUserError(Exception caught, String context) {
        String message = caught.getMessage();
        Boolean expected =
            caught instanceof DuplicateService.DuplicateException ||
            caught instanceof HouseholdException;
        if (!expected) {
            ErrorLogger.log(caught, context);
            message = Label.Core_Duplicates_ErrorUnexpected;
        }
        AuraHandledException reported = new AuraHandledException(message);
        reported.setMessage(message);
        return reported;
    }
}

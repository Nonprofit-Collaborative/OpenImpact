/**
 * Gift batch entry (G-17).
 *
 * Serves the `giftBatchEntry` component: the defaults a batch starts from, the open batches a
 * person can resume, the saving of what has been typed so far, and the post. Every rule lives in
 * `GiftBatchService`; this class validates what arrived from the browser, shapes it for the
 * component, and keeps unexpected failures out of the person's face (plan Section 2.3).
 *
 * Rows are saved as they are typed rather than at the end, which is what makes an open batch
 * survive the browser being closed. A person who is interrupted halfway down a pile of checks
 * comes back to the pile.
 */
public with sharing class GiftBatchController {
    private static final String CONTEXT = 'GiftBatchController';

    /** What a new batch starts from. */
    public class BatchDefaults {
        @AuraEnabled
        public Date giftDate;
        @AuraEnabled
        public Boolean hasPersonAccounts = false;
        @AuraEnabled
        public String defaultFundId;
        @AuraEnabled
        public String defaultAppealId;
        @AuraEnabled
        public List<PicklistOption> paymentMethods = new List<PicklistOption>();
    }

    /** One choice in the "How it arrived" list. */
    public class PicklistOption {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;

        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    /** One open batch in the "pick up where you left off" list. */
    public class BatchSummary {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public Decimal controlTotal;
        @AuraEnabled
        public Datetime lastModified;

        public BatchSummary(Gift_Batch__c batch) {
            this.id = batch.Id;
            this.name = batch.Name;
            this.description = batch.Description__c;
            this.controlTotal = batch.Control_Total__c;
            this.lastModified = batch.LastModifiedDate;
        }
    }

    /** One line, as the grid holds it. */
    public class RowView {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public Integer rowNumber;
        @AuraEnabled
        public String donorContactId;
        @AuraEnabled
        public String donorAccountId;
        @AuraEnabled
        public Decimal amount;
        @AuraEnabled
        public Date giftDate;
        @AuraEnabled
        public String fundId;
        @AuraEnabled
        public String appealId;
        @AuraEnabled
        public String paymentMethod;
        @AuraEnabled
        public String paymentReference;
        @AuraEnabled
        public String giftId;

        public RowView(Gift_Batch_Row__c row) {
            this.id = row.Id;
            this.rowNumber = row.Row_Number__c == null ? null : row.Row_Number__c.intValue();
            this.donorContactId = row.Donor_Contact__c;
            this.donorAccountId = row.Donor_Account__c;
            this.amount = row.Amount__c;
            this.giftDate = row.Gift_Date__c;
            this.fundId = row.Fund__c;
            this.appealId = row.Appeal__c;
            this.paymentMethod = row.Payment_Method__c;
            this.paymentReference = row.Payment_Reference__c;
            this.giftId = row.Gift__c;
        }
    }

    /** A batch and everything the screen needs to draw it, including the three totals. */
    public class BatchView {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public Decimal controlTotal;
        @AuraEnabled
        public Decimal enteredTotal;
        @AuraEnabled
        public Decimal difference;
        @AuraEnabled
        public Date defaultGiftDate;
        @AuraEnabled
        public String defaultFundId;
        @AuraEnabled
        public String defaultAppealId;
        @AuraEnabled
        public String defaultPaymentMethod;
        @AuraEnabled
        public Datetime postedAt;
        @AuraEnabled
        public Integer giftCount;
        @AuraEnabled
        public List<RowView> rows = new List<RowView>();
    }

    /** The header, as the browser sends it. */
    public class BatchInput {
        @AuraEnabled
        public String description;
        @AuraEnabled
        public Decimal controlTotal;
        @AuraEnabled
        public Date defaultGiftDate;
        @AuraEnabled
        public String defaultFundId;
        @AuraEnabled
        public String defaultAppealId;
        @AuraEnabled
        public String defaultPaymentMethod;
    }

    /** One line, as the browser sends it. */
    public class RowInput {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public Integer rowNumber;
        @AuraEnabled
        public String donorContactId;
        @AuraEnabled
        public String donorAccountId;
        @AuraEnabled
        public Decimal amount;
        @AuraEnabled
        public String fundId;
        @AuraEnabled
        public String paymentReference;
    }

    /** One message the component shows beside one line. */
    public class RowError {
        @AuraEnabled
        public String rowId;
        @AuraEnabled
        public Integer rowNumber;
        @AuraEnabled
        public String message;

        public RowError(GiftBatchService.RowProblem problem) {
            this.rowId = problem.rowId;
            this.rowNumber = problem.rowNumber;
            this.message = problem.message;
        }
    }

    /** What came of a post. */
    public class PostResult {
        @AuraEnabled
        public Boolean success = false;
        @AuraEnabled
        public Integer giftCount = 0;
        @AuraEnabled
        public String formError;
        @AuraEnabled
        public List<RowError> rowErrors = new List<RowError>();
    }

    /**
     * The values a new batch starts from: today, the org's default fund and appeal, the payment
     * methods, and whether people in this org are accounts rather than contacts.
     */
    @AuraEnabled(cacheable=true)
    public static BatchDefaults getDefaults() {
        try {
            BatchDefaults defaults = new BatchDefaults();
            defaults.giftDate = Date.today();
            defaults.hasPersonAccounts = OrgShapeDetector.detect().hasPersonAccounts;
            defaults.paymentMethods = paymentMethodOptions();
            Nonprofit_Settings__c settings = SettingsService.getSettings();
            Id fundId = asId(settings.Default_Fund__c, Fund__c.SObjectType);
            defaults.defaultFundId = fundId == null
                ? GiftService.resolveDefaultFundId()
                : fundId;
            defaults.defaultAppealId = asId(settings.Default_Appeal__c, Appeal__c.SObjectType);
            return defaults;
        } catch (Exception e) {
            ErrorLogger.log(e, CONTEXT + '.getDefaults');
            throw asAuraException(Label.Giving_GiftBatch_ErrorLoadDefaults);
        }
    }

    /** The batches still open, so an interrupted person finds their pile again. */
    @AuraEnabled
    public static List<BatchSummary> listOpenBatches() {
        try {
            List<BatchSummary> summaries = new List<BatchSummary>();
            for (Gift_Batch__c batch : GiftBatchSelector.selectOpen()) {
                summaries.add(new BatchSummary(batch));
            }
            return summaries;
        } catch (Exception e) {
            ErrorLogger.log(e, CONTEXT + '.listOpenBatches');
            throw asAuraException(Label.Giving_GiftBatch_ErrorLoadBatches);
        }
    }

    /** Starts a batch. It exists as a record from this moment, which is the point. */
    @AuraEnabled
    public static BatchView createBatch(BatchInput input) {
        try {
            Gift_Batch__c batch = new Gift_Batch__c(Status__c = GiftBatchService.STATUS_OPEN);
            applyHeader(batch, input);
            Database.insert(batch, true, AccessLevel.USER_MODE);
            return view(batch.Id);
        } catch (Exception e) {
            ErrorLogger.log(e, CONTEXT + '.createBatch');
            throw asAuraException(messageFor(e, Label.Giving_GiftBatch_ErrorSaveBatch));
        }
    }

    /** One batch and its lines, for opening or resuming it. */
    @AuraEnabled
    public static BatchView getBatch(Id batchId) {
        try {
            return view(batchId);
        } catch (Exception e) {
            ErrorLogger.log(e, CONTEXT + '.getBatch', batchId);
            throw asAuraException(Label.Giving_GiftBatch_ErrorLoadBatch);
        }
    }

    /** The header: the control total from the deposit slip, and the defaults the lines inherit. */
    @AuraEnabled
    public static BatchView saveBatch(Id batchId, BatchInput input) {
        try {
            Gift_Batch__c batch = loadOpenBatch(batchId);
            applyHeader(batch, input);
            Database.update(batch, true, AccessLevel.USER_MODE);
            return view(batchId);
        } catch (Exception e) {
            ErrorLogger.log(e, CONTEXT + '.saveBatch', batchId);
            throw asAuraException(messageFor(e, Label.Giving_GiftBatch_ErrorSaveBatch));
        }
    }

    /**
     * Saves what has been typed. The whole grid is sent, so a line that was changed, a line that
     * was added and a line that was removed all arrive together and are saved in one transaction:
     * the batch is never half saved.
     *
     * The batch's defaults are applied here rather than in the browser (R-GB1), so a line saved by
     * any other route gets them too, and the totals the caller gets back are the server's.
     */
    @AuraEnabled
    public static BatchView saveRows(Id batchId, List<RowInput> rows, List<String> removedRowIds) {
        try {
            Gift_Batch__c batch = loadOpenBatch(batchId);
            List<Gift_Batch_Row__c> records = new List<Gift_Batch_Row__c>();
            for (RowInput row : rows == null ? new List<RowInput>() : rows) {
                records.add(toRow(batchId, row));
            }
            GiftBatchService.applyDefaults(batch, records);
            if (!records.isEmpty()) {
                Database.upsert(records, true, AccessLevel.USER_MODE);
            }
            deleteRows(batchId, removedRowIds);
            return view(batchId);
        } catch (Exception e) {
            ErrorLogger.log(e, CONTEXT + '.saveRows', batchId);
            throw asAuraException(messageFor(e, Label.Giving_GiftBatch_ErrorSaveRows));
        }
    }

    /**
     * Posts the batch. Everything that decides whether it may be posted is in the service, inside
     * one transaction with the insert of the gifts, so this method only reports what happened.
     */
    @AuraEnabled
    public static PostResult postBatch(Id batchId) {
        PostResult result = new PostResult();
        GiftBatchService.PostOutcome outcome = GiftBatchService.post(batchId);
        result.success = outcome.success;
        result.giftCount = outcome.giftCount;
        result.formError = outcome.formError;
        for (GiftBatchService.RowProblem problem : outcome.rowProblems) {
            result.rowErrors.add(new RowError(problem));
        }
        return result;
    }

    private static void applyHeader(Gift_Batch__c batch, BatchInput input) {
        if (input == null) {
            return;
        }
        batch.Description__c = input.description;
        batch.Control_Total__c = input.controlTotal;
        batch.Default_Gift_Date__c = input.defaultGiftDate;
        batch.Default_Fund__c = asId(input.defaultFundId, Fund__c.SObjectType);
        batch.Default_Appeal__c = asId(input.defaultAppealId, Appeal__c.SObjectType);
        batch.Default_Payment_Method__c = paymentMethodOrNull(input.defaultPaymentMethod);
    }

    private static Gift_Batch_Row__c toRow(Id batchId, RowInput input) {
        return new Gift_Batch_Row__c(
            Id = asId(input.id, Gift_Batch_Row__c.SObjectType),
            Gift_Batch__c = batchId,
            Row_Number__c = input.rowNumber,
            Donor_Contact__c = asId(input.donorContactId, Contact.SObjectType),
            Donor_Account__c = asId(input.donorAccountId, Account.SObjectType),
            Amount__c = input.amount,
            Fund__c = asId(input.fundId, Fund__c.SObjectType),
            Payment_Reference__c = input.paymentReference
        );
    }

    /**
     * A line the person took off the grid. Only lines that belong to this batch are deleted, so a
     * browser cannot ask for anything else to go.
     */
    private static void deleteRows(Id batchId, List<String> removedRowIds) {
        if (removedRowIds == null || removedRowIds.isEmpty()) {
            return;
        }
        Set<Id> wanted = new Set<Id>();
        for (String value : removedRowIds) {
            Id rowId = asId(value, Gift_Batch_Row__c.SObjectType);
            if (rowId != null) {
                wanted.add(rowId);
            }
        }
        if (wanted.isEmpty()) {
            return;
        }
        List<Gift_Batch_Row__c> doomed = new List<Gift_Batch_Row__c>();
        for (Gift_Batch_Row__c row : GiftBatchSelector.selectRows(batchId)) {
            if (wanted.contains(row.Id)) {
                doomed.add(row);
            }
        }
        if (!doomed.isEmpty()) {
            Database.delete(doomed, true, AccessLevel.USER_MODE);
        }
    }

    /** A batch that has posted is finished, so nothing the screen sends reaches it. */
    private static Gift_Batch__c loadOpenBatch(Id batchId) {
        List<Gift_Batch__c> batches = GiftBatchSelector.selectById(new Set<Id>{ batchId });
        if (batches.isEmpty()) {
            throw new GiftBatchService.GiftBatchException(
                Label.Giving_GiftBatch_ErrorBatchMissing
            );
        }
        if (GiftBatchService.STATUS_POSTED.equals(batches[0].Status__c)) {
            throw new GiftBatchService.GiftBatchException(
                Label.Giving_GiftBatch_ErrorEditAfterPost
            );
        }
        return batches[0];
    }

    private static BatchView view(Id batchId) {
        List<Gift_Batch__c> batches = GiftBatchSelector.selectById(new Set<Id>{ batchId });
        if (batches.isEmpty()) {
            throw new GiftBatchService.GiftBatchException(
                Label.Giving_GiftBatch_ErrorBatchMissing
            );
        }
        Gift_Batch__c batch = batches[0];
        BatchView result = new BatchView();
        result.id = batch.Id;
        result.name = batch.Name;
        result.description = batch.Description__c;
        result.status = batch.Status__c;
        result.controlTotal = batch.Control_Total__c;
        result.defaultGiftDate = batch.Default_Gift_Date__c;
        result.defaultFundId = batch.Default_Fund__c;
        result.defaultAppealId = batch.Default_Appeal__c;
        result.defaultPaymentMethod = batch.Default_Payment_Method__c;
        result.postedAt = batch.Posted_At__c;
        result.giftCount = batch.Gift_Count__c == null ? null : batch.Gift_Count__c.intValue();
        for (Gift_Batch_Row__c row : GiftBatchSelector.selectRows(batchId)) {
            result.rows.add(new RowView(row));
        }
        result.enteredTotal = GiftBatchSelector.enteredTotal(batchId);
        result.difference = GiftBatchService.difference(result.controlTotal, result.enteredTotal);
        return result;
    }

    private static String paymentMethodOrNull(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        for (PicklistOption option : paymentMethodOptions()) {
            if (option.value == value) {
                return value;
            }
        }
        return null;
    }

    private static List<PicklistOption> paymentMethodOptions() {
        List<PicklistOption> options = new List<PicklistOption>();
        for (
            Schema.PicklistEntry entry : Gift_Batch_Row__c.Payment_Method__c.getDescribe()
                .getPicklistValues()
        ) {
            if (entry.isActive()) {
                options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
            }
        }
        return options;
    }

    /**
     * Anything that is not a live identifier of the expected kind is treated as no value rather
     * than as an error, so a record deleted since the grid was drawn never blocks a save.
     */
    private static Id asId(String value, Schema.SObjectType expected) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            Id parsed = Id.valueOf(value.trim());
            return parsed.getSobjectType() == expected ? parsed : null;
        } catch (System.StringException e) {
            return null;
        }
    }

    /** A message the person can act on where the platform gave one, a plain sentence otherwise. */
    private static String messageFor(Exception thrown, String fallback) {
        if (thrown instanceof GiftBatchService.GiftBatchException) {
            return thrown.getMessage();
        }
        if (thrown instanceof DmlException) {
            DmlException dml = (DmlException) thrown;
            if (dml.getNumDml() > 0) {
                return dml.getDmlMessage(0);
            }
        }
        return fallback;
    }

    private static AuraHandledException asAuraException(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}

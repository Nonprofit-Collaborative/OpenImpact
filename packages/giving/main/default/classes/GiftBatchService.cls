/**
 * The business rules of a gift batch: what a line inherits from the top of the batch, whether a
 * batch balances, and what happens when it is posted.
 *
 * Canonical model rules R-GB1 to R-GB6 and R-GR1 to R-GR4. This is the only class other code
 * calls for batch behavior (plan Section 7.1).
 *
 * The posting path deliberately takes the long way round. It inserts ordinary `Gift__c` records
 * through ordinary DML, so `GiftTrigger` derives the household, dates the gift, creates the
 * default allocation and keeps the allocations honest, and `GiftReceiptLockHandler` applies from
 * the moment each gift exists. Nothing here reimplements a gift rule to make twenty of them
 * faster (R-GB6, ADR-0031).
 */
public with sharing class GiftBatchService {
    public static final String STATUS_OPEN = 'Open';
    public static final String STATUS_POSTED = 'Posted';

    private static final String GIFT_STATUS_RECEIVED = 'Received';
    private static final String CONTEXT = 'GiftBatchService';

    /**
     * Set only while `post` is writing, so the post lock can tell the one legitimate move from
     * Open to Posted from somebody typing the word into the field. It is transaction state, not
     * configuration, and it is cleared in a finally block.
     */
    public static Boolean posting = false;

    public class GiftBatchException extends Exception {
    }

    /** One thing wrong with one line, in the words the person typing will see beside it. */
    public class RowProblem {
        public Id rowId;
        public Integer rowNumber;
        public String message;

        public RowProblem(Gift_Batch_Row__c row, String message) {
            this.rowId = row.Id;
            this.rowNumber = row.Row_Number__c == null ? null : row.Row_Number__c.intValue();
            this.message = message;
        }
    }

    /** What came of a post. */
    public class PostOutcome {
        public Boolean success = false;
        public Integer giftCount = 0;
        public String formError;
        public List<RowProblem> rowProblems = new List<RowProblem>();
    }

    /**
     * R-GB1: the date, fund, appeal and payment method typed once at the top of a batch are
     * copied onto every line that has not been given its own. They are copied rather than
     * referenced, so a line that was deliberately made different stays different, and changing a
     * default later does not silently re-designate what has already been typed.
     */
    public static void applyDefaults(Gift_Batch__c batch, List<Gift_Batch_Row__c> rows) {
        if (batch == null || rows == null) {
            return;
        }
        for (Gift_Batch_Row__c row : rows) {
            if (row.Gift_Date__c == null) {
                row.Gift_Date__c = batch.Default_Gift_Date__c;
            }
            if (row.Fund__c == null) {
                row.Fund__c = batch.Default_Fund__c;
            }
            if (row.Appeal__c == null) {
                row.Appeal__c = batch.Default_Appeal__c;
            }
            if (String.isBlank(row.Payment_Method__c)) {
                row.Payment_Method__c = batch.Default_Payment_Method__c;
            }
        }
    }

    /**
     * The gap between the deposit slip and what has been typed, positive when the slip says more
     * than the lines do. Both sides are treated as zero when they are empty, so the difference is
     * always a number a message can state (R-GB3).
     */
    public static Decimal difference(Decimal controlTotal, Decimal enteredTotal) {
        Decimal control = controlTotal == null ? 0 : controlTotal;
        Decimal entered = enteredTotal == null ? 0 : enteredTotal;
        return control - entered;
    }

    /**
     * Everything wrong with the lines of a batch, all of it, rather than the first thing found.
     * A person fixing a batch wants the list, not one message at a time.
     *
     * R-GR1's other half lives here rather than in a validation rule: a line is saved from the
     * moment an amount is typed, and the donor is usually found a moment later, so refusing to
     * save an unfinished line would lose the typing the object exists to keep.
     */
    public static List<RowProblem> validateRows(List<Gift_Batch_Row__c> rows) {
        List<RowProblem> problems = new List<RowProblem>();
        for (Gift_Batch_Row__c row : rows) {
            Boolean hasContact = row.Donor_Contact__c != null;
            Boolean hasAccount = row.Donor_Account__c != null;
            if (hasContact && hasAccount) {
                problems.add(new RowProblem(row, Label.Giving_GiftBatch_ErrorRowDonorBoth));
            } else if (!hasContact && !hasAccount) {
                problems.add(new RowProblem(row, Label.Giving_GiftBatch_ErrorRowDonorMissing));
            }
            if (row.Amount__c == null || row.Amount__c <= 0) {
                problems.add(new RowProblem(row, Label.Giving_GiftBatch_ErrorRowAmount));
            }
            if (row.Gift_Date__c == null) {
                problems.add(new RowProblem(row, Label.Giving_GiftBatch_ErrorRowDate));
            }
            if (String.isBlank(row.Payment_Method__c)) {
                problems.add(new RowProblem(row, Label.Giving_GiftBatch_ErrorRowPaymentMethod));
            }
        }
        return problems;
    }

    /**
     * Posts a batch: turns every line into a gift, once.
     *
     * The order of the four steps is the feature. The batch is read with a row lock first, so a
     * second post waits and then finds the batch Posted (R-GB4). The totals are compared on the
     * server, inside the transaction that would create the gifts, so a stale browser cannot post
     * an unbalanced batch (R-GB3). The gifts are then inserted through the ordinary triggers
     * (R-GB6). Anything that fails rolls the whole posting back, because a batch whose gifts no
     * longer total the deposit is the state the control total exists to prevent (R-GB5).
     */
    public static PostOutcome post(Id batchId) {
        PostOutcome outcome = new PostOutcome();
        if (batchId == null) {
            outcome.formError = Label.Giving_GiftBatch_ErrorBatchMissing;
            return outcome;
        }
        Savepoint before = Database.setSavepoint();
        try {
            Gift_Batch__c batch = GiftBatchSelector.selectForPost(batchId);
            if (batch == null) {
                outcome.formError = Label.Giving_GiftBatch_ErrorBatchMissing;
                return outcome;
            }
            if (STATUS_POSTED.equals(batch.Status__c)) {
                outcome.formError = Label.Giving_GiftBatch_ErrorAlreadyPosted;
                return outcome;
            }

            List<Gift_Batch_Row__c> rows = GiftBatchSelector.selectRows(batchId);
            if (rows.isEmpty()) {
                outcome.formError = Label.Giving_GiftBatch_ErrorNoRows;
                return outcome;
            }
            if (batch.Control_Total__c == null) {
                outcome.formError = Label.Giving_GiftBatch_ErrorNoControlTotal;
                return outcome;
            }

            Decimal gap = difference(batch.Control_Total__c, GiftBatchSelector.enteredTotal(batchId));
            if (gap != 0) {
                outcome.formError = outOfBalanceMessage(gap);
                return outcome;
            }

            outcome.rowProblems = validateRows(rows);
            if (!outcome.rowProblems.isEmpty()) {
                outcome.formError = Label.Giving_GiftBatch_ErrorRowsIncomplete;
                return outcome;
            }

            createGifts(batch, rows);
            markPosted(batch, rows.size());

            outcome.success = true;
            outcome.giftCount = rows.size();
            return outcome;
        } catch (Exception e) {
            Database.rollback(before);
            ErrorLogger.log(e, CONTEXT + '.post', batchId);
            outcome.success = false;
            outcome.giftCount = 0;
            outcome.formError = postFailureMessage(e);
            return outcome;
        }
    }

    /**
     * R-GB6: one gift per line, inserted as any other gift is, then each line pointed at the gift
     * it produced so the deposit slip and the gifts stay connected.
     *
     * The fund a line names is applied by repointing the single default allocation the gift
     * trigger has just created, which is the path `QuickGiftEntryController` already takes: it
     * keeps the allocations totalling the gift (R-GA1) instead of adding a second one. A line
     * with no fund is left alone, so it lands in the org's default fund exactly as an ungiven
     * designation does anywhere else (R-GA2).
     */
    private static void createGifts(Gift_Batch__c batch, List<Gift_Batch_Row__c> rows) {
        List<Gift__c> gifts = new List<Gift__c>();
        for (Gift_Batch_Row__c row : rows) {
            gifts.add(
                new Gift__c(
                    Donor_Contact__c = row.Donor_Contact__c,
                    Donor_Account__c = row.Donor_Account__c,
                    Gift_Date__c = row.Gift_Date__c,
                    Amount__c = row.Amount__c,
                    Type__c = row.Payment_Method__c,
                    Status__c = GIFT_STATUS_RECEIVED,
                    Appeal__c = row.Appeal__c,
                    Payment_Reference__c = row.Payment_Reference__c
                )
            );
        }
        Database.insert(gifts, true, AccessLevel.USER_MODE);

        Map<Id, Id> fundByGiftId = new Map<Id, Id>();
        for (Integer index = 0; index < rows.size(); index++) {
            rows[index].Gift__c = gifts[index].Id;
            if (rows[index].Fund__c != null) {
                fundByGiftId.put(gifts[index].Id, rows[index].Fund__c);
            }
        }
        applyChosenFunds(fundByGiftId);
        Database.update(rows, true, AccessLevel.USER_MODE);
    }

    /**
     * Points each gift's single allocation at the fund its line named. A gift that somehow
     * arrived with a split is left alone rather than being flattened: the batch does not know
     * better than whatever produced the split.
     */
    private static void applyChosenFunds(Map<Id, Id> fundByGiftId) {
        if (fundByGiftId.isEmpty()) {
            return;
        }
        Map<Id, List<Gift_Allocation__c>> byGift = new Map<Id, List<Gift_Allocation__c>>();
        for (
            Gift_Allocation__c allocation : GiftSelector.selectAllocationsByGiftIds(
                fundByGiftId.keySet()
            )
        ) {
            if (!byGift.containsKey(allocation.Gift__c)) {
                byGift.put(allocation.Gift__c, new List<Gift_Allocation__c>());
            }
            byGift.get(allocation.Gift__c).add(allocation);
        }

        List<Gift_Allocation__c> changed = new List<Gift_Allocation__c>();
        for (Id giftId : fundByGiftId.keySet()) {
            List<Gift_Allocation__c> allocations = byGift.get(giftId);
            if (allocations == null || allocations.size() != 1) {
                continue;
            }
            Gift_Allocation__c allocation = allocations[0];
            if (allocation.Fund__c != fundByGiftId.get(giftId)) {
                allocation.Fund__c = fundByGiftId.get(giftId);
                changed.add(allocation);
            }
        }
        if (!changed.isEmpty()) {
            Database.update(changed, true, AccessLevel.USER_MODE);
        }
    }

    /**
     * R-GB4: the batch is closed in the same transaction that created its gifts. The flag is what
     * lets this one update past the post lock; every other route from Open to Posted is refused.
     */
    private static void markPosted(Gift_Batch__c batch, Integer giftCount) {
        batch.Status__c = STATUS_POSTED;
        batch.Posted_At__c = System.now();
        batch.Posted_By__c = UserInfo.getUserId();
        batch.Gift_Count__c = giftCount;
        posting = true;
        try {
            Database.update(batch, true, AccessLevel.USER_MODE);
        } finally {
            posting = false;
        }
    }

    /** The refusal states the difference and its direction, because that is what to go and check. */
    @TestVisible
    private static String outOfBalanceMessage(Decimal gap) {
        String template = gap > 0
            ? Label.Giving_GiftBatch_ErrorShortOfControlTotal
            : Label.Giving_GiftBatch_ErrorOverControlTotal;
        return template.replace('{0}', String.valueOf(gap.abs().setScale(2)));
    }

    /**
     * A posting that failed says which line the platform refused where it can, because "the batch
     * did not post" is not something a person can act on. The detail is in the Error Log either
     * way.
     */
    private static String postFailureMessage(Exception thrown) {
        if (thrown instanceof DmlException) {
            DmlException dml = (DmlException) thrown;
            if (dml.getNumDml() > 0) {
                return Label.Giving_GiftBatch_ErrorPostFailed + ' ' + dml.getDmlMessage(0);
            }
        }
        return Label.Giving_GiftBatch_ErrorPostFailed;
    }
}

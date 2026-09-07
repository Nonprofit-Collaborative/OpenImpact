/**
 * The business rules of a gift: where its household comes from, how it is allocated, how the
 * allocations are kept honest, and how money that goes back is recorded.
 *
 * Canonical model rules R-G2, R-G3, R-G4, R-G5, R-GA1, R-GA2 and R-GA3. This is the only
 * class other packages call for gift behavior (plan Section 7.1).
 */
public with sharing class GiftService {
    /**
     * Set by a screen that inserts a gift and its allocations in the same transaction, so the
     * gift does not also receive the default allocation it is about to be given properly.
     * Reset it in a finally block: it is transaction state, not configuration.
     */
    public static Boolean suppressDefaultAllocations = false;

    private static final String STATUS_RECEIVED = 'Received';
    private static final String STATUS_REFUNDED = 'Refunded';
    private static final String STATUS_WRITTEN_OFF = 'Written off';
    private static final String RECORD_TYPE_HOUSEHOLD = 'Household';
    private static final String ACKNOWLEDGMENT_NOT_REQUIRED = 'Not required';

    public class GiftServiceException extends Exception {
    }

    /**
     * A gift saved with no date is a gift that arrived today, which is what staff mean when
     * they leave the field empty during a fast entry session.
     */
    public static void defaultGiftDates(List<Gift__c> gifts) {
        Date today = Date.today();
        for (Gift__c gift : gifts) {
            if (gift.Gift_Date__c == null) {
                gift.Gift_Date__c = today;
            }
        }
    }

    /**
     * R-G2: the household on a gift is written by the package, never typed by a user. It comes
     * from the donor contact's household, from the donor account itself when that account is a
     * household, and from the household of a person held as an account. It is left empty when
     * the donor is an organization, and it is cleared when the donor is cleared.
     */
    public static void deriveHouseholds(List<Gift__c> gifts) {
        Set<Id> contactIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        for (Gift__c gift : gifts) {
            if (gift.Donor_Contact__c != null) {
                contactIds.add(gift.Donor_Contact__c);
            } else if (gift.Donor_Account__c != null) {
                accountIds.add(gift.Donor_Account__c);
            }
        }

        Map<Id, String> recordTypeNames = GivingAccountSelector.selectRecordTypeNamesById(
            accountIds
        );
        Set<Id> personIds = new Set<Id>(contactIds);
        for (Id accountId : accountIds) {
            if (RECORD_TYPE_HOUSEHOLD != recordTypeNames.get(accountId)) {
                personIds.add(accountId);
            }
        }

        Map<Id, Id> householdsByPerson = personIds.isEmpty()
            ? new Map<Id, Id>()
            : HouseholdService.getHouseholdIdsFor(personIds);

        for (Gift__c gift : gifts) {
            if (gift.Donor_Contact__c != null) {
                gift.Household__c = householdsByPerson.get(gift.Donor_Contact__c);
            } else if (gift.Donor_Account__c != null) {
                gift.Household__c = RECORD_TYPE_HOUSEHOLD ==
                    recordTypeNames.get(gift.Donor_Account__c)
                    ? gift.Donor_Account__c
                    : householdsByPerson.get(gift.Donor_Account__c);
            } else {
                gift.Household__c = null;
            }
        }
    }

    /**
     * R-G4: once a receipt number is present the amount, the date and the donor are facts a
     * donor already holds on paper. A correction voids the receipt and reissues it (ADR-0010).
     */
    public static void enforceReceiptLock(List<Gift__c> gifts, Map<Id, Gift__c> oldGifts) {
        for (Gift__c gift : gifts) {
            Gift__c previous = oldGifts.get(gift.Id);
            if (previous == null || String.isBlank(previous.Receipt_Number__c)) {
                continue;
            }
            Boolean locked =
                gift.Amount__c != previous.Amount__c ||
                gift.Gift_Date__c != previous.Gift_Date__c ||
                gift.Donor_Contact__c != previous.Donor_Contact__c ||
                gift.Donor_Account__c != previous.Donor_Account__c;
            if (locked) {
                gift.addError(Label.Giving_Gift_ReceiptLocked);
            }
        }
    }

    /**
     * R-GA2: a gift saved with no allocation is allocated in full to the organization's default
     * fund, so fund reporting is complete without asking staff to think about designation on
     * every gift.
     */
    public static void applyDefaultAllocations(List<Gift__c> gifts) {
        if (suppressDefaultAllocations) {
            return;
        }

        Map<Id, Gift__c> candidates = new Map<Id, Gift__c>();
        for (Gift__c gift : gifts) {
            if (gift.Amount__c != null) {
                candidates.put(gift.Id, gift);
            }
        }
        if (candidates.isEmpty()) {
            return;
        }

        for (
            Gift_Allocation__c allocation : GiftAllocationSelector.selectByGiftIds(
                candidates.keySet()
            )
        ) {
            candidates.remove(allocation.Gift__c);
        }
        if (candidates.isEmpty()) {
            return;
        }

        Id defaultFundId = resolveDefaultFundId();
        if (defaultFundId == null) {
            for (Gift__c gift : candidates.values()) {
                gift.addError(Label.Giving_Gift_DefaultFundMissing);
            }
            return;
        }

        List<Gift_Allocation__c> allocations = new List<Gift_Allocation__c>();
        for (Gift__c gift : candidates.values()) {
            allocations.add(
                new Gift_Allocation__c(
                    Gift__c = gift.Id,
                    Fund__c = defaultFundId,
                    Amount__c = gift.Amount__c,
                    Percent__c = 100
                )
            );
        }
        Database.insert(allocations, AccessLevel.USER_MODE);
    }

    /**
     * The organization's default fund: the identifier held in Nonprofit Settings when it points
     * at a fund that still exists and is active, and otherwise the fund that carries the
     * default flag (R-F4). Null when nobody has picked one.
     */
    public static Id resolveDefaultFundId() {
        Id settingFundId = null;
        Nonprofit_Settings__c settings = SettingsService.getSettings();
        String stored = settings == null ? null : settings.Default_Fund__c;
        if (String.isNotBlank(stored)) {
            try {
                settingFundId = Id.valueOf(stored);
            } catch (System.StringException parseError) {
                settingFundId = null;
            }
        }

        if (settingFundId != null) {
            for (Fund__c fund : FundSelector.selectById(new Set<Id>{ settingFundId })) {
                if (fund.Active__c == true) {
                    return fund.Id;
                }
            }
        }

        Fund__c flagged = FundSelector.selectDefaultFund();
        return flagged == null ? null : flagged.Id;
    }

    /**
     * R-GA1: an allocation is entered as an amount or as a percent, and the package works out
     * the other one. Percentages are converted to amounts on save, and where a set of
     * percentages covers a whole gift the rounding difference goes to the largest allocation,
     * so the total is exact.
     */
    public static void applyAmountAndPercent(
        List<Gift_Allocation__c> allocations,
        Map<Id, Gift_Allocation__c> oldAllocations
    ) {
        Set<Id> giftIds = new Set<Id>();
        for (Gift_Allocation__c allocation : allocations) {
            if (allocation.Gift__c != null) {
                giftIds.add(allocation.Gift__c);
            }
        }
        if (giftIds.isEmpty()) {
            return;
        }
        Map<Id, Gift__c> giftsById = GiftSelector.selectAmountsById(giftIds);

        Map<Id, List<Gift_Allocation__c>> percentEntered = new Map<Id, List<Gift_Allocation__c>>();
        for (Gift_Allocation__c allocation : allocations) {
            Gift__c gift = giftsById.get(allocation.Gift__c);
            if (gift == null || gift.Amount__c == null || gift.Amount__c == 0) {
                continue;
            }
            Gift_Allocation__c previous = oldAllocations == null
                ? null
                : oldAllocations.get(allocation.Id);
            Boolean amountChanged = previous == null
                ? allocation.Amount__c != null
                : allocation.Amount__c != previous.Amount__c;
            Boolean percentChanged = previous == null
                ? allocation.Percent__c != null
                : allocation.Percent__c != previous.Percent__c;

            if (allocation.Amount__c == null && allocation.Percent__c != null) {
                allocation.Amount__c = (gift.Amount__c *
                    allocation.Percent__c /
                    100)
                    .setScale(2, System.RoundingMode.HALF_UP);
                addTo(percentEntered, allocation.Gift__c, allocation);
            } else if (percentChanged && !amountChanged && allocation.Percent__c != null) {
                allocation.Amount__c = (gift.Amount__c *
                    allocation.Percent__c /
                    100)
                    .setScale(2, System.RoundingMode.HALF_UP);
            } else if (allocation.Amount__c != null) {
                allocation.Percent__c = (allocation.Amount__c /
                    gift.Amount__c *
                    100)
                    .setScale(2, System.RoundingMode.HALF_UP);
            }
        }

        spreadRoundingDifference(percentEntered, giftsById);
    }

    private static void addTo(
        Map<Id, List<Gift_Allocation__c>> byGift,
        Id giftId,
        Gift_Allocation__c allocation
    ) {
        if (!byGift.containsKey(giftId)) {
            byGift.put(giftId, new List<Gift_Allocation__c>());
        }
        byGift.get(giftId).add(allocation);
    }

    /**
     * Where a set of percentages covers a whole gift, rounding can leave a cent unallocated.
     * It goes to the largest allocation of the set, which is the convention finance staff
     * expect and the one R-GA1 records.
     */
    private static void spreadRoundingDifference(
        Map<Id, List<Gift_Allocation__c>> percentEntered,
        Map<Id, Gift__c> giftsById
    ) {
        for (Id giftId : percentEntered.keySet()) {
            List<Gift_Allocation__c> allocations = percentEntered.get(giftId);
            Decimal percentTotal = 0;
            Decimal amountTotal = 0;
            Gift_Allocation__c largest = null;
            for (Gift_Allocation__c allocation : allocations) {
                percentTotal += allocation.Percent__c;
                amountTotal += allocation.Amount__c;
                if (largest == null || allocation.Amount__c.abs() > largest.Amount__c.abs()) {
                    largest = allocation;
                }
            }
            Decimal giftAmount = giftsById.get(giftId).Amount__c;
            if (percentTotal == 100 && largest != null && amountTotal != giftAmount) {
                largest.Amount__c = largest.Amount__c + (giftAmount - amountTotal);
            }
        }
    }

    /**
     * R-G5 and R-GA1: every gift's allocations total its amount exactly. Returns one message
     * per gift that does not add up, naming the difference, so the caller can put the error on
     * the record the user is actually editing.
     *
     * A gift that no longer exists is not checked: its allocations are being deleted with it.
     */
    public static Map<Id, String> validateAllocations(Set<Id> giftIds) {
        Map<Id, String> problems = new Map<Id, String>();
        if (giftIds == null || giftIds.isEmpty()) {
            return problems;
        }

        Map<Id, Gift__c> giftsById = GiftSelector.selectAmountsById(giftIds);
        Map<Id, Decimal> totals = new Map<Id, Decimal>();
        for (Id giftId : giftsById.keySet()) {
            totals.put(giftId, 0);
        }
        for (
            Gift_Allocation__c allocation : GiftAllocationSelector.selectByGiftIds(
                giftsById.keySet()
            )
        ) {
            Decimal running = totals.get(allocation.Gift__c);
            totals.put(
                allocation.Gift__c,
                running + (allocation.Amount__c == null ? 0 : allocation.Amount__c)
            );
        }

        for (Id giftId : giftsById.keySet()) {
            Gift__c gift = giftsById.get(giftId);
            if (gift.Amount__c == null) {
                continue;
            }
            Decimal allocated = totals.get(giftId).setScale(2, System.RoundingMode.HALF_UP);
            Decimal expected = gift.Amount__c.setScale(2, System.RoundingMode.HALF_UP);
            if (allocated != expected) {
                problems.put(
                    giftId,
                    String.format(
                        Label.Giving_Gift_AllocationsMustTotal,
                        new List<String>{
                            String.valueOf(allocated),
                            String.valueOf(expected),
                            String.valueOf((expected - allocated).abs())
                        }
                    )
                );
            }
        }
        return problems;
    }

    /**
     * A gift whose amount changes and that has exactly one allocation has that allocation moved
     * with it, because the single allocation is the one the package created and staff never
     * chose. A gift split across several funds is left alone and the person is told to adjust
     * the split first, because the package cannot know which fund lost the money.
     */
    public static void synchronizeAllocationsToAmount(
        List<Gift__c> gifts,
        Map<Id, Gift__c> oldGifts
    ) {
        Map<Id, Gift__c> changed = new Map<Id, Gift__c>();
        for (Gift__c gift : gifts) {
            Gift__c previous = oldGifts.get(gift.Id);
            if (previous != null && gift.Amount__c != previous.Amount__c) {
                changed.put(gift.Id, gift);
            }
        }
        if (changed.isEmpty()) {
            return;
        }

        Map<Id, List<Gift_Allocation__c>> byGift = new Map<Id, List<Gift_Allocation__c>>();
        for (
            Gift_Allocation__c allocation : GiftAllocationSelector.selectByGiftIds(changed.keySet())
        ) {
            addTo(byGift, allocation.Gift__c, allocation);
        }

        List<Gift_Allocation__c> toUpdate = new List<Gift_Allocation__c>();
        for (Id giftId : byGift.keySet()) {
            List<Gift_Allocation__c> allocations = byGift.get(giftId);
            Gift__c gift = changed.get(giftId);
            if (allocations.size() == 1) {
                allocations[0].Amount__c = gift.Amount__c;
                allocations[0].Percent__c = 100;
                toUpdate.add(allocations[0]);
            } else {
                gift.addError(Label.Giving_Gift_AmountChangeSplit);
            }
        }
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, AccessLevel.USER_MODE);
        }
    }

    /**
     * G-04: record money going back to a donor as a new gift for a negative amount, linked to
     * the original, with the original's allocations mirrored negatively so fund totals correct
     * themselves (R-G3, R-GA3, ADR-0010). The original is never edited except for its status,
     * and only when the whole gift has gone back.
     *
     * Returns the identifier of the gift that records the refund.
     */
    public static Id refund(Id giftId, Decimal amount, String reason) {
        Gift__c original = loadReversible(giftId);
        Decimal remaining = remainingAmount(original);
        if (amount == null || amount <= 0) {
            throw new GiftServiceException(Label.Giving_Gift_RefundAmountRequired);
        }
        if (amount > remaining) {
            throw new GiftServiceException(Label.Giving_Gift_RefundExceedsRemaining);
        }
        Boolean whole = amount == remaining && remaining == original.Amount__c;
        return recordReversal(original, -amount, reason, whole ? STATUS_REFUNDED : null);
    }

    /**
     * G-04: a gift that is never going to be collected is written off, which is the same shape
     * as a refund (a linked negative gift) with a different status on the original.
     */
    public static Id writeOff(Id giftId, String reason) {
        Gift__c original = loadReversible(giftId);
        Decimal remaining = remainingAmount(original);
        if (remaining <= 0) {
            throw new GiftServiceException(
                String.format(
                    Label.Giving_Gift_AlreadyReversed,
                    new List<String>{ String.valueOf(original.Status__c) }
                )
            );
        }
        return recordReversal(original, -remaining, reason, STATUS_WRITTEN_OFF);
    }

    private static Gift__c loadReversible(Id giftId) {
        if (giftId == null) {
            throw new GiftServiceException(Label.Giving_Gift_OriginalNotFound);
        }
        List<Gift__c> gifts = GiftSelector.selectWithAllocations(new Set<Id>{ giftId });
        if (gifts.isEmpty()) {
            throw new GiftServiceException(Label.Giving_Gift_OriginalNotFound);
        }
        Gift__c original = gifts[0];
        if (original.Amount__c == null || original.Amount__c <= 0) {
            throw new GiftServiceException(Label.Giving_Gift_CannotReverseNegative);
        }
        return original;
    }

    /**
     * What is left of a gift once the negative gifts that reverse it are counted.
     */
    public static Decimal remainingAmount(Gift__c original) {
        Decimal remaining = original.Amount__c;
        for (Gift__c reversal : GiftSelector.selectReversalsFor(new Set<Id>{ original.Id })) {
            remaining += reversal.Amount__c == null ? 0 : reversal.Amount__c;
        }
        return remaining;
    }

    private static Id recordReversal(
        Gift__c original,
        Decimal negativeAmount,
        String reason,
        String newOriginalStatus
    ) {
        Gift__c reversal = new Gift__c(
            Donor_Contact__c = original.Donor_Contact__c,
            Donor_Account__c = original.Donor_Account__c,
            Appeal__c = original.Appeal__c,
            Type__c = original.Type__c,
            Gift_Date__c = Date.today(),
            Amount__c = negativeAmount,
            Status__c = STATUS_RECEIVED,
            Acknowledgment_Status__c = ACKNOWLEDGMENT_NOT_REQUIRED,
            Original_Gift__c = original.Id,
            Refund_Reason__c = reason
        );

        List<Gift_Allocation__c> originalAllocations = original.Gift_Allocations__r;
        Boolean mirrorAllocations = originalAllocations != null && !originalAllocations.isEmpty();

        try {
            suppressDefaultAllocations = mirrorAllocations;
            Database.insert(reversal, AccessLevel.USER_MODE);
        } finally {
            suppressDefaultAllocations = false;
        }

        if (mirrorAllocations) {
            Database.insert(
                mirroredAllocations(
                    reversal.Id,
                    originalAllocations,
                    original.Amount__c,
                    negativeAmount
                ),
                AccessLevel.USER_MODE
            );
        }

        if (newOriginalStatus != null) {
            Database.update(
                new Gift__c(Id = original.Id, Status__c = newOriginalStatus),
                AccessLevel.USER_MODE
            );
        }
        return reversal.Id;
    }

    /**
     * R-GA3: the reversal's allocations mirror the original's, in proportion, with the rounding
     * difference on the largest one so the mirrored total is exactly the reversal's amount.
     */
    private static List<Gift_Allocation__c> mirroredAllocations(
        Id reversalGiftId,
        List<Gift_Allocation__c> originalAllocations,
        Decimal originalAmount,
        Decimal negativeAmount
    ) {
        List<Gift_Allocation__c> mirrored = new List<Gift_Allocation__c>();
        Decimal running = 0;
        Gift_Allocation__c largest = null;
        for (Gift_Allocation__c source : originalAllocations) {
            Decimal share = source.Amount__c == null ? 0 : source.Amount__c;
            Decimal mirroredAmount = (share /
                originalAmount *
                negativeAmount)
                .setScale(2, System.RoundingMode.HALF_UP);
            Gift_Allocation__c allocation = new Gift_Allocation__c(
                Gift__c = reversalGiftId,
                Fund__c = source.Fund__c,
                Amount__c = mirroredAmount
            );
            running += mirroredAmount;
            if (largest == null || mirroredAmount.abs() > largest.Amount__c.abs()) {
                largest = allocation;
            }
            mirrored.add(allocation);
        }
        if (largest != null && running != negativeAmount) {
            largest.Amount__c = largest.Amount__c + (negativeAmount - running);
        }
        return mirrored;
    }
}

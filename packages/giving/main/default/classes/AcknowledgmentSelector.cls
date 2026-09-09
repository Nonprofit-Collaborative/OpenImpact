/**
 * Every query the acknowledgment rules need (plan Section 9.3).
 *
 * Three of them run `WITH SYSTEM_MODE`, out loud rather than by omission. `activeRules` reads the
 * configuration the package itself decides with: a rule that quietly stopped applying because the
 * person saving a gift cannot see rule records would be worse than no rules at all, which is the
 * reason the donor level ladder is read the same way. `earliestGiftDateByDonor` decides whether a
 * gift is a donor's first, and an answer that changed with who was saving would not be an answer.
 * `giftsToAcknowledge` reads a donor's name and an appeal's name only to compose wording the
 * package then stores on a record it owns. ADR-0021 allows a read whose only purpose is to compute
 * a package owned value to run in system mode alongside the write it feeds, provided the class says
 * which reads are which. These are those, and record level sharing still applies to every one of
 * them: this class is `with sharing`, and `WITH SYSTEM_MODE` waives object and field permissions,
 * not who may see which record.
 */
public with sharing class AcknowledgmentSelector {
    /**
     * The gift statuses that count when the question is "has this donor given before". The same
     * three ADR-0022 settled for the counting rollups, plus a positive amount, so that a gift
     * given once and refunded in full is still the gift that came first and the negative gift
     * reversing it is not a second one.
     */
    public static final Set<String> COUNTED_STATUSES = new Set<String>{
        'Received',
        'Refunded',
        'Written off'
    };

    /** The rules, in the order they are tested (R-AK1). */
    public static List<Acknowledgment_Rule__c> activeRules() {
        return [
            SELECT
                Id,
                Name,
                Evaluation_Order__c,
                Minimum_Amount__c,
                Maximum_Amount__c,
                Gift_Type__c,
                Appeal__c,
                First_Gift_Only__c,
                Channel__c,
                Template__c,
                Template__r.Id,
                Template__r.Name,
                Template__r.Channel__c,
                Template__r.Body__c,
                Template__r.Email_Template_Developer_Name__c,
                Template__r.Active__c
            FROM Acknowledgment_Rule__c
            WHERE Active__c = TRUE
            WITH SYSTEM_MODE
            ORDER BY Evaluation_Order__c ASC, Name ASC
            LIMIT 500
        ];
    }

    /**
     * The date of the earliest gift each donor has, so that "first gift" is answered from the
     * gifts rather than from a total the rollup engine may not have recalculated since last night
     * (R-AK4). Contacts and accounts are asked separately because a donor is one or the other and
     * never both.
     */
    public static Map<Id, Date> earliestGiftDateByDonor(Set<Id> donorIds) {
        Map<Id, Date> earliest = new Map<Id, Date>();
        if (donorIds == null || donorIds.isEmpty()) {
            return earliest;
        }
        for (AggregateResult row : [
            SELECT Donor_Contact__c donorId, MIN(Gift_Date__c) firstGift
            FROM Gift__c
            WHERE Donor_Contact__c IN :donorIds AND Amount__c > 0 AND Status__c IN :COUNTED_STATUSES
            WITH SYSTEM_MODE
            GROUP BY Donor_Contact__c
            LIMIT 2000
        ]) {
            earliest.put((Id) row.get('donorId'), (Date) row.get('firstGift'));
        }
        for (AggregateResult row : [
            SELECT Donor_Account__c donorId, MIN(Gift_Date__c) firstGift
            FROM Gift__c
            WHERE Donor_Account__c IN :donorIds AND Amount__c > 0 AND Status__c IN :COUNTED_STATUSES
            WITH SYSTEM_MODE
            GROUP BY Donor_Account__c
            LIMIT 2000
        ]) {
            earliest.put((Id) row.get('donorId'), (Date) row.get('firstGift'));
        }
        return earliest;
    }

    /**
     * The gifts just marked acknowledged, with the donor and appeal names the wording merges.
     * Read after the save rather than carried from the trigger context, because the merge needs
     * related names the trigger record does not hold.
     */
    public static List<Gift__c> giftsToAcknowledge(Set<Id> giftIds) {
        if (giftIds == null || giftIds.isEmpty()) {
            return new List<Gift__c>();
        }
        return [
            SELECT
                Id,
                Amount__c,
                Gift_Date__c,
                Type__c,
                Status__c,
                Acknowledgment_Status__c,
                Acknowledgment_Date__c,
                Appeal__c,
                Appeal__r.Name,
                Donor_Contact__c,
                Donor_Contact__r.Name,
                Donor_Contact__r.FirstName,
                Donor_Account__c,
                Donor_Account__r.Name
            FROM Gift__c
            WHERE Id IN :giftIds
            WITH SYSTEM_MODE
            LIMIT 2000
        ];
    }

    /** Every thank you recorded against one gift, newest first, for a screen or a test. */
    public static List<Acknowledgment__c> forGift(Id giftId) {
        return [
            SELECT
                Id,
                Name,
                Gift__c,
                Rule__c,
                Template__c,
                Channel__c,
                Acknowledged_Date__c,
                Letter__c,
                Email_Template_Developer_Name__c
            FROM Acknowledgment__c
            WHERE Gift__c = :giftId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 200
        ];
    }
}

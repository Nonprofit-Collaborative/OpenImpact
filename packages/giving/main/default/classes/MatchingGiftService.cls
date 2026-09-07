/**
 * Matching gifts: the employer's gift that an employee's gift earned (feature G-10, canonical
 * model R-G11).
 *
 * The two gifts stay two gifts. The company gave its money and is hard credited for it, the
 * employee gave theirs and is hard credited for that, and the link records that one caused the
 * other. The employee then gets a soft credit on the company's gift, so their real influence on
 * the organization's income is visible without anyone being credited with money they did not
 * give.
 *
 * What is checked before a link is accepted:
 *
 *   - one gift of the pair comes from an account whose record type is Organization, and it is
 *     the employer's gift;
 *   - the other comes from a person, and it is the employee's gift;
 *   - where that person's Employer is filled in, it names that same organization;
 *   - neither gift is already linked to a third gift, and a gift never matches itself.
 *
 * Where Employer is blank the link is accepted without complaint. Filling it in is what turns a
 * silent mistake into a message.
 *
 * There are two ways in and they enforce the same rules: `link` and `unlink`, called by an action
 * with two record ids, and `applyLinkChanges`, called by the gift trigger when someone edits the
 * Matched Gift field on the record page.
 */
public with sharing class MatchingGiftService {
    public static final String RECORD_TYPE_ORGANIZATION = 'Organization';

    public class MatchingGiftException extends Exception {
    }

    /**
     * Links an employee's gift to the employer's gift that matched it, from either side.
     */
    public static void link(Id employeeGiftId, Id employerGiftId) {
        if (employeeGiftId == null || employerGiftId == null) {
            throw new MatchingGiftException(Label.Giving_MatchingGift_GiftNotFound);
        }
        if (employeeGiftId == employerGiftId) {
            throw new MatchingGiftException(Label.Giving_MatchingGift_SameGift);
        }
        Map<Id, Gift__c> giftById = giftsById(new Set<Id>{ employeeGiftId, employerGiftId });
        Gift__c employeeGift = giftById.get(employeeGiftId);
        Gift__c employerGift = giftById.get(employerGiftId);
        if (employeeGift == null || employerGift == null) {
            throw new MatchingGiftException(Label.Giving_MatchingGift_GiftNotFound);
        }
        if (!isOrganizationGift(employerGift)) {
            throw new MatchingGiftException(Label.Giving_MatchingGift_EmployerMustBeOrganization);
        }
        String problem = problemWith(employerGift, employeeGift);
        if (problem != null) {
            throw new MatchingGiftException(problem);
        }

        Database.update(
            new List<Gift__c>{
                new Gift__c(Id = employeeGiftId, Matched_Gift__c = employerGiftId),
                new Gift__c(Id = employerGiftId, Matched_Gift__c = employeeGiftId)
            },
            true,
            AccessLevel.USER_MODE
        );
        insertCredits(creditsFor(employerGift, donorPersonOf(employeeGift)));
    }

    /**
     * Undoes a link from either side, and removes the credit the link created.
     */
    public static void unlink(Id giftId) {
        if (giftId == null) {
            throw new MatchingGiftException(Label.Giving_MatchingGift_GiftNotFound);
        }
        Gift__c gift = giftsById(new Set<Id>{ giftId }).get(giftId);
        if (gift == null) {
            throw new MatchingGiftException(Label.Giving_MatchingGift_GiftNotFound);
        }
        if (gift.Matched_Gift__c == null) {
            return;
        }
        Id otherGiftId = gift.Matched_Gift__c;
        Database.update(
            new List<Gift__c>{
                new Gift__c(Id = giftId, Matched_Gift__c = null),
                new Gift__c(Id = otherGiftId, Matched_Gift__c = null)
            },
            true,
            AccessLevel.USER_MODE
        );
        removeMatchedDonorCredits(new Set<Id>{ giftId, otherGiftId });
    }

    /**
     * The trigger path: someone typed into Matched Gift on a gift record, or an import did.
     * Refuses a link the rules do not allow, writes the other side of the one they do, and
     * maintains the matched donor credit either way.
     */
    public static void applyLinkChanges(List<Gift__c> gifts, Map<Id, Gift__c> priorById) {
        if (gifts == null || gifts.isEmpty()) {
            return;
        }
        Map<Id, Id> newPartnerByGift = new Map<Id, Id>();
        Map<Id, Id> oldPartnerByGift = new Map<Id, Id>();
        Set<Id> involved = new Set<Id>();
        for (Gift__c gift : gifts) {
            Id priorPartnerId = null;
            if (priorById != null && priorById.containsKey(gift.Id)) {
                priorPartnerId = priorById.get(gift.Id).Matched_Gift__c;
            }
            if (gift.Matched_Gift__c == priorPartnerId) {
                continue;
            }
            involved.add(gift.Id);
            if (gift.Matched_Gift__c != null) {
                newPartnerByGift.put(gift.Id, gift.Matched_Gift__c);
                involved.add(gift.Matched_Gift__c);
            }
            if (priorPartnerId != null) {
                oldPartnerByGift.put(gift.Id, priorPartnerId);
                involved.add(priorPartnerId);
            }
        }
        if (involved.isEmpty()) {
            return;
        }

        Map<Id, Gift__c> giftById = giftsById(involved);
        Map<Id, Gift__c> updateById = new Map<Id, Gift__c>();
        List<Soft_Credit__c> creditsToInsert = new List<Soft_Credit__c>();
        Set<Id> creditsToRemoveFor = new Set<Id>();
        Map<Id, Gift__c> byId = new Map<Id, Gift__c>(gifts);

        for (Id giftId : oldPartnerByGift.keySet()) {
            Id oldPartnerId = oldPartnerByGift.get(giftId);
            if (newPartnerByGift.get(giftId) == oldPartnerId) {
                continue;
            }
            creditsToRemoveFor.add(giftId);
            creditsToRemoveFor.add(oldPartnerId);
            Gift__c oldPartner = giftById.get(oldPartnerId);
            if (oldPartner != null && oldPartner.Matched_Gift__c == giftId) {
                updateById.put(oldPartnerId, new Gift__c(Id = oldPartnerId, Matched_Gift__c = null));
            }
        }

        for (Id giftId : newPartnerByGift.keySet()) {
            Id partnerId = newPartnerByGift.get(giftId);
            Gift__c edited = giftById.get(giftId);
            Gift__c partner = giftById.get(partnerId);
            Gift__c record = byId.get(giftId);
            if (edited == null || partner == null) {
                record.addError(Label.Giving_MatchingGift_GiftNotFound);
                continue;
            }
            if (giftId == partnerId) {
                record.addError(Label.Giving_MatchingGift_SameGift);
                continue;
            }
            Gift__c employerGift = isOrganizationGift(edited) ? edited : partner;
            Gift__c employeeGift = employerGift === edited ? partner : edited;
            if (!isOrganizationGift(employerGift)) {
                record.addError(Label.Giving_MatchingGift_EmployerMustBeOrganization);
                continue;
            }
            String problem = problemWith(employerGift, employeeGift);
            if (problem != null) {
                record.addError(problem);
                continue;
            }
            if (partner.Matched_Gift__c != giftId) {
                updateById.put(partnerId, new Gift__c(Id = partnerId, Matched_Gift__c = giftId));
            }
            creditsToRemoveFor.remove(giftId);
            creditsToRemoveFor.remove(partnerId);
            creditsToInsert.addAll(creditsFor(employerGift, donorPersonOf(employeeGift)));
        }

        if (!creditsToRemoveFor.isEmpty()) {
            removeMatchedDonorCredits(creditsToRemoveFor);
        }
        if (!updateById.isEmpty()) {
            Database.update(updateById.values(), true, AccessLevel.USER_MODE);
        }
        insertCredits(creditsToInsert);
    }

    /**
     * The reason this pair may not be linked, or null when it may. The employer's gift is
     * assumed to have been identified already.
     */
    private static String problemWith(Gift__c employerGift, Gift__c employeeGift) {
        if (employerGift.Id == employeeGift.Id) {
            return Label.Giving_MatchingGift_SameGift;
        }
        if (isOrganizationGift(employeeGift) || donorPersonOf(employeeGift) == null) {
            return Label.Giving_MatchingGift_EmployeeMustBePerson;
        }
        if (
            linkedElsewhere(employeeGift, employerGift.Id) ||
            linkedElsewhere(employerGift, employeeGift.Id)
        ) {
            return Label.Giving_MatchingGift_AlreadyLinked;
        }
        Id statedEmployerId = employerOf(employeeGift);
        if (statedEmployerId != null && statedEmployerId != employerGift.Donor_Account__c) {
            return Label.Giving_MatchingGift_EmployerMismatch;
        }
        return null;
    }

    /**
     * The matched donor credit for one link, unless it is already there.
     */
    private static List<Soft_Credit__c> creditsFor(Gift__c employerGift, Id employeePersonId) {
        List<Soft_Credit__c> credits = new List<Soft_Credit__c>();
        if (employeePersonId == null) {
            return credits;
        }
        for (Soft_Credit__c existing : SoftCreditSelector.selectAutomaticForGifts(
            new Set<Id>{ employerGift.Id },
            SoftCreditService.ROLE_MATCHED_DONOR
        )) {
            Id creditedId = existing.Contact__c != null ? existing.Contact__c : existing.Account__c;
            if (creditedId == employeePersonId) {
                return credits;
            }
        }
        credits.add(
            SoftCreditService.buildAutomaticCredit(
                employerGift.Id,
                employeePersonId,
                SoftCreditService.ROLE_MATCHED_DONOR,
                employerGift.Amount__c,
                employerGift.Amount__c
            )
        );
        return credits;
    }

    private static void insertCredits(List<Soft_Credit__c> credits) {
        if (credits != null && !credits.isEmpty()) {
            Database.insert(credits, true, AccessLevel.USER_MODE);
        }
    }

    private static void removeMatchedDonorCredits(Set<Id> giftIds) {
        List<Soft_Credit__c> toDelete = SoftCreditSelector.selectAutomaticForGifts(
            giftIds,
            SoftCreditService.ROLE_MATCHED_DONOR
        );
        if (!toDelete.isEmpty()) {
            Database.delete(toDelete, true, AccessLevel.USER_MODE);
        }
    }

    private static Map<Id, Gift__c> giftsById(Set<Id> giftIds) {
        return new Map<Id, Gift__c>(GiftLookupSelector.selectForMatching(giftIds));
    }

    private static Boolean isOrganizationGift(Gift__c gift) {
        return gift != null &&
            gift.Donor_Account__c != null &&
            gift.Donor_Account__r != null &&
            gift.Donor_Account__r.RecordType != null &&
            RECORD_TYPE_ORGANIZATION.equals(gift.Donor_Account__r.RecordType.DeveloperName);
    }

    private static Boolean linkedElsewhere(Gift__c gift, Id intendedPartnerId) {
        return gift.Matched_Gift__c != null && gift.Matched_Gift__c != intendedPartnerId;
    }

    private static Id donorPersonOf(Gift__c gift) {
        return gift.Donor_Contact__c != null ? gift.Donor_Contact__c : gift.Donor_Account__c;
    }

    private static Id employerOf(Gift__c gift) {
        if (gift.Donor_Contact__c != null && gift.Donor_Contact__r != null) {
            return gift.Donor_Contact__r.Employer__c;
        }
        if (gift.Donor_Account__c != null && gift.Donor_Account__r != null) {
            return gift.Donor_Account__r.Employer__c;
        }
        return null;
    }
}

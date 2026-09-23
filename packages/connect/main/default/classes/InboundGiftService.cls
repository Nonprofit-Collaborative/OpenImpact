/**
 * Records gifts sent by other systems (feature X-03), for the REST endpoint and the Flow action
 * alike. The contract is `docs/api/inbound-gift-api.md` and the decisions behind it ADR-NEXT.
 *
 * Four rules shape everything here:
 *
 * - A gift is made the way Giving makes one: an ordinary `Gift__c` insert in user mode, then
 *   `GiftService.applyChosenFunds` for a chosen fund, the path quick entry and gift batches use
 *   (ADR-0045). Giving's own triggers derive the household and the default allocation; nothing
 *   here reimplements a gift rule.
 * - External Id is the key (canonical model R-G7). A gift already carrying it is answered, never
 *   edited: `existing` when the amount agrees, `external_id_conflict` when it does not.
 * - A donor is found, never created: by record id, or by email through Core's importer matcher.
 * - Each gift succeeds or fails on its own, and every failure is an answer with a stable error
 *   code, logged to the Error Log so the nonprofit sees a gift that did not arrive.
 */
public with sharing class InboundGiftService {
    private static final Integer MAX_EXTERNAL_ID = 100;
    private static final Integer MAX_PARSER_MESSAGE = 255;
    private static final Integer SAVE_ATTEMPTS = 2;
    private static final String CONTEXT = 'InboundGiftService';

    /**
     * One gift from a REST request body. A body that is not JSON, names a field `InboundGift`
     * does not have, or carries a value of the wrong type is refused as a whole: reading it
     * strictly is what stops a misspelled field from being silently ignored.
     */
    public static InboundGiftResult recordBody(Blob body) {
        InboundGift gift = null;
        String problem = null;
        try {
            gift = (InboundGift) JSON.deserializeStrict(
                body == null ? '' : body.toString(),
                InboundGift.class
            );
        } catch (Exception malformed) {
            problem = malformed.getMessage();
        }
        if (gift == null) {
            InboundGiftResult refused = InboundGiftResult.rejected(
                InboundGiftResult.ERROR_INVALID_REQUEST,
                String.format(
                    Label.Connect_InboundGift_ErrorInvalidRequest,
                    new List<String>{ String.valueOf(problem).abbreviate(MAX_PARSER_MESSAGE) }
                )
            );
            logRefusals(new List<InboundGift>{ null }, new List<InboundGiftResult>{ refused });
            return refused;
        }
        return record(new List<InboundGift>{ gift })[0];
    }

    /**
     * Records each gift and answers each one, in the order given. Nothing that goes wrong with one
     * gift stops another; only an unexpected failure undoes the whole call, and it is answered as
     * `internal_error` for every gift, which a caller can safely send again.
     */
    public static List<InboundGiftResult> record(List<InboundGift> requests) {
        List<InboundGiftResult> results = new List<InboundGiftResult>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }
        Savepoint start = Database.setSavepoint();
        try {
            results = process(requests);
        } catch (Exception unexpected) {
            Database.rollback(start);
            ErrorLogger.log(unexpected, CONTEXT);
            results = new List<InboundGiftResult>();
            for (Integer index = 0; index < requests.size(); index++) {
                results.add(
                    InboundGiftResult.rejected(
                        InboundGiftResult.ERROR_INTERNAL,
                        Label.Connect_InboundGift_ErrorInternal
                    )
                );
            }
        }
        logRefusals(requests, results);
        return results;
    }

    private static List<InboundGiftResult> process(List<InboundGift> requests) {
        List<InboundGiftRequest> all = new List<InboundGiftRequest>();
        Map<String, InboundGiftRequest> firstByKey = new Map<String, InboundGiftRequest>();
        List<InboundGiftRequest> repeats = new List<InboundGiftRequest>();
        for (InboundGift request : requests) {
            InboundGiftRequest item = new InboundGiftRequest(request);
            all.add(item);
            item.validate();
            if (item.result != null) {
                continue;
            }
            if (firstByKey.containsKey(item.key)) {
                repeats.add(item);
            } else {
                firstByKey.put(item.key, item);
            }
        }

        List<InboundGiftRequest> fresh = new List<InboundGiftRequest>();
        Map<String, Gift__c> recorded = InboundGiftSelector.giftsByExternalId(
            externalIds(firstByKey.values())
        );
        for (InboundGiftRequest item : firstByKey.values()) {
            Gift__c found = recorded.get(item.key);
            if (found != null) {
                answerFromRecordedGift(item, found);
            } else {
                fresh.add(item);
            }
        }

        resolveReferences(fresh);
        List<InboundGiftRequest> ready = new List<InboundGiftRequest>();
        for (InboundGiftRequest item : fresh) {
            if (item.result == null) {
                ready.add(item);
            }
        }
        insertGifts(ready);

        for (InboundGiftRequest item : repeats) {
            InboundGiftRequest first = firstByKey.get(item.key);
            if (first.recordedGiftId == null) {
                item.result = InboundGiftResult.rejected(
                    InboundGiftResult.ERROR_INVALID_FIELD,
                    Label.Connect_InboundGift_ErrorRepeated
                );
            } else {
                answerFromRecordedGift(
                    item,
                    new Gift__c(Id = first.recordedGiftId, Amount__c = first.recordedAmount)
                );
            }
        }

        List<InboundGiftResult> results = new List<InboundGiftResult>();
        for (InboundGiftRequest item : all) {
            results.add(item.result);
        }
        return results;
    }

    /**
     * The donor, fund and appeal each gift names, with one query per kind of reference however
     * many gifts there are. A reference that is malformed, of the wrong kind, or to a record the
     * integration user cannot see gets the same answer as one to nothing, so a caller probing
     * with made-up identifiers learns nothing about what is in the org.
     */
    private static void resolveReferences(List<InboundGiftRequest> items) {
        Set<Id> contactIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        Set<String> emailKeys = new Set<String>();
        Set<String> fundCodes = new Set<String>();
        Set<Id> fundIds = new Set<Id>();
        Set<Id> appealIds = new Set<Id>();
        for (InboundGiftRequest item : items) {
            InboundGift request = item.request;
            Id donor = InboundGiftRequest.asId(request.donorId);
            if (donor != null && donor.getSObjectType() == Contact.SObjectType) {
                contactIds.add(donor);
            } else if (donor != null && donor.getSObjectType() == Account.SObjectType) {
                accountIds.add(donor);
            }
            if (String.isNotBlank(request.donorEmail)) {
                emailKeys.add(ImportMatcher.emailKey(request.donorEmail));
            }
            if (String.isNotBlank(request.fundCode)) {
                fundCodes.add(request.fundCode.trim());
            }
            addIfOfType(fundIds, request.fundId, Fund__c.SObjectType);
            addIfOfType(appealIds, request.appealId, Appeal__c.SObjectType);
        }

        Map<String, Id> contactByEmail = ImportMatcher.contactsByEmail(emailKeys);
        contactIds.addAll(contactByEmail.values());
        Map<Id, Id> donorByContact = InboundGiftSelector.donorForContacts(contactIds);
        Set<Id> visibleAccounts = InboundGiftSelector.accountIds(accountIds);
        Map<String, Id> fundByCode = InboundGiftSelector.activeFundsByCode(fundCodes);
        Set<Id> activeFunds = InboundGiftSelector.activeFundIds(fundIds);
        Set<Id> visibleAppeals = InboundGiftSelector.appealIds(appealIds);

        for (InboundGiftRequest item : items) {
            InboundGift request = item.request;
            Id donor;
            String donorMissing;
            if (String.isNotBlank(request.donorId)) {
                Id named = InboundGiftRequest.asId(request.donorId);
                donor = named == null
                    ? null
                    : (donorByContact.containsKey(named)
                          ? donorByContact.get(named)
                          : (visibleAccounts.contains(named) ? named : null));
                donorMissing = Label.Connect_InboundGift_ErrorDonorIdNotFound;
            } else {
                Id contactId = contactByEmail.get(ImportMatcher.emailKey(request.donorEmail));
                donor = contactId == null ? null : donorByContact.get(contactId);
                donorMissing = Label.Connect_InboundGift_ErrorDonorEmailNotFound;
            }
            if (donor == null) {
                item.result = InboundGiftResult.rejected(
                    InboundGiftResult.ERROR_DONOR_NOT_FOUND,
                    donorMissing
                );
                continue;
            }
            if (donor.getSObjectType() == Contact.SObjectType) {
                item.donorContactId = donor;
            } else {
                item.donorAccountId = donor;
            }

            if (String.isNotBlank(request.fundCode)) {
                item.fundId = fundByCode.get(request.fundCode.trim().toLowerCase());
            } else if (String.isNotBlank(request.fundId)) {
                Id named = InboundGiftRequest.asId(request.fundId);
                item.fundId = activeFunds.contains(named) ? named : null;
            }
            Boolean fundNamed =
                String.isNotBlank(request.fundCode) || String.isNotBlank(request.fundId);
            if (fundNamed && item.fundId == null) {
                item.result = InboundGiftResult.rejected(
                    InboundGiftResult.ERROR_FUND_NOT_FOUND,
                    Label.Connect_InboundGift_ErrorFundNotFound
                );
                continue;
            }

            if (String.isNotBlank(request.appealId)) {
                Id named = InboundGiftRequest.asId(request.appealId);
                if (!visibleAppeals.contains(named)) {
                    item.result = InboundGiftResult.rejected(
                        InboundGiftResult.ERROR_APPEAL_NOT_FOUND,
                        Label.Connect_InboundGift_ErrorAppealNotFound
                    );
                    continue;
                }
                item.appealId = named;
            }
        }
    }

    /**
     * Inserts the gifts, each on its own, then designates the ones that named a fund.
     *
     * The platform saves what it can and reports the rest per gift. Designation comes after the
     * insert, and a gift it cannot be applied to (one other automation already split) must not
     * stay recorded against the wrong fund, so that attempt is rolled back and made again without
     * it. Two attempts at most: the second can only fail the same way if more automation splits
     * more gifts, and then the rest are refused rather than retried forever.
     */
    private static void insertGifts(List<InboundGiftRequest> items) {
        List<InboundGiftRequest> remaining = items;
        List<InboundGiftRequest> duplicates = new List<InboundGiftRequest>();
        for (Integer attempt = 0; attempt < SAVE_ATTEMPTS && !remaining.isEmpty(); attempt++) {
            Savepoint beforeAttempt = Database.setSavepoint();
            List<Gift__c> gifts = new List<Gift__c>();
            for (InboundGiftRequest item : remaining) {
                gifts.add(item.toGift());
            }
            List<Database.SaveResult> saves;
            try {
                saves = Database.insert(gifts, false, AccessLevel.USER_MODE);
            } catch (Exception refused) {
                // User mode refuses the whole list when the integration user may not create
                // gifts at all: a setup problem, answered on every gift in the platform's words.
                for (InboundGiftRequest item : remaining) {
                    item.result = notSaved(refused.getMessage());
                }
                break;
            }

            List<InboundGiftRequest> saved = new List<InboundGiftRequest>();
            List<Gift__c> savedGifts = new List<Gift__c>();
            Map<Id, Id> fundByGift = new Map<Id, Id>();
            for (Integer index = 0; index < saves.size(); index++) {
                InboundGiftRequest item = remaining[index];
                if (saves[index].isSuccess()) {
                    item.giftId = gifts[index].Id;
                    saved.add(item);
                    savedGifts.add(gifts[index]);
                    if (item.fundId != null) {
                        fundByGift.put(item.giftId, item.fundId);
                    }
                } else if (isDuplicate(saves[index].getErrors())) {
                    duplicates.add(item);
                } else {
                    item.result = notSaved(messagesOf(saves[index].getErrors()));
                }
            }

            Set<Id> notApplied = GiftService.applyChosenFunds(savedGifts, fundByGift);
            if (notApplied.isEmpty()) {
                for (InboundGiftRequest item : saved) {
                    item.result = InboundGiftResult.recorded(
                        InboundGiftResult.OUTCOME_CREATED,
                        item.giftId,
                        Label.Connect_InboundGift_Created
                    );
                    item.recordedGiftId = item.giftId;
                    item.recordedAmount = item.request.amount;
                }
                remaining = new List<InboundGiftRequest>();
                break;
            }

            Database.rollback(beforeAttempt);
            List<InboundGiftRequest> next = new List<InboundGiftRequest>();
            for (InboundGiftRequest item : saved) {
                if (notApplied.contains(item.giftId)) {
                    item.result = InboundGiftResult.rejected(
                        InboundGiftResult.ERROR_NOT_SAVED,
                        Label.Connect_InboundGift_ErrorFundNotApplied
                    );
                } else {
                    next.add(item);
                }
                item.giftId = null;
            }
            remaining = next;
        }
        for (InboundGiftRequest item : remaining) {
            if (item.result == null) {
                item.result = InboundGiftResult.rejected(
                    InboundGiftResult.ERROR_NOT_SAVED,
                    Label.Connect_InboundGift_ErrorFundNotApplied
                );
            }
        }
        answerDuplicates(duplicates);
    }

    /**
     * Gifts the unique index refused: another request recorded the same external id between our
     * look and our save, or a gift the integration user cannot see already holds it. Looked up
     * again, and answered as a resend when it can be seen.
     */
    private static void answerDuplicates(List<InboundGiftRequest> duplicates) {
        if (duplicates.isEmpty()) {
            return;
        }
        Map<String, Gift__c> recorded = InboundGiftSelector.giftsByExternalId(
            externalIds(duplicates)
        );
        for (InboundGiftRequest item : duplicates) {
            Gift__c found = recorded.get(item.key);
            if (found != null) {
                answerFromRecordedGift(item, found);
            } else {
                item.result = InboundGiftResult.rejected(
                    InboundGiftResult.ERROR_CONFLICT,
                    Label.Connect_InboundGift_ErrorConflictUnseen
                );
            }
        }
    }

    /** A gift already carries this external id: the same gift sent again, or a conflict. */
    private static void answerFromRecordedGift(InboundGiftRequest item, Gift__c found) {
        item.recordedGiftId = found.Id;
        item.recordedAmount = found.Amount__c;
        if (found.Amount__c == item.request.amount) {
            item.result = InboundGiftResult.recorded(
                InboundGiftResult.OUTCOME_EXISTING,
                found.Id,
                Label.Connect_InboundGift_Existing
            );
        } else {
            item.result = InboundGiftResult.rejected(
                InboundGiftResult.ERROR_CONFLICT,
                Label.Connect_InboundGift_ErrorConflict
            );
            item.result.giftId = found.Id;
        }
    }

    /**
     * Every refusal, one Error Log line each at Warning, naming the external id and the error
     * code and nothing about the donor, so the nonprofit sees a gift that did not arrive.
     */
    private static void logRefusals(List<InboundGift> requests, List<InboundGiftResult> results) {
        List<String> lines = new List<String>();
        for (Integer index = 0; index < results.size(); index++) {
            InboundGiftResult result = results[index];
            if (result == null || result.outcome != InboundGiftResult.OUTCOME_REJECTED) {
                continue;
            }
            InboundGift request = index < requests.size() ? requests[index] : null;
            String externalId = request == null || String.isBlank(request.externalId)
                ? '-'
                : request.externalId.trim().abbreviate(MAX_EXTERNAL_ID);
            lines.add(
                String.format(
                    Label.Connect_InboundGift_LogRefused,
                    new List<String>{ externalId, result.errorCode, result.message }
                )
            );
        }
        ErrorLogger.logMessages(lines, CONTEXT, ErrorLogger.SEVERITY_WARNING);
    }

    private static Set<String> externalIds(List<InboundGiftRequest> items) {
        Set<String> values = new Set<String>();
        for (InboundGiftRequest item : items) {
            values.add(item.externalId);
        }
        return values;
    }

    private static Boolean isDuplicate(List<Database.Error> errors) {
        for (Database.Error error : errors) {
            if (error.getStatusCode() == StatusCode.DUPLICATE_VALUE) {
                return true;
            }
        }
        return false;
    }

    private static String messagesOf(List<Database.Error> errors) {
        List<String> messages = new List<String>();
        for (Database.Error error : errors) {
            messages.add(error.getMessage());
        }
        return String.join(messages, ' ');
    }

    private static void addIfOfType(Set<Id> target, String value, Schema.SObjectType expected) {
        Id parsed = InboundGiftRequest.asId(value);
        if (parsed != null && parsed.getSObjectType() == expected) {
            target.add(parsed);
        }
    }

    private static InboundGiftResult notSaved(String platformMessage) {
        return InboundGiftResult.rejected(
            InboundGiftResult.ERROR_NOT_SAVED,
            String.format(
                Label.Connect_InboundGift_ErrorNotSaved,
                new List<String>{ platformMessage }
            )
        );
    }
}

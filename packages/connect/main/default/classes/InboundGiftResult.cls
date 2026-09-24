/**
 * What became of one inbound gift (feature X-03): the REST response body and the output of the
 * Record Inbound Gift Flow action.
 *
 * Three outcomes and no fourth. `created`: this call recorded the gift. `existing`: an earlier
 * call did, and nothing changed. `rejected`: nothing was recorded, and `errorCode` says why in a
 * form a program can branch on. The four fields are `global` and permanent for the same reason
 * as `InboundGift` (ADR-0051); the codes and the status mapping below are `public`, so they stay
 * inside the package.
 */
global with sharing class InboundGiftResult {
    public static final String OUTCOME_CREATED = 'created';
    public static final String OUTCOME_EXISTING = 'existing';
    public static final String OUTCOME_REJECTED = 'rejected';

    public static final String ERROR_INVALID_REQUEST = 'invalid_request';
    public static final String ERROR_INVALID_FIELD = 'invalid_field';
    public static final String ERROR_CONFLICT = 'external_id_conflict';
    public static final String ERROR_DONOR_NOT_FOUND = 'donor_not_found';
    public static final String ERROR_FUND_NOT_FOUND = 'fund_not_found';
    public static final String ERROR_APPEAL_NOT_FOUND = 'appeal_not_found';
    public static final String ERROR_NOT_SAVED = 'gift_not_saved';
    public static final String ERROR_INTERNAL = 'internal_error';

    private static final Map<String, Integer> HTTP_STATUS_BY_ERROR = new Map<String, Integer>{
        ERROR_INVALID_REQUEST => 400,
        ERROR_INVALID_FIELD => 400,
        ERROR_CONFLICT => 409,
        ERROR_DONOR_NOT_FOUND => 422,
        ERROR_FUND_NOT_FOUND => 422,
        ERROR_APPEAL_NOT_FOUND => 422,
        ERROR_NOT_SAVED => 422
    };

    @InvocableVariable(label='Outcome' description='created, existing or rejected.')
    global String outcome;

    @InvocableVariable(
        label='Gift Id'
        description='The gift recorded, or already recorded under this external id.'
    )
    global Id giftId;

    @InvocableVariable(
        label='Error Code'
        description='Why the gift was rejected, as a stable code. Empty unless rejected.'
    )
    global String errorCode;

    @InvocableVariable(label='Message' description='What happened, in a sentence.')
    global String message;

    /** A gift that was recorded, by this call or an earlier one. */
    public static InboundGiftResult recorded(String outcome, Id giftId, String message) {
        InboundGiftResult result = new InboundGiftResult();
        result.outcome = outcome;
        result.giftId = giftId;
        result.message = message;
        return result;
    }

    /** A gift that was not recorded, and why. */
    public static InboundGiftResult rejected(String errorCode, String message) {
        InboundGiftResult result = new InboundGiftResult();
        result.outcome = OUTCOME_REJECTED;
        result.errorCode = errorCode;
        result.message = message;
        return result;
    }

    /** The HTTP status the REST endpoint answers a result with (docs/api/inbound-gift-api.md). */
    public static Integer httpStatus(InboundGiftResult result) {
        if (result == null) {
            return 500;
        }
        if (result.outcome == OUTCOME_CREATED) {
            return 201;
        }
        if (result.outcome == OUTCOME_EXISTING) {
            return 200;
        }
        Integer status = HTTP_STATUS_BY_ERROR.get(result.errorCode);
        return status == null ? 500 : status;
    }
}

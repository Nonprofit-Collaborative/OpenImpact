/**
 * One gift as another system describes it: the body of the inbound gift API and the input of
 * the Record Inbound Gift Flow action (feature X-03). One class carries both, so the two ways in
 * cannot drift apart in what they accept.
 *
 * `global` because a Flow in a subscriber org builds one and the REST body is read into it.
 * Every variable here is permanent once the package is managed (ADR-NEXT): a new optional
 * variable may be added, none may be removed or renamed. The rules applied to these values are
 * in `InboundGiftService` and the API reference, `docs/api/inbound-gift-api.md`.
 */
global with sharing class InboundGift {
    @InvocableVariable(
        label='External Id'
        description='The gift\'s identifier in the sending system. Required, and what makes sending it again safe.'
        required=true
    )
    global String externalId;

    @InvocableVariable(
        label='Amount'
        description='The amount received: greater than zero, at most two decimal places.'
        required=true
    )
    global Decimal amount;

    @InvocableVariable(
        label='Payment Method'
        description='Cash, Check, Card, ACH, Stock, Grant or Other.'
        required=true
    )
    global String paymentMethod;

    @InvocableVariable(
        label='Gift Date'
        description='The day the money arrived. Today when left empty.'
    )
    global Date giftDate;

    @InvocableVariable(
        label='Payment Reference'
        description='A check number, transaction id or deposit reference.'
    )
    global String paymentReference;

    @InvocableVariable(
        label='Donor Id'
        description='The record id of the person or organization who gave. Send this or Donor Email.'
    )
    global String donorId;

    @InvocableVariable(
        label='Donor Email'
        description='The email address of the person who gave. Send this or Donor Id.'
    )
    global String donorEmail;

    @InvocableVariable(
        label='Fund Accounting Code'
        description='The accounting code of the fund the gift is for. Empty means the default fund.'
    )
    global String fundCode;

    @InvocableVariable(
        label='Fund Id'
        description='The record id of the fund the gift is for, instead of its accounting code.'
    )
    global String fundId;

    @InvocableVariable(
        label='Appeal Id'
        description='The record id of the appeal the gift responds to.'
    )
    global String appealId;

    /** Flow, the REST endpoint and subscriber Apex each build a gift field by field. */
    global InboundGift() {
    }
}

/**
 * One gift as another system describes it (feature X-03).
 *
 * The shape is deliberately flat and deliberately ignorant of Open Impact's objects: a payment
 * processor knows an email address, an amount and a fund code, not a record identifier. The same
 * class carries the REST body and the Flow-invocable input, so the two surfaces cannot drift
 * apart in what they accept (plan Section 4.12).
 *
 * It is `global` because a Flow in a subscriber org builds one, which is the one place
 * ADR-0017 reserves that keyword for.
 */
global with sharing class GiftIntakeRequest {
    @InvocableVariable(
        label='External Id'
        description='The identifier this gift carries in your system. Required, and what makes a repeated send safe.'
        required=true
    )
    global String externalId;

    @InvocableVariable(label='Amount' description='The amount received, greater than zero.' required=true)
    global Decimal amount;

    @InvocableVariable(label='Gift Date' description='The date the money arrived. Defaults to today when left empty.')
    global Date giftDate;

    @InvocableVariable(
        label='Payment Method'
        description='How the gift arrived: Cash, Check, Card, ACH, Stock, In-kind, Grant or Other.'
        required=true
    )
    global String paymentMethod;

    @InvocableVariable(label='Payment Reference' description='The processor reference, check number or deposit reference.')
    global String paymentReference;

    @InvocableVariable(label='Donor Contact Id' description='The record identifier of the person who gave, when you hold it.')
    global String donorContactId;

    @InvocableVariable(label='Donor Account Id' description='The record identifier of the organization or person account that gave, when you hold it.')
    global String donorAccountId;

    @InvocableVariable(label='Donor Email' description='The email address of the person who gave. Must match exactly one person.')
    global String donorEmail;

    @InvocableVariable(label='Donor Organization Name' description='The name of the organization that gave. Must match exactly one organization.')
    global String donorOrganizationName;

    @InvocableVariable(label='Fund Id' description='The record identifier of the fund this gift is designated to.')
    global String fundId;

    @InvocableVariable(label='Fund Accounting Code' description='The accounting code of the fund this gift is designated to.')
    global String fundAccountingCode;

    @InvocableVariable(label='Fund Name' description='The name of the fund this gift is designated to.')
    global String fundName;

    @InvocableVariable(label='Appeal Id' description='The record identifier of the appeal this gift responded to.')
    global String appealId;

    @InvocableVariable(label='Appeal Name' description='The name of the appeal this gift responded to.')
    global String appealName;

    global GiftIntakeRequest() {
    }
}

/**
 * What happened to one inbound gift, written for the developer on the other end (feature X-03).
 *
 * Three outcomes and no fourth: the gift was created, it was already here and matched, or it was
 * rejected. A rejection always carries an error code that a program can branch on and a message a
 * person can read, and never carries an identifier, a stack trace or anything else about the
 * inside of the org (plan Section 4.13).
 */
global with sharing class GiftIntakeResult {
    global static final String OUTCOME_CREATED = 'created';
    global static final String OUTCOME_MATCHED = 'matched';
    global static final String OUTCOME_REJECTED = 'rejected';

    @InvocableVariable(label='Outcome' description='created, matched or rejected.')
    global String outcome;

    @InvocableVariable(label='Created' description='True only when this call is the one that recorded the gift.')
    global Boolean created;

    @InvocableVariable(label='External Id' description='The external id this result answers for.')
    global String externalId;

    @InvocableVariable(label='Gift Id' description='The gift that was created or matched.')
    global String giftId;

    @InvocableVariable(label='Gift Number' description='The gift number a person can look up, for example G-000123.')
    global String giftNumber;

    @InvocableVariable(label='Donor Contact Id' description='The person the gift was credited to.')
    global String donorContactId;

    @InvocableVariable(label='Donor Account Id' description='The account the gift was credited to.')
    global String donorAccountId;

    @InvocableVariable(label='Fund Id' description='The fund the gift was designated to.')
    global String fundId;

    @InvocableVariable(label='Amount' description='The amount recorded on the gift.')
    global Decimal amount;

    @InvocableVariable(label='Gift Date' description='The date recorded on the gift.')
    global Date giftDate;

    @InvocableVariable(label='Status Code' description='The HTTP status the REST endpoint returns for this outcome.')
    global Integer statusCode;

    @InvocableVariable(label='Error Code' description='A stable code to branch on, empty when the gift was accepted.')
    global String errorCode;

    @InvocableVariable(label='Message' description='What went wrong, or what was done, in words.')
    global String message;

    @InvocableVariable(
        label='Differences'
        description='Fields this call sent that differ from the gift already recorded, and were therefore ignored.'
    )
    global List<String> differences;

    global GiftIntakeResult() {
        this.differences = new List<String>();
    }
}

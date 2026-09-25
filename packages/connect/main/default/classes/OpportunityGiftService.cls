/**
 * The Opportunity mirror, Opportunities to Gifts (feature X-01, R-OM7): each won Opportunity
 * closed on or after the start date, that no gift names yet, becomes a gift.
 *
 * Called only by `OpportunityMirrorBatch`, one chunk at a time, as the person who started or
 * scheduled the run. Connect cannot hold a trigger on Opportunity (ADR-0013), so a run is how an
 * online gift written as an Opportunity reaches Open Impact.
 *
 * Gifts are ordinary gifts inserted in user mode with partial success, carrying the Opportunity
 * ID in the insert itself, so the unique attribute stops a second gift even when two runs
 * overlap and nothing needs undoing. Giving's own rules derive the household and allocate the
 * default fund. The mirror never edits a gift afterwards (ADR-0051, R-G4, R-G14).
 */
public with sharing class OpportunityGiftService {
    private static final String TYPE_OTHER = 'Other';
    private static final String STATUS_RECEIVED = 'Received';
    private static final String CAMPAIGN_FIELD = 'CampaignId';

    /** The fields a run reads from each won Opportunity, with Campaign where the org has it. */
    public static List<String> opportunityFields() {
        List<String> fields = new List<String>{ 'Id', 'Name', 'Amount', 'CloseDate', 'AccountId' };
        Schema.SObjectType opportunity = OpportunityMirrorService.opportunityType();
        if (
            opportunity != null &&
            opportunity.getDescribe().fields.getMap().containsKey(CAMPAIGN_FIELD.toLowerCase())
        ) {
            fields.add(CAMPAIGN_FIELD);
        }
        return fields;
    }

    /** The start date, or null while none is set, in which case no Opportunity becomes a gift. */
    public static Date startDate() {
        Connect_Settings__c settings = Connect_Settings__c.getOrgDefaults();
        return settings == null ||
            settings.Opportunity_Mirror_Start__c == null
            ? null
            : settings.Opportunity_Mirror_Start__c.date();
    }

    /**
     * Makes a gift from each of these won Opportunities that no gift names yet. Refusals stay on
     * the result, grouped by message, for the run to write once when it ends (R-OM6).
     */
    public static OpportunityMirrorService.Result makeGifts(List<SObject> opportunities) {
        OpportunityMirrorService.Result result = new OpportunityMirrorService.Result();
        if (opportunities == null || opportunities.isEmpty()) {
            return result;
        }
        Set<String> ids = new Set<String>();
        Set<Id> opportunityIds = new Set<Id>();
        Set<String> campaignIds = new Set<String>();
        Boolean hasCampaign = opportunityFields().contains(CAMPAIGN_FIELD);
        for (SObject opportunity : opportunities) {
            ids.add(String.valueOf(opportunity.Id));
            opportunityIds.add(opportunity.Id);
            Object campaign = hasCampaign ? opportunity.get(CAMPAIGN_FIELD) : null;
            if (campaign != null) {
                campaignIds.add(String.valueOf(campaign));
            }
        }
        Set<String> linked = OpportunityMirrorSelector.linkedOpportunityIds(ids);
        Map<Id, SObject> roles = OpportunityMirrorSelector.primaryRolesByOpportunity(
            OpportunityMirrorService.roleObjectName(),
            opportunityIds
        );
        Set<Id> contactIds = new Set<Id>();
        for (SObject role : roles.values()) {
            contactIds.add((Id) role.get('ContactId'));
        }
        Map<Id, Id> personAccounts = OpportunityMirrorSelector.personAccountByContact(contactIds);
        Map<String, Id> appeals = Appeal__c.Campaign_Id__c.getDescribe().isAccessible()
            ? OpportunityMirrorSelector.appealIdsByCampaignId(campaignIds)
            : new Map<String, Id>();

        List<Gift__c> gifts = new List<Gift__c>();
        List<SObject> madeFrom = new List<SObject>();
        for (SObject opportunity : opportunities) {
            if (linked.contains(String.valueOf(opportunity.Id))) {
                result.unchanged++;
                continue;
            }
            Decimal amount = (Decimal) opportunity.get('Amount');
            SObject role = roles.get(opportunity.Id);
            Id contactId = role == null ? null : (Id) role.get('ContactId');
            Id accountId = (Id) opportunity.get('AccountId');
            String refusal = amount == null ||
                amount <= 0
                ? Label.Connect_OpportunityMirror_AmountNotAboveZero
                : (contactId == null &&
                      accountId == null
                      ? Label.Connect_OpportunityMirror_NoDonor
                      : null);
            if (refusal != null) {
                result.failed++;
                result.refusals.add(refusal, (String) opportunity.get('Name'), opportunity.Id);
                continue;
            }
            Gift__c gift = new Gift__c(
                Amount__c = amount,
                Gift_Date__c = (Date) opportunity.get('CloseDate'),
                Type__c = TYPE_OTHER,
                Status__c = STATUS_RECEIVED,
                Opportunity_Id__c = String.valueOf(opportunity.Id)
            );
            // A person stored as an account is always named by the account (R-G1).
            if (contactId != null && personAccounts.containsKey(contactId)) {
                gift.Donor_Account__c = personAccounts.get(contactId);
            } else if (contactId != null) {
                gift.Donor_Contact__c = contactId;
            } else {
                gift.Donor_Account__c = accountId;
            }
            Object campaign = hasCampaign ? opportunity.get(CAMPAIGN_FIELD) : null;
            if (campaign != null) {
                gift.Appeal__c = appeals.get(String.valueOf(campaign));
            }
            gifts.add(gift);
            madeFrom.add(opportunity);
        }
        if (gifts.isEmpty()) {
            return result;
        }
        List<Database.SaveResult> saved = Database.insert(gifts, false, AccessLevel.USER_MODE);
        for (Integer i = 0; i < saved.size(); i++) {
            if (saved[i].isSuccess()) {
                result.created++;
                continue;
            }
            result.failed++;
            List<String> messages = new List<String>();
            for (Database.Error error : saved[i].getErrors()) {
                messages.add(error.getMessage());
            }
            result.refusals.add(
                String.join(messages, ' '),
                (String) madeFrom[i].get('Name'),
                madeFrom[i].Id
            );
        }
        return result;
    }
}

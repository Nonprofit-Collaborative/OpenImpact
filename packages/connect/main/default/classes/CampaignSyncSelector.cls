/**
 * The queries behind Campaign sync (feature X-02, canonical model Section 29B). Every one runs
 * in user mode: the copy is made with the access of the person saving the appeal or running
 * Sync all appeals, so a record they cannot see is a record the sync does not touch (R-CS4).
 *
 * Campaign is never named at compile time. Its queries are built from the object name the
 * service resolved through describe, so Connect compiles and installs where Campaign does not
 * exist (plan Section 4.2, ADR-0013).
 */
public with sharing class CampaignSyncSelector {
    /** The appeal attributes R-CS2 copies, plus the link. */
    public static final String APPEAL_FIELDS = 'Id, Name, Description__c, Start_Date__c, End_Date__c, Goal__c, Cost__c, Active__c, Parent_Appeal__c, Campaign_Id__c';

    /** The Campaign fields R-CS2 writes, read back to decide whether anything changed. */
    public static final String CAMPAIGN_FIELDS = 'Id, Name, Description, StartDate, EndDate, ExpectedRevenue, ActualCost, IsActive, ParentId';

    /** The Campaign ID of each of these appeals, keyed by appeal; an appeal with none is left out. */
    public static Map<Id, String> campaignIdsByAppealId(Set<Id> appealIds) {
        Map<Id, String> byAppeal = new Map<Id, String>();
        if (appealIds == null || appealIds.isEmpty()) {
            return byAppeal;
        }
        for (Appeal__c appeal : [
            SELECT Id, Campaign_Id__c
            FROM Appeal__c
            WHERE Id IN :appealIds AND Campaign_Id__c != NULL
            WITH USER_MODE
        ]) {
            byAppeal.put(appeal.Id, appeal.Campaign_Id__c);
        }
        return byAppeal;
    }

    /** The Campaigns with these identifiers that the running user can see, keyed by Id. */
    public static Map<Id, SObject> campaignsById(String campaignObject, Set<Id> campaignIds) {
        if (String.isBlank(campaignObject) || campaignIds == null || campaignIds.isEmpty()) {
            return new Map<Id, SObject>();
        }
        return new Map<Id, SObject>(
            Database.queryWithBinds(
                'SELECT ' +
                    CAMPAIGN_FIELDS +
                    ' FROM ' +
                    String.escapeSingleQuotes(campaignObject) +
                    ' WHERE Id IN :campaignIds',
                new Map<String, Object>{ 'campaignIds' => campaignIds },
                AccessLevel.USER_MODE
            )
        );
    }
}

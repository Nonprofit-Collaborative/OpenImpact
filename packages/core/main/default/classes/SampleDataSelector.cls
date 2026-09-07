/**
 * All SOQL for the sample data loader (C-10). No other class in this feature issues a
 * query directly (plan Section 9.3).
 */
public with sharing class SampleDataSelector {
    /**
     * The SampleData static resource, or null when it has not been deployed. Callers use
     * the Body field's toString() to get the JSON text.
     */
    public StaticResource getSampleDataResource() {
        List<StaticResource> resources = [
            SELECT Body
            FROM StaticResource
            WHERE Name = 'SampleData'
            WITH USER_MODE
            LIMIT 1
        ];
        return resources.isEmpty() ? null : resources[0];
    }

    public Integer countSampleHouseholds() {
        return [
            SELECT COUNT()
            FROM Account
            WHERE Sample_Data__c = TRUE AND RecordType.DeveloperName = 'Household'
            WITH USER_MODE
        ];
    }

    public Integer countSampleOrganizations() {
        return [
            SELECT COUNT()
            FROM Account
            WHERE Sample_Data__c = TRUE AND RecordType.DeveloperName = 'Organization'
            WITH USER_MODE
        ];
    }

    public Integer countSampleContacts() {
        return [SELECT COUNT() FROM Contact WHERE Sample_Data__c = TRUE WITH USER_MODE];
    }

    public List<Id> getSampleAccountIds() {
        List<Id> ids = new List<Id>();
        for (Account acct : [SELECT Id FROM Account WHERE Sample_Data__c = TRUE WITH USER_MODE]) {
            ids.add(acct.Id);
        }
        return ids;
    }

    public List<Id> getSampleContactIds() {
        List<Id> ids = new List<Id>();
        for (Contact con : [SELECT Id FROM Contact WHERE Sample_Data__c = TRUE WITH USER_MODE]) {
            ids.add(con.Id);
        }
        return ids;
    }

    /**
     * True while a SampleDataLoadQueueable chain is still queued or running, so the
     * status card can keep polling instead of reporting a partial load as finished.
     */
    public Boolean hasRunningLoadJob() {
        return ![
                SELECT Id
                FROM AsyncApexJob
                WHERE
                    ApexClass.Name = 'SampleDataLoadQueueable'
                    AND Status IN ('Queued', 'Preparing', 'Processing', 'Holding')
                WITH USER_MODE
                LIMIT 1
            ]
            .isEmpty();
    }
}

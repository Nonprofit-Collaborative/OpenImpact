/**
 * Loads the C-10 sample data set in a chain of queueable jobs, so that inserting
 * roughly 430 contacts (each running through the household naming and greeting
 * triggers) never risks the CPU limit of a single synchronous transaction.
 *
 * Stage 1 (constructed with just the JSON body): inserts every household and
 * organization Account, Sample_Data__c true, then enqueues stage 2 with the household
 * key to Id map and the flattened member list.
 *
 * Stage 2 (private constructor): inserts up to CONTACT_CHUNK_SIZE contacts, Sample_Data__c
 * true, AccountId set from the household key map, and re-enqueues itself with the next
 * chunk until every member has been inserted.
 */
public with sharing class SampleDataLoadQueueable implements Queueable {
    private final String jsonBody;
    private final ContactStage contactStage;

    /** Carries stage 2 (contact chunking) state from one queueable to the next. */
    private class ContactStage {
        private final Map<String, Id> householdIdsByKey;
        private final List<Object> pendingMembers;
        private final Integer chunkStart;

        private ContactStage(
            Map<String, Id> householdIdsByKey,
            List<Object> pendingMembers,
            Integer chunkStart
        ) {
            this.householdIdsByKey = householdIdsByKey;
            this.pendingMembers = pendingMembers;
            this.chunkStart = chunkStart;
        }
    }

    public SampleDataLoadQueueable(String jsonBody) {
        this.jsonBody = jsonBody;
        this.contactStage = null;
    }

    private SampleDataLoadQueueable(String jsonBody, ContactStage contactStage) {
        this.jsonBody = jsonBody;
        this.contactStage = contactStage;
    }

    public void execute(QueueableContext context) {
        try {
            if (contactStage != null) {
                runContactStage();
            } else {
                runHouseholdAndOrganizationStage();
            }
        } catch (Exception e) {
            ErrorLogger.log(e, 'SampleDataLoadQueueable');
            throw e;
        }
    }

    private void runHouseholdAndOrganizationStage() {
        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(jsonBody);
        List<Object> households = (List<Object>) data.get('households');
        List<Object> organizations = (List<Object>) data.get('organizations');

        Id householdRecordTypeId = recordTypeId(Account.SObjectType, 'Household');
        Id organizationRecordTypeId = recordTypeId(Account.SObjectType, 'Organization');

        List<Account> householdAccounts = new List<Account>();
        List<String> householdKeys = new List<String>();
        for (Object householdEntry : households) {
            Map<String, Object> household = (Map<String, Object>) householdEntry;
            householdAccounts.add(buildHouseholdAccount(household, householdRecordTypeId));
            householdKeys.add((String) household.get('key'));
        }

        List<Account> organizationAccounts = new List<Account>();
        for (Object organizationEntry : organizations) {
            Map<String, Object> organization = (Map<String, Object>) organizationEntry;
            organizationAccounts.add(
                buildOrganizationAccount(organization, organizationRecordTypeId)
            );
        }

        List<Account> allAccounts = new List<Account>();
        allAccounts.addAll(householdAccounts);
        allAccounts.addAll(organizationAccounts);
        Database.insert(allAccounts, AccessLevel.USER_MODE);

        Map<String, Id> keysToIds = new Map<String, Id>();
        for (Integer i = 0; i < householdAccounts.size(); i++) {
            keysToIds.put(householdKeys[i], householdAccounts[i].Id);
        }

        List<Object> flattenedMembers = new List<Object>();
        for (Object householdEntry : households) {
            Map<String, Object> household = (Map<String, Object>) householdEntry;
            String key = (String) household.get('key');
            List<Object> members = (List<Object>) household.get('members');
            for (Object memberEntry : members) {
                Map<String, Object> member = (Map<String, Object>) memberEntry;
                member.put('householdKey', key);
                flattenedMembers.add(member);
            }
        }

        if (!flattenedMembers.isEmpty()) {
            System.enqueueJob(
                new SampleDataLoadQueueable(
                    jsonBody,
                    new ContactStage(keysToIds, flattenedMembers, 0)
                )
            );
        }
    }

    private void runContactStage() {
        Map<String, Id> householdIdsByKey = contactStage.householdIdsByKey;
        List<Object> pendingMembers = contactStage.pendingMembers;
        Integer chunkStart = contactStage.chunkStart;

        Id contactRecordTypeId = recordTypeId(Contact.SObjectType, 'Household_Contact');
        Integer chunkEnd = Math.min(
            chunkStart + SampleDataLoader.CONTACT_CHUNK_SIZE,
            pendingMembers.size()
        );

        List<Contact> contactsToInsert = new List<Contact>();
        for (Integer i = chunkStart; i < chunkEnd; i++) {
            Map<String, Object> member = (Map<String, Object>) pendingMembers[i];
            contactsToInsert.add(buildContact(member, householdIdsByKey, contactRecordTypeId));
        }
        Database.insert(contactsToInsert, AccessLevel.USER_MODE);

        if (chunkEnd < pendingMembers.size()) {
            System.enqueueJob(
                new SampleDataLoadQueueable(
                    jsonBody,
                    new ContactStage(householdIdsByKey, pendingMembers, chunkEnd)
                )
            );
        }
    }

    private Account buildHouseholdAccount(Map<String, Object> household, Id recordTypeId) {
        Account acct = new Account();
        acct.RecordTypeId = recordTypeId;
        acct.Sample_Data__c = true;

        Map<String, Object> address = (Map<String, Object>) household.get('address');
        if (address != null) {
            acct.BillingStreet = (String) address.get('street');
            acct.BillingCity = (String) address.get('city');
            acct.BillingState = (String) address.get('state');
            acct.BillingPostalCode = (String) address.get('postalCode');
        }

        Object anniversary = household.get('anniversary');
        if (anniversary != null) {
            acct.Anniversary__c = Date.valueOf((String) anniversary);
        }

        Boolean customName = household.get('customName') == true;
        if (customName) {
            // The household naming trigger never recomputes a Custom_Name__c household
            // (canonical model rule R-H8), so the generator's chosen wording is final.
            acct.Custom_Name__c = true;
            acct.Name = (String) household.get('name');
        } else {
            // Placeholder; the household naming trigger recomputes Name, the formal
            // greeting, and the informal greeting once members are attached (R-H4).
            acct.Name = 'Household';
        }
        return acct;
    }

    private Account buildOrganizationAccount(Map<String, Object> organization, Id recordTypeId) {
        Account acct = new Account();
        acct.RecordTypeId = recordTypeId;
        acct.Sample_Data__c = true;
        acct.Name = (String) organization.get('name');
        acct.Website = (String) organization.get('website');
        acct.Phone = (String) organization.get('phone');
        return acct;
    }

    private Contact buildContact(
        Map<String, Object> member,
        Map<String, Id> householdIdsByKey,
        Id recordTypeId
    ) {
        Contact con = new Contact();
        con.RecordTypeId = recordTypeId;
        con.Sample_Data__c = true;
        con.AccountId = householdIdsByKey.get((String) member.get('householdKey'));
        con.FirstName = (String) member.get('firstName');
        con.LastName = (String) member.get('lastName');
        con.Salutation = (String) member.get('salutation');
        con.Household_Role__c = (String) member.get('householdRole');
        con.Email = (String) member.get('email');
        con.Phone = (String) member.get('phone');
        con.MailingStreet = (String) member.get('mailingStreet');
        con.MailingCity = (String) member.get('mailingCity');
        con.MailingState = (String) member.get('mailingState');
        con.MailingPostalCode = (String) member.get('mailingPostalCode');

        Object birthdate = member.get('birthdate');
        if (birthdate != null) {
            con.Birthdate = Date.valueOf((String) birthdate);
        }
        Object preferredName = member.get('preferredName');
        if (preferredName != null) {
            con.Preferred_Name__c = (String) preferredName;
        }
        if (member.get('deceased') == true) {
            con.Deceased__c = true;
        }
        return con;
    }

    private static Id recordTypeId(Schema.SObjectType sobjectType, String developerName) {
        // DEFERRED skips loading child relationships this method never uses. NOPMD:
        // EagerlyLoadedDescribeSObjectResult flags any getDescribe() call regardless of
        // the DEFERRED option, which is the rule's own recommended fix.
        Schema.DescribeSObjectResult describeResult = sobjectType.getDescribe( // NOPMD
            Schema.SObjectDescribeOptions.DEFERRED
        );
        Map<String, Schema.RecordTypeInfo> infosByDeveloperName = describeResult.getRecordTypeInfosByDeveloperName();
        Schema.RecordTypeInfo info = infosByDeveloperName.get(developerName);
        if (info == null) {
            throw new SampleDataException(
                String.format(
                    Label.Core_SampleData_RecordTypeMissing,
                    new List<Object>{ developerName }
                )
            );
        }
        return info.getRecordTypeId();
    }
}

/**
 * The queries behind the Opportunity mirror (feature X-01, canonical model Section 29C). Every
 * one runs in user mode: the copy is made with the access of the person saving the gift or
 * running the mirror, so a record they cannot see is a record the mirror does not touch (R-OM5).
 *
 * Opportunity, its contact roles and its stages are never named at compile time. Their queries
 * are built from the object names the service resolved through describe, so Connect compiles and
 * installs where they do not exist (plan Section 4.2, ADR-0013).
 */
public with sharing class OpportunityMirrorSelector {
    /** The gift attributes R-OM3 copies, plus the link. */
    public static final String GIFT_FIELDS = 'Id, Name, Amount__c, Gift_Date__c, Status__c, Donor_Contact__c, Donor_Account__c, Household__c, Appeal__c, Opportunity_Id__c';

    // detection-only: stage records are read by name so Connect installs without Opportunity
    private static final String STAGE_OBJECT = 'OpportunityStage';
    private static final String PERSON_CONTACT_FIELD = 'PersonContactId';

    /**
     * The Opportunities with these identifiers that the running user can see, keyed by Id.
     *
     * @param fields the fields to read, from the service, which knows which ones the org has
     */
    public static Map<Id, SObject> opportunitiesById(
        String opportunityObject,
        List<String> fields,
        Set<Id> ids
    ) {
        if (String.isBlank(opportunityObject) || ids == null || ids.isEmpty()) {
            return new Map<Id, SObject>();
        }
        return new Map<Id, SObject>(
            Database.queryWithBinds(
                'SELECT ' +
                    String.escapeSingleQuotes(String.join(fields, ', ')) +
                    ' FROM ' +
                    String.escapeSingleQuotes(opportunityObject) +
                    ' WHERE Id IN :ids',
                new Map<String, Object>{ 'ids' => ids },
                AccessLevel.USER_MODE
            )
        );
    }

    /** The primary contact role of each of these Opportunities, keyed by Opportunity. */
    public static Map<Id, SObject> primaryRolesByOpportunity(String roleObject, Set<Id> ids) {
        Map<Id, SObject> byOpportunity = new Map<Id, SObject>();
        if (String.isBlank(roleObject) || ids == null || ids.isEmpty()) {
            return byOpportunity;
        }
        for (
            SObject role : Database.queryWithBinds(
                'SELECT Id, OpportunityId, ContactId FROM ' +
                    String.escapeSingleQuotes(roleObject) +
                    ' WHERE OpportunityId IN :ids AND IsPrimary = TRUE',
                new Map<String, Object>{ 'ids' => ids },
                AccessLevel.USER_MODE
            )
        ) {
            byOpportunity.put((Id) role.get('OpportunityId'), role);
        }
        return byOpportunity;
    }

    /** The org's active Opportunity stages, in the order the org sorts them. */
    public static List<SObject> activeStages() {
        return Database.query(
            'SELECT ApiName, IsWon, IsClosed, SortOrder FROM ' +
                STAGE_OBJECT +
                ' WHERE IsActive = TRUE ORDER BY SortOrder',
            AccessLevel.USER_MODE
        );
    }

    /** The name of each of these people and accounts that the running user can see. */
    public static Map<Id, String> namesById(Set<Id> contactIds, Set<Id> accountIds) {
        Map<Id, String> names = new Map<Id, String>();
        if (contactIds != null && !contactIds.isEmpty()) {
            for (Contact person : [
                SELECT Id, Name
                FROM Contact
                WHERE Id IN :contactIds
                WITH USER_MODE
            ]) {
                names.put(person.Id, person.Name);
            }
        }
        if (accountIds != null && !accountIds.isEmpty()) {
            for (Account account : [
                SELECT Id, Name
                FROM Account
                WHERE Id IN :accountIds
                WITH USER_MODE
            ]) {
                names.put(account.Id, account.Name);
            }
        }
        return names;
    }

    /**
     * The contact behind each of these accounts that holds a person, by account. Empty in an org
     * that does not store people as accounts, where the field does not exist.
     */
    public static Map<Id, Id> personContactIds(Set<Id> accountIds) {
        Map<Id, Id> byAccount = new Map<Id, Id>();
        if (
            accountIds == null ||
            accountIds.isEmpty() ||
            !Schema.SObjectType.Account.fields.getMap().containsKey(PERSON_CONTACT_FIELD)
        ) {
            return byAccount;
        }
        for (
            SObject account : Database.queryWithBinds(
                'SELECT Id, ' +
                    PERSON_CONTACT_FIELD +
                    ' FROM Account WHERE Id IN :accountIds AND ' +
                    PERSON_CONTACT_FIELD +
                    ' != NULL',
                new Map<String, Object>{ 'accountIds' => accountIds },
                AccessLevel.USER_MODE
            )
        ) {
            byAccount.put(account.Id, (Id) account.get(PERSON_CONTACT_FIELD));
        }
        return byAccount;
    }

    /** The same, without the linked gifts changed since the last run. */
    public static String giftsToCopyQuery(Boolean inRange) {
        return giftsToCopyQuery(inRange, false);
    }

    /**
     * The gifts a Gifts to Opportunities run copies (R-OM8, R-OM11). Without a range: those in the
     * totals with no Opportunity, and, when `sinceLastRun`, every linked gift changed since the
     * last completed run started (bind `since`), which puts right a change whose copy was skipped.
     * Given a range (binds `fromDate`, `toDate`): every gift dated in it that is in the totals or
     * linked, so a Cancelled gift's Opportunity is moved to the lost stage too.
     */
    public static String giftsToCopyQuery(Boolean inRange, Boolean sinceLastRun) {
        String query = 'SELECT ' + GIFT_FIELDS + ' FROM Gift__c WHERE ';
        if (inRange == true) {
            query +=
                'Gift_Date__c >= :fromDate AND Gift_Date__c <= :toDate' +
                ' AND (Status__c IN :statuses OR Opportunity_Id__c != NULL)';
        } else {
            query += '(Opportunity_Id__c = NULL AND Status__c IN :statuses)';
            if (sinceLastRun == true) {
                query += ' OR (Opportunity_Id__c != NULL AND LastModifiedDate >= :since)';
            }
        }
        return query + ' ORDER BY Gift_Date__c, Id';
    }
}

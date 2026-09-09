/**
 * All SOQL the inbound gift API runs against Contact and Account, in user mode.
 *
 * The one dynamic query in this package is here. An org that stores people as accounts holds
 * their email address on a field that only exists in that kind of org, so the field cannot be
 * named at compile time. The query text is a constant, the address is passed as a bind, and the
 * whole path is skipped unless the org is shaped that way and the field is really present, which
 * is the same treatment Core gives the person name fields in PersonRecordSelector.
 */
public with sharing class ConnectDonorSelector {
    private static final String ORGANIZATION_RECORD_TYPE = 'Organization';

    // The email field that exists on the account object only where the org stores people as
    // accounts. Held as text and read through describe, never referenced statically.
    private static final String PERSON_EMAIL_FIELD = 'PersonEmail';

    private static final String PERSON_EMAIL_QUERY =
        'SELECT Id, PersonEmail FROM Account WHERE PersonEmail IN :emails LIMIT 200';

    public static Map<Id, Contact> selectContactsById(Set<Id> contactIds) {
        if (contactIds == null || contactIds.isEmpty()) {
            return new Map<Id, Contact>();
        }
        return new Map<Id, Contact>(
            [SELECT Id FROM Contact WHERE Id IN :contactIds WITH USER_MODE LIMIT 500]
        );
    }

    public static Map<Id, Account> selectAccountsById(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new Map<Id, Account>();
        }
        return new Map<Id, Account>(
            [SELECT Id FROM Account WHERE Id IN :accountIds WITH USER_MODE LIMIT 500]
        );
    }

    /**
     * People whose email address is one of these. Email matching is case insensitive on the
     * platform, and the resolver lowercases both sides before counting, so a processor sending a
     * differently cased address still finds the one person.
     */
    public static List<Contact> selectContactsByEmail(Set<String> emails) {
        if (emails == null || emails.isEmpty()) {
            return new List<Contact>();
        }
        return [
            SELECT Id, Email
            FROM Contact
            WHERE Email IN :emails AND Email != NULL
            WITH USER_MODE
            LIMIT 200
        ];
    }

    /**
     * Organizations by name. Households are excluded: a gift credited to a household account is
     * an app decision that needs a person looking at it, not something an inbound feed guesses
     * from a name.
     */
    public static List<Account> selectOrganizationsByName(Set<String> names) {
        if (names == null || names.isEmpty()) {
            return new List<Account>();
        }
        return [
            SELECT Id, Name
            FROM Account
            WHERE Name IN :names AND RecordType.DeveloperName = :ORGANIZATION_RECORD_TYPE
            WITH USER_MODE
            LIMIT 200
        ];
    }

    /**
     * People held as account records whose email address is one of these, keyed by the lowercased
     * address, in the orgs that are shaped that way. Empty everywhere else, so a caller sending an
     * email address is answered the same way whichever kind of org is on the other end.
     *
     * The address is read out of the values the record actually carries rather than from a named
     * field, which is what keeps this class compiling in an org where the field is absent.
     */
    public static Map<String, List<Id>> selectPersonAccountIdsByEmail(Set<String> emails) {
        Map<String, List<Id>> found = new Map<String, List<Id>>();
        if (emails == null || emails.isEmpty() || !HouseholdService.isPersonAccountOrg()) {
            return found;
        }
        if (!Schema.SObjectType.Account.fields.getMap().containsKey(PERSON_EMAIL_FIELD)) {
            return found;
        }
        Map<String, Object> binds = new Map<String, Object>{ 'emails' => emails };
        for (
            SObject record : Database.queryWithBinds(PERSON_EMAIL_QUERY, binds, AccessLevel.USER_MODE)
        ) {
            Object address = record.getPopulatedFieldsAsMap().get(PERSON_EMAIL_FIELD);
            if (address == null) {
                continue;
            }
            String key = String.valueOf(address).toLowerCase();
            if (!found.containsKey(key)) {
                found.put(key, new List<Id>());
            }
            found.get(key).add(record.Id);
        }
        return found;
    }
}

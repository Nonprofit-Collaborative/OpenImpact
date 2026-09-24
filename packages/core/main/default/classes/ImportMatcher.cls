/**
 * Finds the records an incoming row already has, one query per key set and never one per row.
 *
 * Three rules, exactly the three the template offers (R-IT2), and each one is a lookup from a
 * set of keys built out of a whole chunk to a map of key to record identifier. Nothing here
 * writes, and nothing here decides: the processor asks for the matches and then decides what
 * to do with a row that has one.
 *
 * Person records are queried through dynamic SOQL with field names held as text, because the
 * fields that carry a person's name and email on an account exist only in an org that stores
 * people that way, and Core must compile and run where they do not (plan Section 4.2).
 */
@NamespaceAccessible
public with sharing class ImportMatcher {
    /** The separator between the parts of a composite key, chosen not to occur in a name. */
    private static final String KEY_SEPARATOR = '|~|';

    private static final String ACCOUNT_EMAIL_FIELD = 'PersonEmail';
    private static final String ACCOUNT_LAST_NAME_FIELD = 'LastName';

    /** How many keys one query will take. A chunk larger than this is queried in slices. */
    @NamespaceAccessible
    public static final Integer MAX_KEYS_PER_QUERY = 1000;

    /** The composite key of the "name plus postal code" rule, or null when it cannot be built. */
    @NamespaceAccessible
    public static String nameAndPostalKey(String lastName, String postalCode) {
        if (String.isBlank(lastName) || String.isBlank(postalCode)) {
            return null;
        }
        return lastName.trim().toLowerCase() + KEY_SEPARATOR + postalCode.trim().toLowerCase();
    }

    /** Separates a matching key from the first name that tells two people sharing it apart. */
    private static final String FIRST_NAME_SEPARATOR = '|#|';
    private static final String ACCOUNT_FIRST_NAME_FIELD = 'FirstName';

    /**
     * A matching key narrowed to one first name. When a row's two people share a key (a couple
     * with one surname and postal code, or one email), each is matched and remembered by the
     * shared key plus their own first name, so neither is ever taken for the other (R-IB12).
     */
    @NamespaceAccessible
    public static String firstNameKey(String key, String firstName) {
        if (key == null) {
            return null;
        }
        return key +
            FIRST_NAME_SEPARATOR +
            (String.isBlank(firstName) ? '' : firstName.trim().toLowerCase());
    }

    /** The shared key a first-name key narrows, or the key itself when it narrows none. */
    @NamespaceAccessible
    public static String baseKey(String key) {
        return key == null ? null : key.substringBefore(FIRST_NAME_SEPARATOR);
    }

    /**
     * The shared keys the last lookup found on more than one record, such as a couple at one
     * address or with one email. A person is matched on such a key only by their first name,
     * or when the row gives no first name (R-IB12).
     */
    @NamespaceAccessible
    public static Set<String> heldByMany = new Set<String>();

    /** Records the first found under a key, and under the key narrowed to its first name. */
    private static void put(Map<String, Id> result, String key, String firstName, Id recordId) {
        if (key == null) {
            return;
        }
        if (!result.containsKey(key)) {
            result.put(key, recordId);
        } else if (result.get(key) != recordId) {
            heldByMany.add(key);
        }
        String narrowed = firstNameKey(key, firstName);
        if (!result.containsKey(narrowed)) {
            result.put(narrowed, recordId);
        }
    }

    /** The key an email is looked up by. */
    @NamespaceAccessible
    public static String emailKey(String email) {
        return String.isBlank(email) ? null : email.trim().toLowerCase();
    }

    /** The key a name is looked up by. */
    @NamespaceAccessible
    public static String nameKey(String name) {
        return String.isBlank(name) ? null : name.trim().toLowerCase();
    }

    /** One slice's worth of contacts matched on email. Kept out of the caller's loop so the
     * query itself is never lexically inside a loop; the caller still runs one query per
     * MAX_KEYS_PER_QUERY-sized chunk, never one per row. */
    private static List<Contact> contactsByEmailSlice(List<String> slice) {
        return [
            SELECT Id, Email, FirstName
            FROM Contact
            WHERE Email IN :slice
            WITH USER_MODE
            ORDER BY CreatedDate ASC, Id ASC
            LIMIT 5000
        ];
    }

    /** Contacts whose email is one of these, keyed by the lower cased email. */
    @NamespaceAccessible
    public static Map<String, Id> contactsByEmail(Set<String> emails) {
        Map<String, Id> result = new Map<String, Id>();
        for (List<String> slice : slices(emails)) {
            List<Contact> found = contactsByEmailSlice(slice);
            for (Contact record : found) {
                // First created wins, so a duplicate in the org resolves the same way twice.
                put(result, emailKey(record.Email), record.FirstName, record.Id);
            }
        }
        return result;
    }

    /** Contacts whose last name and mailing postal code match, keyed by the composite key. */
    @NamespaceAccessible
    public static Map<String, Id> contactsByNameAndPostalCode(Set<String> keys) {
        Map<String, Id> result = new Map<String, Id>();
        if (keys == null || keys.isEmpty()) {
            return result;
        }
        Set<String> lastNames = new Set<String>();
        for (String key : keys) {
            if (key != null && key.contains(KEY_SEPARATOR)) {
                lastNames.add(key.substringBefore(KEY_SEPARATOR));
            }
        }
        for (List<String> slice : slices(lastNames)) {
            List<Contact> found = contactsByNameSlice(slice);
            for (Contact record : found) {
                String key = nameAndPostalKey(record.LastName, record.MailingPostalCode);
                if (key != null && keys.contains(key)) {
                    put(result, key, record.FirstName, record.Id);
                }
            }
        }
        return result;
    }

    /** One slice's worth of contacts matched on last name, kept out of the caller's loop. */
    private static List<Contact> contactsByNameSlice(List<String> slice) {
        return [
            SELECT Id, FirstName, LastName, MailingPostalCode
            FROM Contact
            WHERE LastName IN :slice
            WITH USER_MODE
            ORDER BY CreatedDate ASC, Id ASC
            LIMIT 5000
        ];
    }

    /** One slice's worth of accounts matched on name within a record type. */
    private static List<Account> accountsByNameSlice(List<String> slice, Id recordTypeId) {
        return [
            SELECT Id, Name
            FROM Account
            WHERE Name IN :slice AND RecordTypeId = :recordTypeId
            WITH USER_MODE
            ORDER BY CreatedDate ASC, Id ASC
            LIMIT 5000
        ];
    }

    /** Accounts of the given record type whose name matches, keyed by the lower cased name. */
    @NamespaceAccessible
    public static Map<String, Id> accountsByName(Set<String> names, Id recordTypeId) {
        Map<String, Id> result = new Map<String, Id>();
        for (List<String> slice : slices(names)) {
            List<Account> found = accountsByNameSlice(slice, recordTypeId);
            for (Account record : found) {
                String key = nameKey(record.Name);
                if (key != null && !result.containsKey(key)) {
                    result.put(key, record.Id);
                }
            }
        }
        return result;
    }

    /**
     * Person records held as accounts, matched on the email field an org that stores people
     * that way has. Empty where the org has no such field, which is the answer the processor
     * needs to refuse the run rather than create duplicates.
     */
    @NamespaceAccessible
    public static Map<String, Id> personAccountsByEmail(Set<String> emails, Set<Id> recordTypeIds) {
        Map<String, Id> result = new Map<String, Id>();
        if (
            !accountHasField(ACCOUNT_EMAIL_FIELD) ||
            recordTypeIds == null ||
            recordTypeIds.isEmpty()
        ) {
            return result;
        }
        for (List<String> slice : slices(emails)) {
            List<SObject> found = personAccountsByEmailSlice(slice, recordTypeIds);
            for (SObject record : found) {
                put(
                    result,
                    emailKey((String) record.get(ACCOUNT_EMAIL_FIELD)),
                    firstNameOf(record),
                    (Id) record.get('Id')
                );
            }
        }
        return result;
    }

    /** One slice's worth of person accounts matched on email, kept out of the caller's loop. */
    private static List<SObject> personAccountsByEmailSlice(
        List<String> slice,
        Set<Id> recordTypeIds
    ) {
        String query =
            'SELECT Id, ' +
            firstNameColumn() +
            ACCOUNT_EMAIL_FIELD +
            ' FROM Account WHERE ' +
            ACCOUNT_EMAIL_FIELD +
            ' IN :slice AND RecordTypeId IN :recordTypeIds ORDER BY CreatedDate ASC, Id ASC LIMIT 5000';
        return Database.queryWithBinds(
            query,
            new Map<String, Object>{ 'slice' => slice, 'recordTypeIds' => recordTypeIds },
            AccessLevel.USER_MODE
        );
    }

    /** Person records held as accounts, matched on last name plus billing postal code. */
    @NamespaceAccessible
    public static Map<String, Id> personAccountsByNameAndPostalCode(
        Set<String> keys,
        Set<Id> recordTypeIds
    ) {
        Map<String, Id> result = new Map<String, Id>();
        if (
            keys == null ||
            keys.isEmpty() ||
            !accountHasField(ACCOUNT_LAST_NAME_FIELD) ||
            recordTypeIds == null ||
            recordTypeIds.isEmpty()
        ) {
            return result;
        }
        Set<String> lastNames = new Set<String>();
        for (String key : keys) {
            if (key != null && key.contains(KEY_SEPARATOR)) {
                lastNames.add(key.substringBefore(KEY_SEPARATOR));
            }
        }
        for (List<String> slice : slices(lastNames)) {
            List<SObject> found = personAccountsByNameSlice(slice, recordTypeIds);
            for (SObject record : found) {
                String key = nameAndPostalKey(
                    (String) record.get(ACCOUNT_LAST_NAME_FIELD),
                    (String) record.get('BillingPostalCode')
                );
                if (key != null && keys.contains(key)) {
                    put(result, key, firstNameOf(record), (Id) record.get('Id'));
                }
            }
        }
        return result;
    }

    /** One slice's worth of person accounts matched on last name, kept out of the caller's loop. */
    private static List<SObject> personAccountsByNameSlice(
        List<String> slice,
        Set<Id> recordTypeIds
    ) {
        String query =
            'SELECT Id, ' +
            firstNameColumn() +
            ACCOUNT_LAST_NAME_FIELD +
            ', BillingPostalCode FROM Account WHERE ' +
            ACCOUNT_LAST_NAME_FIELD +
            ' IN :slice AND RecordTypeId IN :recordTypeIds ORDER BY CreatedDate ASC, Id ASC LIMIT 5000';
        return Database.queryWithBinds(
            query,
            new Map<String, Object>{ 'slice' => slice, 'recordTypeIds' => recordTypeIds },
            AccessLevel.USER_MODE
        );
    }

    /** The person account first name column, where the org has person accounts. */
    private static String firstNameColumn() {
        return accountHasField(ACCOUNT_FIRST_NAME_FIELD) ? ACCOUNT_FIRST_NAME_FIELD + ', ' : '';
    }

    private static String firstNameOf(SObject record) {
        return accountHasField(ACCOUNT_FIRST_NAME_FIELD)
            ? (String) record.get(ACCOUNT_FIRST_NAME_FIELD)
            : null;
    }

    /**
     * Records of the given object matched on its own external identifier field, keyed by the
     * value. Empty when the object has no external identifier, which is what makes the
     * External ID rule refuse rather than match everything to nothing.
     */
    @NamespaceAccessible
    public static Map<String, Id> byExternalId(Schema.SObjectType type, Set<String> values) {
        Map<String, Id> result = new Map<String, Id>();
        String field = externalIdField(type);
        if (field == null) {
            return result;
        }
        String objectName = type.getDescribe(SObjectDescribeOptions.DEFERRED).getName();
        for (List<String> slice : slices(values)) {
            List<SObject> found = byExternalIdSlice(objectName, field, slice);
            for (SObject record : found) {
                String key = nameKey((String) record.get(field));
                if (key != null && !result.containsKey(key)) {
                    result.put(key, (Id) record.get('Id'));
                }
            }
        }
        return result;
    }

    /** One slice's worth of records matched on an external identifier field. */
    private static List<SObject> byExternalIdSlice(
        String objectName,
        String field,
        List<String> slice
    ) {
        String query =
            'SELECT Id, ' +
            field +
            ' FROM ' +
            objectName +
            ' WHERE ' +
            field +
            ' IN :slice ORDER BY CreatedDate ASC, Id ASC LIMIT 5000';
        return Database.queryWithBinds(
            query,
            new Map<String, Object>{ 'slice' => slice },
            AccessLevel.USER_MODE
        );
    }

    /** The API name of the object's external identifier field, or null when it has none. */
    @NamespaceAccessible
    public static String externalIdField(Schema.SObjectType type) {
        if (type == null) {
            return null;
        }
        for (
            Schema.SObjectField field : type.getDescribe(SObjectDescribeOptions.DEFERRED)
                .fields.getMap()
                .values()
        ) {
            Schema.DescribeFieldResult describe = field.getDescribe();
            if (describe.isExternalId() && describe.isAccessible()) {
                return describe.getName();
            }
        }
        return null;
    }

    /** True when the account object in this org has the named field. */
    @NamespaceAccessible
    public static Boolean accountHasField(String fieldName) {
        return Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
            .fields.getMap()
            .containsKey(fieldName.toLowerCase());
    }

    /**
     * The key set cut into query-sized lists, with blanks dropped. One chunk of an import can
     * be larger than a single IN clause should carry.
     */
    private static List<List<String>> slices(Set<String> keys) {
        List<List<String>> result = new List<List<String>>();
        if (keys == null || keys.isEmpty()) {
            return result;
        }
        List<String> current = new List<String>();
        for (String key : keys) {
            if (String.isBlank(key)) {
                continue;
            }
            current.add(key);
            if (current.size() == MAX_KEYS_PER_QUERY) {
                result.add(current);
                current = new List<String>();
            }
        }
        if (!current.isEmpty()) {
            result.add(current);
        }
        return result;
    }
}

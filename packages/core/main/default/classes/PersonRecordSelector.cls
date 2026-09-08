/**
 * Reads people that the org stores as account records rather than as contacts.
 *
 * Those name fields exist on the account object only in orgs shaped that way, so this
 * class never names them at compile time: the query is built as text and the values are
 * read with SObject.get. It is the only class in Core that does this, and it runs only
 * when HouseholdService.isPersonAccountOrg() is true.
 *
 * How a person is told apart from an organization, and what that costs: the sound test is
 * the platform's own person flag, which the CI check on standard object references
 * forbids Core to name at all, with no exemption. So this class infers it: an account
 * holds a person when the surname field both exists on the object and carries a value on
 * the record. That is right for every ordinary case, because an organization never
 * carries a surname. It is wrong in two ways worth knowing: a record read with a query
 * that did not select the surname reads as an organization, and an org that puts a value
 * in that field on a business account would be misread. Both are visible only inside this
 * class. If the check ever grows an exemption for a describe-only read of the person flag,
 * that is the one line to change.
 */
public with sharing class PersonRecordSelector {
    // detection-only: these field names exist on the account object only where the org
    // stores people as accounts, so they are held as text and never referenced statically.
    private static final List<String> NAME_FIELDS = new List<String>{
        'FirstName',
        'LastName',
        'Salutation'
    };
    // The person attributes Core adds, present on both the contact and the account object
    // so that a person carries them whichever object holds them.
    private static final List<String> PERSON_FIELDS = new List<String>{
        'Preferred_Name__c',
        'Deceased__c',
        'Household_Role__c',
        'Exclude_From_Household_Name__c',
        'Exclude_From_Greetings__c'
    };

    // detection-only: an account holds a person rather than an organization when this
    // field both exists on the object and carries a value on the record.
    private static final String PERSON_MARKER_FIELD = 'LastName';

    /**
     * Set only by tests. When it is true every account record is treated as a person, so
     * that the person account paths can be exercised on an org shape that has no person
     * accounts. Production code never sets it.
     */
    @TestVisible
    private static Boolean personRecordOverride;

    /**
     * Set only by tests, keyed by the account's name. It supplies the person details that
     * an org without the person name fields cannot hold, so that a test can assert the
     * household name those details produce. Production code never sets it.
     */
    @TestVisible
    private static Map<String, HouseholdService.Person> personOverridesByName;

    /**
     * True when this account record holds a person. Nothing that exists only in some orgs
     * is named at compile time: the field is looked up by name and read from the values
     * the record actually carries.
     */
    public static Boolean isPersonRecord(SObject record) {
        if (record == null) {
            return false;
        }
        if (personRecordOverride != null) {
            return personRecordOverride;
        }
        if (!Schema.SObjectType.Account.fields.getMap().containsKey(PERSON_MARKER_FIELD)) {
            return false;
        }
        Object value = record.getPopulatedFieldsAsMap().get(PERSON_MARKER_FIELD);
        return value != null && String.isNotBlank(String.valueOf(value));
    }

    public static List<SObject> filterPeople(List<SObject> records) {
        List<SObject> result = new List<SObject>();
        if (records == null) {
            return result;
        }
        for (SObject record : records) {
            if (isPersonRecord(record)) {
                result.add(record);
            }
        }
        return result;
    }

    public static List<HouseholdService.Person> getPersons(Set<Id> personRecordIds) {
        List<HouseholdService.Person> result = new List<HouseholdService.Person>();
        if (
            personRecordIds == null ||
            personRecordIds.isEmpty() ||
            !HouseholdService.isPersonAccountOrg()
        ) {
            return result;
        }
        List<String> selected = new List<String>{ 'Id', 'Name', 'CreatedDate' };
        selected.addAll(availableFields());
        String query =
            'SELECT ' +
            String.join(selected, ', ') +
            ' FROM Account WHERE Id IN :personRecordIds LIMIT 10000';
        Map<String, Object> binds = new Map<String, Object>{ 'personRecordIds' => personRecordIds };
        for (SObject record : Database.queryWithBinds(query, binds, AccessLevel.USER_MODE)) {
            result.add(toPerson(record));
        }
        return result;
    }

    public static List<HouseholdService.Person> toPersons(List<SObject> records) {
        List<HouseholdService.Person> result = new List<HouseholdService.Person>();
        if (records == null) {
            return result;
        }
        for (SObject record : records) {
            result.add(toPerson(record));
        }
        return result;
    }

    public static HouseholdService.Person toPerson(SObject record) {
        HouseholdService.Person person = declared(record);
        if (person != null) {
            return person;
        }
        person = new HouseholdService.Person();
        person.id = record.Id;
        person.sourceObject = HouseholdService.SOURCE_ACCOUNT;
        // Only the values actually on the record are read, so a field this org does not
        // have, or did not select, reads as empty instead of failing.
        Map<String, Object> values = record.getPopulatedFieldsAsMap();
        person.firstName = text(values, 'FirstName');
        person.lastName = text(values, 'LastName');
        person.salutation = text(values, 'Salutation');
        person.preferredName = text(values, 'Preferred_Name__c');
        person.role = text(values, 'Household_Role__c');
        person.isDeceased = flag(values, 'Deceased__c');
        person.excludeFromName = flag(values, 'Exclude_From_Household_Name__c');
        person.excludeFromGreetings = flag(values, 'Exclude_From_Greetings__c');
        person.createdDate = values.get('CreatedDate') instanceof Datetime
            ? (Datetime) values.get('CreatedDate')
            : null;
        return person;
    }

    /**
     * The person details a test declared for this record, if any.
     */
    private static HouseholdService.Person declared(SObject record) {
        if (personOverridesByName == null || record == null) {
            return null;
        }
        Object name = record.getPopulatedFieldsAsMap().get('Name');
        if (name == null || !personOverridesByName.containsKey(String.valueOf(name))) {
            return null;
        }
        HouseholdService.Person person = personOverridesByName.get(String.valueOf(name)).copy();
        person.id = record.Id;
        person.sourceObject = HouseholdService.SOURCE_ACCOUNT;
        return person;
    }

    private static List<String> availableFields() {
        List<String> result = new List<String>();
        Map<String, Schema.SObjectField> describe = Schema.SObjectType.Account.fields.getMap();
        for (String fieldName : NAME_FIELDS) {
            if (describe.containsKey(fieldName)) {
                result.add(fieldName);
            }
        }
        for (String fieldName : PERSON_FIELDS) {
            if (describe.containsKey(fieldName)) {
                result.add(fieldName);
            }
        }
        return result;
    }

    private static String text(Map<String, Object> values, String fieldName) {
        Object value = values.get(fieldName);
        return value == null ? null : String.valueOf(value);
    }

    private static Boolean flag(Map<String, Object> values, String fieldName) {
        Object value = values.get(fieldName);
        return value instanceof Boolean ? (Boolean) value : false;
    }
}

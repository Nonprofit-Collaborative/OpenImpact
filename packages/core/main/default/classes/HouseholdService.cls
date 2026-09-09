/**
 * Household membership, in both membership modes, behind one entry point.
 *
 * Feature code never asks how membership is stored. In contact mode a person's household
 * is the account their contact record points at. In junction mode a Household Member row
 * joins a person to a household, and the person may be stored as a contact or, in orgs
 * that store people as accounts, as an account.
 *
 * Canonical model Section 5 (R-H1 to R-H12) and Section 6 (R-M1 to R-M5).
 */
@NamespaceAccessible
public with sharing class HouseholdService {
    @NamespaceAccessible
    public static final String MODE_JUNCTION = 'Junction';
    @NamespaceAccessible
    public static final String SOURCE_CONTACT = 'Contact';
    @NamespaceAccessible
    public static final String SOURCE_ACCOUNT = 'Account';
    @NamespaceAccessible
    public static final String RECORD_TYPE_HOUSEHOLD = 'Household';
    @NamespaceAccessible
    public static final String ROLE_HEAD = 'Head';

    /**
     * Set only by tests, so that the person account branches are exercised deterministically
     * on org shapes that do not have them. Production code always reads the detector.
     */
    @TestVisible
    private static Boolean personAccountOverride;

    private static Boolean creatingPersonHouseholds = false;

    /**
     * Answers already worked out in this transaction, so that a caller asking about the
     * same people twice does not query twice. Cleared whenever membership changes here.
     */
    private static final Map<Id, Id> HOUSEHOLD_ID_BY_PERSON = new Map<Id, Id>();
    private static Boolean upkeepRunning = false;

    /**
     * One member of a household, whichever object the person is stored on.
     */
    @NamespaceAccessible
    public class Person implements Comparable {
        @NamespaceAccessible
        public Id id;
        @NamespaceAccessible
        public String firstName;
        @NamespaceAccessible
        public String lastName;
        @NamespaceAccessible
        public String preferredName;
        @NamespaceAccessible
        public String salutation;
        @NamespaceAccessible
        public String role;
        @NamespaceAccessible
        public String sourceObject;
        @NamespaceAccessible
        public Boolean isDeceased = false;
        @NamespaceAccessible
        public Boolean isPrimary = false;
        @NamespaceAccessible
        public Boolean excludeFromName = false;
        @NamespaceAccessible
        public Boolean excludeFromGreetings = false;
        @NamespaceAccessible
        public Datetime createdDate;

        @NamespaceAccessible
        public Person() {
            this.sourceObject = SOURCE_CONTACT;
        }

        @NamespaceAccessible
        public Person(Contact source) {
            this.id = source.Id;
            this.firstName = source.FirstName;
            this.lastName = source.LastName;
            this.preferredName = source.Preferred_Name__c;
            this.salutation = source.Salutation;
            this.role = source.Household_Role__c;
            this.isDeceased = source.Deceased__c == true;
            this.excludeFromName = source.Exclude_From_Household_Name__c == true;
            this.excludeFromGreetings = source.Exclude_From_Greetings__c == true;
            this.createdDate = source.CreatedDate;
            this.sourceObject = SOURCE_CONTACT;
        }

        /**
         * A person built from whatever values the record actually carries. Used on the
         * display path, where a field the running user cannot read has been stripped out
         * and naming it would throw, so every value is read from the record's own
         * populated values and a missing one simply stays empty.
         */
        @NamespaceAccessible
        public Person(SObject record, String source) {
            Map<String, Object> values = record.getPopulatedFieldsAsMap();
            this.id = record.Id;
            this.sourceObject = source;
            this.firstName = textValue(values, 'FirstName');
            this.lastName = textValue(values, 'LastName');
            this.preferredName = textValue(values, 'Preferred_Name__c');
            this.salutation = textValue(values, 'Salutation');
            this.role = textValue(values, 'Household_Role__c');
            this.isDeceased = flagValue(values, 'Deceased__c');
            this.excludeFromName = flagValue(values, 'Exclude_From_Household_Name__c');
            this.excludeFromGreetings = flagValue(values, 'Exclude_From_Greetings__c');
            this.createdDate = values.get('CreatedDate') instanceof Datetime
                ? (Datetime) values.get('CreatedDate')
                : null;
        }

        @NamespaceAccessible
        public Person copy() {
            Person result = new Person();
            result.id = this.id;
            result.firstName = this.firstName;
            result.lastName = this.lastName;
            result.preferredName = this.preferredName;
            result.salutation = this.salutation;
            result.role = this.role;
            result.sourceObject = this.sourceObject;
            result.isDeceased = this.isDeceased;
            result.isPrimary = this.isPrimary;
            result.excludeFromName = this.excludeFromName;
            result.excludeFromGreetings = this.excludeFromGreetings;
            result.createdDate = this.createdDate;
            return result;
        }

        /**
         * Head first, then spouse or partner, then child, then other, then anyone with no
         * role. Within a role the primary member leads, then the earliest created member,
         * then first name, so that a household's name never changes without a reason.
         */
        @NamespaceAccessible
        public Integer compareTo(Object other) {
            Person that = (Person) other;
            Integer result = rank(this.role) - rank(that.role);
            if (result != 0) {
                return result;
            }
            result = flag(that.isPrimary) - flag(this.isPrimary);
            if (result != 0) {
                return result;
            }
            if (
                this.createdDate != null &&
                that.createdDate != null &&
                this.createdDate != that.createdDate
            ) {
                return this.createdDate < that.createdDate ? -1 : 1;
            }
            result = compareText(this.firstName, that.firstName);
            if (result != 0) {
                return result;
            }
            String leftId = this.id == null ? '' : String.valueOf(this.id);
            String rightId = that.id == null ? '' : String.valueOf(that.id);
            return compareText(leftId, rightId);
        }

        private Integer rank(String value) {
            if (value == ROLE_HEAD) {
                return 0;
            }
            if (value == 'Spouse or Partner') {
                return 1;
            }
            if (value == 'Child') {
                return 2;
            }
            if (value == 'Other') {
                return 3;
            }
            return 4;
        }

        private Integer flag(Boolean value) {
            return value == true ? 1 : 0;
        }

        private Integer compareText(String left, String right) {
            String a = left == null ? '' : left;
            String b = right == null ? '' : right;
            return a.compareTo(b);
        }
    }

    /**
     * True when this org stores people as accounts. The detection itself lives in
     * OrgShapeDetector so that only one class knows how the org is shaped.
     */
    @NamespaceAccessible
    public static Boolean isPersonAccountOrg() {
        if (personAccountOverride != null) {
            return personAccountOverride;
        }
        OrgShapeDetector.OrgShape shape = OrgShapeDetector.detect();
        return shape != null && shape.hasPersonAccounts == true;
    }

    @NamespaceAccessible
    public static Boolean isJunctionMode() {
        Nonprofit_Settings__c settings = SettingsService.getSettings();
        return settings != null &&
            MODE_JUNCTION.equalsIgnoreCase(settings.Household_Membership_Mode__c);
    }

    @NamespaceAccessible
    public static Id householdRecordTypeId() {
        Schema.RecordTypeInfo info = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get(RECORD_TYPE_HOUSEHOLD);
        return info == null ? null : info.getRecordTypeId();
    }

    @NamespaceAccessible
    public static List<Person> toPersons(List<Contact> contacts) {
        List<Person> result = new List<Person>();
        if (contacts == null) {
            return result;
        }
        for (Contact record : contacts) {
            result.add(new Person(record));
        }
        return result;
    }

    /**
     * The current members of each household, keyed by household id. Every requested id is
     * present in the map, with an empty list where the household has no members.
     */
    @NamespaceAccessible
    public static Map<Id, List<Person>> getMembers(Set<Id> householdIds) {
        return getMembers(householdIds, false);
    }

    /**
     * The same members, read with the running user's own access, for a screen. Object
     * access is checked and any field the user cannot read is left empty rather than
     * shown (ADR-0021).
     */
    @NamespaceAccessible
    public static Map<Id, List<Person>> getMembersAsUser(Set<Id> householdIds) {
        return getMembers(householdIds, true);
    }

    private static Map<Id, List<Person>> getMembers(Set<Id> householdIds, Boolean asUser) {
        Map<Id, List<Person>> result = new Map<Id, List<Person>>();
        if (householdIds == null || householdIds.isEmpty()) {
            return result;
        }
        for (Id householdId : householdIds) {
            result.put(householdId, new List<Person>());
        }
        if (isJunctionMode()) {
            addJunctionMembers(householdIds, result, asUser);
        } else if (asUser) {
            for (
                Contact record : HouseholdSelector.getContactsByHouseholdIdsForDisplay(householdIds)
            ) {
                Id householdId = idValue(record.getPopulatedFieldsAsMap(), 'AccountId');
                List<Person> bucket = householdId == null ? null : result.get(householdId);
                if (bucket != null) {
                    bucket.add(new Person(record, SOURCE_CONTACT));
                }
            }
        } else {
            for (Contact record : HouseholdSelector.getContactsByHouseholdIds(householdIds)) {
                List<Person> bucket = result.get(record.AccountId);
                if (bucket != null) {
                    bucket.add(new Person(record));
                }
            }
        }
        return result;
    }

    private static void addJunctionMembers(
        Set<Id> householdIds,
        Map<Id, List<Person>> result,
        Boolean asUser
    ) {
        List<Household_Member__c> memberships = asUser
            ? HouseholdSelector.getMembershipsForDisplay(householdIds)
            : HouseholdSelector.getMemberships(householdIds);
        Set<Id> contactIds = new Set<Id>();
        Set<Id> personRecordIds = new Set<Id>();
        for (Household_Member__c membership : memberships) {
            // Read from the values the row actually carries: on the display path a field
            // the user cannot read has been stripped, and naming it would throw.
            Map<String, Object> values = membership.getPopulatedFieldsAsMap();
            Id contactId = idValue(values, 'Contact__c');
            Id personRecordId = idValue(values, 'Account__c');
            if (contactId != null) {
                contactIds.add(contactId);
            } else if (personRecordId != null) {
                personRecordIds.add(personRecordId);
            }
        }
        Map<Id, Person> peopleById = new Map<Id, Person>();
        if (asUser) {
            for (Contact record : HouseholdSelector.getContactsByIdsForDisplay(contactIds)) {
                peopleById.put(record.Id, new Person(record, SOURCE_CONTACT));
            }
        } else {
            for (Contact record : HouseholdSelector.getContactsByIds(contactIds)) {
                peopleById.put(record.Id, new Person(record));
            }
        }
        if (!personRecordIds.isEmpty() && isPersonAccountOrg()) {
            for (Person person : PersonRecordSelector.getPersons(personRecordIds)) {
                peopleById.put(person.id, person);
            }
        }
        for (Household_Member__c membership : memberships) {
            Map<String, Object> values = membership.getPopulatedFieldsAsMap();
            Id contactId = idValue(values, 'Contact__c');
            Id personId = contactId != null ? contactId : idValue(values, 'Account__c');
            Id householdId = idValue(values, 'Household__c');
            Person source = peopleById.get(personId);
            List<Person> bucket = householdId == null ? null : result.get(householdId);
            if (source == null || bucket == null) {
                continue;
            }
            Person member = source.copy();
            String role = textValue(values, 'Role__c');
            if (String.isNotBlank(role)) {
                member.role = role;
            }
            member.isPrimary = flagValue(values, 'Is_Primary__c');
            bucket.add(member);
        }
    }

    /**
     * The household each of these people belongs to, for callers in other packages that
     * hold a person id and need the household to credit or to roll up to (ADR-0017).
     *
     * The set may mix people stored as contacts and people stored as accounts. Every id
     * asked about is in the answer: a person with no household, or one whose account is
     * not a household, is answered with null, so that "asked and there is none" is never
     * confused with "not asked".
     */
    @NamespaceAccessible
    public static Map<Id, Id> getHouseholdIdsFor(Set<Id> personIds) {
        Map<Id, Id> result = new Map<Id, Id>();
        if (personIds == null || personIds.isEmpty()) {
            return result;
        }
        Set<Id> unresolved = new Set<Id>();
        for (Id personId : personIds) {
            if (personId == null) {
                continue;
            }
            if (HOUSEHOLD_ID_BY_PERSON.containsKey(personId)) {
                result.put(personId, HOUSEHOLD_ID_BY_PERSON.get(personId));
            } else {
                unresolved.add(personId);
                result.put(personId, null);
            }
        }
        if (unresolved.isEmpty()) {
            return result;
        }
        if (isJunctionMode()) {
            resolveThroughJunction(unresolved, result);
        } else {
            resolveThroughContacts(unresolved, result);
        }
        for (Id personId : unresolved) {
            HOUSEHOLD_ID_BY_PERSON.put(personId, result.get(personId));
        }
        return result;
    }

    /**
     * Every household these people currently belong to, all of them rather than only the
     * one they are primary in.
     *
     * `getHouseholdIdsFor` answers "which household is this person's", which is the right
     * question when crediting a gift. This answers "which households does a change to this
     * person show up in", which is the right question when settling up after that person
     * has been renamed, deleted or restored: somebody in two households is named in two
     * household names, and both have to be rewritten.
     *
     * Junction mode only. In contact mode a person's household is the account their
     * contact record points at, and the contact trigger reads it from the record itself.
     */
    @NamespaceAccessible
    public static Set<Id> householdIdsForPeople(Set<Id> personIds) {
        Set<Id> result = new Set<Id>();
        if (personIds == null || personIds.isEmpty() || !isJunctionMode()) {
            return result;
        }
        for (
            Household_Member__c membership : HouseholdSelector.getMembershipsForPeople(personIds)
        ) {
            Id personId = membership.Contact__c != null
                ? membership.Contact__c
                : membership.Account__c;
            if (
                personId != null &&
                personIds.contains(personId) &&
                membership.Household__c != null
            ) {
                result.add(membership.Household__c);
            }
        }
        return result;
    }

    /**
     * The people who currently belong to each household given, by household id. The
     * counterpart of getHouseholdIdsFor, for callers rolling values up to a household.
     */
    @NamespaceAccessible
    public static Map<Id, Set<Id>> getMemberPersonIds(Set<Id> householdIds) {
        Map<Id, Set<Id>> result = new Map<Id, Set<Id>>();
        if (householdIds == null || householdIds.isEmpty()) {
            return result;
        }
        Map<Id, List<Person>> membersByHousehold = getMembers(householdIds);
        for (Id householdId : householdIds) {
            Set<Id> personIds = new Set<Id>();
            List<Person> members = membersByHousehold.get(householdId);
            if (members != null) {
                for (Person person : members) {
                    if (person.id != null) {
                        personIds.add(person.id);
                    }
                }
            }
            result.put(householdId, personIds);
        }
        return result;
    }

    /**
     * Takes the membership rows that join these people to their households out of the way,
     * for the one caller that needs it: the person records themselves are being deleted.
     *
     * Called from a `before delete` context, while the rows still say whose membership
     * they are. Two things follow from that, and neither works from `after delete`. The
     * households the deletion affects can still be read off the rows, and they are what
     * this returns. And the rows go into the recycle bin still naming the person, so that
     * restoring the person can put the membership back (`restoreMembershipsFor`).
     *
     * Ended memberships go too. A membership that has ended is history of a person, and
     * once that person is gone it is history of nobody: left behind, the platform empties
     * its person lookup and the row says nothing at all (R-M4).
     */
    @NamespaceAccessible
    public static Set<Id> removeMembershipsFor(Set<Id> personIds) {
        Set<Id> affected = new Set<Id>();
        if (personIds == null || personIds.isEmpty() || !isJunctionMode()) {
            return affected;
        }
        List<Household_Member__c> removing = new List<Household_Member__c>();
        for (
            Household_Member__c membership : HouseholdSelector.getAllMembershipsForPeople(personIds)
        ) {
            Id personId = membership.Contact__c != null
                ? membership.Contact__c
                : membership.Account__c;
            if (personId == null || !personIds.contains(personId)) {
                continue;
            }
            if (membership.Household__c != null) {
                affected.add(membership.Household__c);
            }
            removing.add(new Household_Member__c(Id = membership.Id));
        }
        HouseholdWriter.deleteMemberships(removing);
        HOUSEHOLD_ID_BY_PERSON.clear();
        return affected;
    }

    /**
     * Puts back the membership rows that were removed when these people were deleted, and
     * answers with the households that has changed.
     *
     * The platform cannot do this for us. A lookup that was emptied because the record it
     * pointed at was deleted is not restored when that record comes back, so a membership
     * row left to the platform would come out of the deletion naming nobody and stay that
     * way. Removing the row first, while it still names the person, is what makes the
     * restore possible at all.
     */
    @NamespaceAccessible
    public static Set<Id> restoreMembershipsFor(Set<Id> personIds) {
        Set<Id> affected = new Set<Id>();
        if (personIds == null || personIds.isEmpty() || !isJunctionMode()) {
            return affected;
        }
        List<Household_Member__c> restoring = new List<Household_Member__c>();
        for (
            Household_Member__c membership : HouseholdSelector.getDeletedMembershipsForPeople(
                personIds
            )
        ) {
            Id personId = membership.Contact__c != null
                ? membership.Contact__c
                : membership.Account__c;
            if (personId == null || !personIds.contains(personId)) {
                continue;
            }
            if (membership.Household__c != null) {
                affected.add(membership.Household__c);
            }
            restoring.add(new Household_Member__c(Id = membership.Id));
        }
        HouseholdWriter.undeleteMemberships(restoring);
        HOUSEHOLD_ID_BY_PERSON.clear();
        return affected;
    }

    /**
     * Everything a household needs once its membership has changed: the member count, the
     * name and the two greetings, and the tidying away of a household that has been left
     * with nobody in it.
     *
     * This is the one place that upkeep is spelled out. The trigger handlers call it, and
     * so may another package that has changed membership itself (ADR-0017). The guard stops
     * the saves it makes from coming back round through another trigger and starting again.
     */
    @NamespaceAccessible
    public static void afterMembershipChange(Set<Id> householdIds) {
        afterMembershipChange(householdIds, true);
    }

    /**
     * The same, saying whether a household left with nobody in it may be tidied away. It
     * may not on a path where people are still being added to a household that has only
     * just been created.
     */
    @NamespaceAccessible
    public static void afterMembershipChange(Set<Id> householdIds, Boolean mayTidyAway) {
        if (upkeepRunning || householdIds == null || householdIds.isEmpty()) {
            return;
        }
        upkeepRunning = true;
        try {
            // Who belongs to what has just changed, so any answer already given is stale.
            HOUSEHOLD_ID_BY_PERSON.clear();
            clearDepartedPrimaryContacts(householdIds);
            recalculateMemberCounts(householdIds);
            HouseholdNamingService.applyNaming(householdIds);
            if (mayTidyAway == true) {
                deleteEmptyHouseholds(householdIds);
            }
        } finally {
            upkeepRunning = false;
        }
    }

    private static void resolveThroughContacts(Set<Id> personIds, Map<Id, Id> result) {
        Set<Id> contactIds = idsOfType(personIds, Contact.SObjectType);
        if (contactIds.isEmpty()) {
            return;
        }
        Id recordTypeId = householdRecordTypeId();
        for (Contact record : HouseholdSelector.getContactsWithHouseholds(contactIds)) {
            Boolean isHousehold =
                record.AccountId != null &&
                recordTypeId != null &&
                record.Account.RecordTypeId == recordTypeId;
            result.put(record.Id, isHousehold ? record.AccountId : null);
        }
    }

    /**
     * A person in more than one household is answered with the household they are marked
     * primary in. Where they are in exactly one, that one is the answer.
     */
    private static void resolveThroughJunction(Set<Id> personIds, Map<Id, Id> result) {
        Map<Id, List<Household_Member__c>> byPerson = new Map<Id, List<Household_Member__c>>();
        for (
            Household_Member__c membership : HouseholdSelector.getMembershipsForPeople(personIds)
        ) {
            Id personId = membership.Contact__c != null
                ? membership.Contact__c
                : membership.Account__c;
            if (personId == null || !personIds.contains(personId)) {
                continue;
            }
            if (!byPerson.containsKey(personId)) {
                byPerson.put(personId, new List<Household_Member__c>());
            }
            byPerson.get(personId).add(membership);
        }
        for (Id personId : byPerson.keySet()) {
            List<Household_Member__c> memberships = byPerson.get(personId);
            if (memberships.size() == 1) {
                result.put(personId, memberships[0].Household__c);
                continue;
            }
            for (Household_Member__c membership : memberships) {
                if (membership.Is_Primary__c == true) {
                    result.put(personId, membership.Household__c);
                    break;
                }
            }
        }
    }

    /**
     * Values read from a record's own populated values, so that a field the running user
     * cannot read, which has been stripped out before the record got here, reads as empty
     * instead of throwing.
     */
    private static String textValue(Map<String, Object> values, String fieldName) {
        Object value = values.get(fieldName);
        return value == null ? null : String.valueOf(value);
    }

    private static Boolean flagValue(Map<String, Object> values, String fieldName) {
        Object value = values.get(fieldName);
        return value instanceof Boolean ? (Boolean) value : false;
    }

    private static Id idValue(Map<String, Object> values, String fieldName) {
        Object value = values.get(fieldName);
        return value instanceof Id ? (Id) value : null;
    }

    private static Set<Id> idsOfType(Set<Id> ids, Schema.SObjectType wanted) {
        Set<Id> result = new Set<Id>();
        for (Id value : ids) {
            if (value.getSObjectType() == wanted) {
                result.add(value);
            }
        }
        return result;
    }

    /**
     * Gives every contact that arrives without a household one of its own, named from the
     * org's pattern. Runs before insert, so the new household id is simply assigned to the
     * contact and no second pass over contacts is needed. R-H1.
     */
    @NamespaceAccessible
    public static void ensureHouseholds(List<Contact> contacts) {
        if (contacts == null || contacts.isEmpty()) {
            return;
        }
        Nonprofit_Settings__c settings = SettingsService.getSettings();
        if (settings == null || settings.Auto_Create_Households__c != true || isJunctionMode()) {
            return;
        }
        Id recordTypeId = householdRecordTypeId();
        if (recordTypeId == null) {
            ErrorLogger.log(
                new HouseholdException(Label.Core_Households_ErrorRecordTypeMissing),
                Label.Core_Households_ErrorContextMembership
            );
            return;
        }
        List<Contact> waiting = new List<Contact>();
        List<Account> households = new List<Account>();
        for (Contact record : contacts) {
            if (record.AccountId != null) {
                continue;
            }
            waiting.add(record);
            households.add(
                newHousehold(new List<Person>{ new Person(record) }, recordTypeId, settings)
            );
        }
        if (households.isEmpty()) {
            return;
        }
        // The household is the package's own bookkeeping, so it is saved by HouseholdWriter,
        // which explains why that one write does not run with the saving user's access.
        List<Id> created = HouseholdWriter.createHouseholds(households);
        HOUSEHOLD_ID_BY_PERSON.clear();
        for (Integer i = 0; i < created.size(); i++) {
            if (created[i] != null) {
                waiting[i].AccountId = created[i];
            }
        }
    }

    /**
     * Creates a household and a membership row for each new person that the org stores as
     * an account. R-H2. Called only when the org has person records, membership is in
     * junction mode, and the setting is on.
     */
    @NamespaceAccessible
    public static void createHouseholdsForPersonAccounts(List<SObject> personRecords) {
        if (personRecords == null || personRecords.isEmpty() || creatingPersonHouseholds) {
            return;
        }
        Id recordTypeId = householdRecordTypeId();
        if (recordTypeId == null) {
            ErrorLogger.log(
                new HouseholdException(Label.Core_Households_ErrorRecordTypeMissing),
                Label.Core_Households_ErrorContextMembership
            );
            return;
        }
        Nonprofit_Settings__c settings = SettingsService.getSettings();
        List<Person> people = PersonRecordSelector.toPersons(personRecords);
        if (people.isEmpty()) {
            return;
        }
        creatingPersonHouseholds = true;
        try {
            List<Account> households = new List<Account>();
            for (Person person : people) {
                households.add(newHousehold(new List<Person>{ person }, recordTypeId, settings));
            }
            List<Id> created = HouseholdWriter.createHouseholds(households);
            List<Household_Member__c> memberships = new List<Household_Member__c>();
            for (Integer i = 0; i < created.size(); i++) {
                if (created[i] == null) {
                    continue;
                }
                memberships.add(
                    new Household_Member__c(
                        Household__c = created[i],
                        Account__c = people[i].id,
                        Role__c = ROLE_HEAD,
                        Is_Primary__c = true,
                        Start_Date__c = Date.today()
                    )
                );
            }
            if (!memberships.isEmpty()) {
                HouseholdWriter.createMemberships(memberships);
                HOUSEHOLD_ID_BY_PERSON.clear();
            }
        } finally {
            creatingPersonHouseholds = false;
        }
    }

    private static Account newHousehold(
        List<Person> members,
        Id recordTypeId,
        Nonprofit_Settings__c settings
    ) {
        String namePattern = settings == null ? null : settings.Household_Name_Pattern__c;
        String formalPattern = settings == null ? null : settings.Formal_Greeting_Pattern__c;
        String informalPattern = settings == null ? null : settings.Informal_Greeting_Pattern__c;
        String name = HouseholdNamingService.computeName(members, namePattern);
        return new Account(
            Name = String.isBlank(name) ? Label.Core_Households_NamePlaceholder : name,
            RecordTypeId = recordTypeId,
            Custom_Name__c = false,
            Member_Count__c = members.size(),
            Household_Formal_Greeting__c = HouseholdNamingService.computeFormalGreeting(
                members,
                formalPattern
            ),
            Household_Informal_Greeting__c = HouseholdNamingService.computeInformalGreeting(
                members,
                informalPattern
            )
        );
    }

    /**
     * Moves one person to another household and leaves both households correct: counts,
     * names, greetings, and the empty household tidied away when the org asks for that.
     * R-H12.
     */
    @NamespaceAccessible
    public static void moveContact(Id contactId, Id targetHouseholdId) {
        if (contactId == null) {
            throw new HouseholdException(Label.Core_Households_ErrorMoveMissingInput);
        }
        // One upkeep path, the same one the membership trigger uses, so the work is not
        // done twice when the trigger has already run for this move.
        afterMembershipChange(moveMembers(new Set<Id>{ contactId }, targetHouseholdId));
    }

    /**
     * Moves several people to one household in a single pass, whichever object holds each
     * of them and whichever membership mode the org uses, and answers with every household
     * the move touched: the target, and each household somebody left.
     *
     * Nothing is recounted, renamed, or tidied away here. The caller decides when to settle
     * up by calling `afterMembershipChange` with the answer, so that a merge or a split of
     * fifty people settles once rather than fifty times. `moveContact` is that caller for a
     * single move. R-H12.
     */
    @NamespaceAccessible
    public static Set<Id> moveMembers(Set<Id> personIds, Id targetHouseholdId) {
        if (personIds == null || personIds.isEmpty() || targetHouseholdId == null) {
            throw new HouseholdException(Label.Core_Households_ErrorMoveMissingInput);
        }
        List<Account> targets = HouseholdSelector.getHouseholdsByIds(
            new Set<Id>{ targetHouseholdId }
        );
        if (targets.isEmpty()) {
            throw new HouseholdException(Label.Core_Households_ErrorMoveNotFound);
        }
        if (targets[0].RecordTypeId != householdRecordTypeId()) {
            throw new HouseholdException(Label.Core_Households_ErrorNotAHousehold);
        }
        Set<Id> contactPeople = idsOfType(personIds, Contact.SObjectType);
        Set<Id> accountPeople = idsOfType(personIds, Account.SObjectType);
        if (contactPeople.size() + accountPeople.size() != personIds.size()) {
            // An id of any other object is not a person this service can move.
            throw new HouseholdException(Label.Core_Households_ErrorMoveNotFound);
        }
        if (!accountPeople.isEmpty() && !isJunctionMode()) {
            // A person stored as an account has no account reference of their own to move,
            // so this org has to be in the flexible membership mode to move them at all.
            throw new HouseholdException(Label.Core_Households_ErrorMoveNeedsJunction);
        }
        // Everybody named is read through the object that holds them, and everybody named
        // has to exist. A merge or a split that names somebody who has since been deleted
        // is refused rather than quietly moving the rest.
        Map<Id, Contact> contacts = new Map<Id, Contact>(
            HouseholdSelector.getContactsByIds(contactPeople)
        );
        if (contacts.size() != contactPeople.size()) {
            throw new HouseholdException(Label.Core_Households_ErrorMoveNotFound);
        }
        Set<Id> foundAsAccount = new Set<Id>();
        for (Person person : PersonRecordSelector.getPersons(accountPeople)) {
            foundAsAccount.add(person.id);
        }
        if (foundAsAccount.size() != accountPeople.size()) {
            throw new HouseholdException(Label.Core_Households_ErrorMoveNotFound);
        }
        Set<Id> affected = new Set<Id>{ targetHouseholdId };
        if (isJunctionMode()) {
            moveJunctionMembers(personIds, targetHouseholdId, affected);
        } else {
            moveContactMembers(contacts.values(), targetHouseholdId, affected);
        }
        HOUSEHOLD_ID_BY_PERSON.clear();
        return affected;
    }

    /**
     * In contact mode the move is the person's own account reference, so everybody moves in
     * one update. Somebody already in the target is left alone.
     */
    private static void moveContactMembers(
        List<Contact> people,
        Id targetHouseholdId,
        Set<Id> affected
    ) {
        List<Contact> updates = new List<Contact>();
        for (Contact person : people) {
            if (person.AccountId == targetHouseholdId) {
                continue;
            }
            if (person.AccountId != null) {
                affected.add(person.AccountId);
            }
            updates.add(new Contact(Id = person.Id, AccountId = targetHouseholdId));
        }
        if (!updates.isEmpty()) {
            Database.update(updates, AccessLevel.USER_MODE);
        }
    }

    /**
     * In junction mode a person who is already a current member of the target keeps that
     * one membership: their other memberships are end dated and no second row is written,
     * so that a move never leaves a person in the same household twice.
     *
     * The role a person had comes with them, so that a move does not quietly turn a Head
     * into nobody in particular. The primary flag comes with them only where the target has
     * room for it: at most one current member of a household is primary (R-M3), so if the
     * target already has a primary, or two people arrive holding the flag, the arrivals
     * join as ordinary members and the household keeps the one primary it is allowed.
     */
    private static void moveJunctionMembers(
        Set<Id> personIds,
        Id targetHouseholdId,
        Set<Id> affected
    ) {
        Boolean primaryIsFree = true;
        for (
            Household_Member__c membership : HouseholdSelector.getMemberships(
                new Set<Id>{ targetHouseholdId }
            )
        ) {
            if (membership.Is_Primary__c == true) {
                primaryIsFree = false;
            }
        }
        Set<Id> alreadyInTarget = new Set<Id>();
        Map<Id, String> roleByPerson = new Map<Id, String>();
        Set<Id> wasPrimary = new Set<Id>();
        List<Household_Member__c> ended = new List<Household_Member__c>();
        for (
            Household_Member__c membership : HouseholdSelector.getMembershipsForPeople(personIds)
        ) {
            Id personId = membership.Contact__c != null
                ? membership.Contact__c
                : membership.Account__c;
            if (personId == null || !personIds.contains(personId)) {
                continue;
            }
            if (membership.Household__c == targetHouseholdId) {
                alreadyInTarget.add(personId);
                continue;
            }
            affected.add(membership.Household__c);
            if (
                String.isBlank(roleByPerson.get(personId)) && String.isNotBlank(membership.Role__c)
            ) {
                roleByPerson.put(personId, membership.Role__c);
            }
            if (membership.Is_Primary__c == true) {
                wasPrimary.add(personId);
            }
            // Ended today, and the current-membership filter counts only a membership that
            // ends after today, so the person leaves the old household straight away.
            ended.add(new Household_Member__c(Id = membership.Id, End_Date__c = Date.today()));
        }
        if (!ended.isEmpty()) {
            Database.update(ended, AccessLevel.USER_MODE);
        }
        Boolean primaryStillFree = primaryIsFree && wasPrimary.size() == 1;
        List<Household_Member__c> joined = new List<Household_Member__c>();
        for (Id personId : personIds) {
            if (alreadyInTarget.contains(personId)) {
                continue;
            }
            Boolean takesPrimary = primaryStillFree && wasPrimary.contains(personId);
            if (takesPrimary) {
                primaryStillFree = false;
            }
            joined.add(
                newMembership(personId, targetHouseholdId, roleByPerson.get(personId), takesPrimary)
            );
        }
        if (!joined.isEmpty()) {
            Database.insert(joined, AccessLevel.USER_MODE);
        }
    }

    /**
     * Joins people to households, whichever way the org stores membership, and answers with
     * every household the join touched.
     *
     * The counterpart of `moveMembers` for a caller that is building people and households
     * together (a sample data set, an import) rather than moving somebody who already
     * belongs somewhere. Each entry names one household and the people joining it, so a
     * caller with two hundred households joins them in one pass.
     *
     * What "joining" means is the mode's business, not the caller's (R-M5). In contact mode
     * a person's household is the account their contact points at, so joining reparents
     * them and the household they left is in the answer. In junction mode a membership row
     * is added and the person keeps any other household they belong to, which is what that
     * mode is for. Somebody who is already a current member of the household they are being
     * joined to is left alone, so calling twice does not make two memberships.
     *
     * A person is joined as an ordinary member with no role and no primary flag on the
     * membership row: the role the person carries on their own record is the one that
     * naming and greetings read, and a household's primary member (R-M3) is a decision
     * somebody makes rather than a side effect of a join.
     *
     * Nothing is recounted or renamed here. The write fires the trigger that settles the
     * households up, exactly as it does when a person is saved by hand; a caller that has
     * suppressed that automation settles by passing the answer to `afterMembershipChange`.
     */
    @NamespaceAccessible
    public static Set<Id> addMembers(Map<Id, Set<Id>> personIdsByHouseholdId) {
        Set<Id> affected = new Set<Id>();
        if (personIdsByHouseholdId == null || personIdsByHouseholdId.isEmpty()) {
            return affected;
        }
        Set<Id> householdIds = new Set<Id>(personIdsByHouseholdId.keySet());
        Set<Id> everybody = new Set<Id>();
        for (Id householdId : householdIds) {
            Set<Id> people = personIdsByHouseholdId.get(householdId);
            if (people != null) {
                everybody.addAll(people);
            }
        }
        if (everybody.isEmpty()) {
            return affected;
        }
        Id recordTypeId = householdRecordTypeId();
        Set<Id> found = new Set<Id>();
        for (Account household : HouseholdSelector.getHouseholdsByIds(householdIds)) {
            if (recordTypeId != null && household.RecordTypeId != recordTypeId) {
                throw new HouseholdException(Label.Core_Households_ErrorNotAHousehold);
            }
            found.add(household.Id);
        }
        if (found.size() != householdIds.size()) {
            throw new HouseholdException(Label.Core_Households_ErrorMoveNotFound);
        }
        Set<Id> contactPeople = idsOfType(everybody, Contact.SObjectType);
        Set<Id> accountPeople = idsOfType(everybody, Account.SObjectType);
        if (contactPeople.size() + accountPeople.size() != everybody.size()) {
            // An id of any other object is not a person this service can join.
            throw new HouseholdException(Label.Core_Households_ErrorMoveNotFound);
        }
        if (!accountPeople.isEmpty() && !isJunctionMode()) {
            // A person stored as an account has no account reference of their own, so only
            // the flexible membership mode can hold them.
            throw new HouseholdException(Label.Core_Households_ErrorMoveNeedsJunction);
        }
        affected.addAll(householdIds);
        if (isJunctionMode()) {
            joinThroughJunction(personIdsByHouseholdId, everybody);
        } else {
            joinThroughContacts(personIdsByHouseholdId, contactPeople, affected);
        }
        HOUSEHOLD_ID_BY_PERSON.clear();
        return affected;
    }

    /**
     * One membership row per person who is not already a current member of the household
     * they are joining. Read once for everybody, written once.
     */
    private static void joinThroughJunction(
        Map<Id, Set<Id>> personIdsByHouseholdId,
        Set<Id> everybody
    ) {
        Set<String> alreadyMembers = new Set<String>();
        for (
            Household_Member__c membership : HouseholdSelector.getMembershipsForPeople(everybody)
        ) {
            Id personId = membership.Contact__c != null
                ? membership.Contact__c
                : membership.Account__c;
            if (personId != null) {
                alreadyMembers.add(membership.Household__c + ':' + personId);
            }
        }
        List<Household_Member__c> joined = new List<Household_Member__c>();
        for (Id householdId : personIdsByHouseholdId.keySet()) {
            Set<Id> people = personIdsByHouseholdId.get(householdId);
            if (people == null) {
                continue;
            }
            for (Id personId : people) {
                if (alreadyMembers.contains(householdId + ':' + personId)) {
                    continue;
                }
                joined.add(newMembership(personId, householdId, null, false));
            }
        }
        if (!joined.isEmpty()) {
            Database.insert(joined, AccessLevel.USER_MODE);
        }
    }

    /**
     * In contact mode joining is the person's own account reference, so everybody moves in
     * one update and every household somebody left is added to the answer.
     */
    private static void joinThroughContacts(
        Map<Id, Set<Id>> personIdsByHouseholdId,
        Set<Id> contactPeople,
        Set<Id> affected
    ) {
        Map<Id, Contact> people = new Map<Id, Contact>(
            HouseholdSelector.getContactsByIds(contactPeople)
        );
        if (people.size() != contactPeople.size()) {
            throw new HouseholdException(Label.Core_Households_ErrorMoveNotFound);
        }
        List<Contact> updates = new List<Contact>();
        for (Id householdId : personIdsByHouseholdId.keySet()) {
            Set<Id> joining = personIdsByHouseholdId.get(householdId);
            if (joining == null) {
                continue;
            }
            for (Id personId : joining) {
                Contact person = people.get(personId);
                if (person == null || person.AccountId == householdId) {
                    continue;
                }
                if (person.AccountId != null) {
                    affected.add(person.AccountId);
                }
                updates.add(new Contact(Id = personId, AccountId = householdId));
            }
        }
        if (!updates.isEmpty()) {
            Database.update(updates, AccessLevel.USER_MODE);
        }
    }

    /**
     * A membership row that points at the person through whichever object holds them, so
     * that an org storing people as accounts is joined up the same way as any other.
     */
    private static Household_Member__c newMembership(
        Id personId,
        Id householdId,
        String role,
        Boolean isPrimary
    ) {
        Household_Member__c membership = new Household_Member__c(
            Household__c = householdId,
            Role__c = role,
            Is_Primary__c = isPrimary,
            Start_Date__c = Date.today()
        );
        if (personId.getSObjectType() == Contact.SObjectType) {
            membership.Contact__c = personId;
        } else {
            membership.Account__c = personId;
        }
        return membership;
    }

    /**
     * Creates one household named from the people who are about to join it, for a split
     * that has no household to move them into yet. The people are not attached here: the
     * caller moves them, so that one move path serves every caller.
     */
    @NamespaceAccessible
    public static Id createHouseholdFor(List<Person> members) {
        Id recordTypeId = householdRecordTypeId();
        if (recordTypeId == null) {
            throw new HouseholdException(Label.Core_Households_ErrorRecordTypeMissing);
        }
        List<Person> people = members == null ? new List<Person>() : members;
        Account household = newHousehold(people, recordTypeId, SettingsService.getSettings());
        household.Member_Count__c = 0;
        // The name, the greetings and the count on this record are the package's own
        // bookkeeping, so it is saved by HouseholdWriter for the reason ADR-0021 gives.
        List<Id> created = HouseholdWriter.createHouseholds(new List<Account>{ household });
        HOUSEHOLD_ID_BY_PERSON.clear();
        Id householdId = created.isEmpty() ? null : created[0];
        if (householdId == null) {
            // HouseholdWriter has already logged why. Nobody is moved into a household
            // that does not exist, so the split stops here rather than half happening.
            throw new HouseholdException(Label.Core_Households_ErrorCreateFailed);
        }
        return householdId;
    }

    /**
     * Clears Primary Contact on any household whose primary contact is no longer one of
     * its current members. R-H10.
     *
     * The reference is cleared and nothing is promoted in its place: the canonical model
     * says the next member by ordering is proposed, not silently assigned, so choosing a
     * new primary contact stays a decision somebody makes. A split that moves the primary
     * contact out therefore leaves the household with no primary contact rather than with
     * a reference to somebody who has left.
     *
     * Both membership modes are covered by asking the one question "is this person still a
     * current member", which getMembers answers whichever way the org stores membership. A
     * person held as an account cannot be a household's Primary Contact at all (the field
     * is a lookup to Contact), so in junction mode a household whose members are all held
     * as accounts simply has no primary contact to keep.
     */
    private static void clearDepartedPrimaryContacts(Set<Id> householdIds) {
        Id recordTypeId = householdRecordTypeId();
        List<Account> households = HouseholdSelector.getHouseholdsByIds(householdIds);
        Set<Id> withPrimary = new Set<Id>();
        for (Account household : households) {
            // Only a household. An organization shares the Primary Contact field (R-O3),
            // where it names the person the nonprofit deals with rather than a member, and
            // household upkeep never touches it.
            Boolean isHousehold = recordTypeId != null && household.RecordTypeId == recordTypeId;
            if (isHousehold && household.Primary_Contact__c != null) {
                withPrimary.add(household.Id);
            }
        }
        if (withPrimary.isEmpty()) {
            return;
        }
        // One read of the members of every household that has a primary contact, so a
        // split of fifty households still asks once.
        Map<Id, List<Person>> membersByHousehold = getMembers(withPrimary);
        List<Account> updates = new List<Account>();
        for (Account household : households) {
            if (!withPrimary.contains(household.Id)) {
                continue;
            }
            Boolean stillAMember = false;
            List<Person> members = membersByHousehold.get(household.Id);
            if (members != null) {
                for (Person member : members) {
                    if (member.id == household.Primary_Contact__c) {
                        stillAMember = true;
                        break;
                    }
                }
            }
            if (!stillAMember) {
                updates.add(new Account(Id = household.Id, Primary_Contact__c = null));
            }
        }
        if (!updates.isEmpty()) {
            // Package upkeep of a household, saved the way every other piece of household
            // upkeep is saved, for the reason ADR-0021 gives: an ordinary contact save
            // must not fail because the saving user cannot edit the household.
            HouseholdWriter.updateHouseholds(updates);
        }
    }

    /**
     * Recounts current members on each household given. R-H11.
     */
    @NamespaceAccessible
    public static void recalculateMemberCounts(Set<Id> householdIds) {
        if (householdIds == null || householdIds.isEmpty()) {
            return;
        }
        Id recordTypeId = householdRecordTypeId();
        Map<Id, List<Person>> membersByHousehold = getMembers(householdIds);
        List<Account> updates = new List<Account>();
        for (Account household : HouseholdSelector.getHouseholdsByIds(householdIds)) {
            // Only a household is counted. An organization a contact happens to belong to
            // never gets a member count stamped on it.
            if (recordTypeId != null && household.RecordTypeId != recordTypeId) {
                continue;
            }
            List<Person> members = membersByHousehold.get(household.Id);
            Decimal count = members == null ? 0 : members.size();
            if (household.Member_Count__c != count) {
                updates.add(new Account(Id = household.Id, Member_Count__c = count));
            }
        }
        if (!updates.isEmpty()) {
            HouseholdWriter.updateHouseholds(updates);
        }
    }

    /**
     * Deletes households that have been left with no members, when the org asks for that.
     * R-H12.
     */
    @NamespaceAccessible
    public static void deleteEmptyHouseholds(Set<Id> householdIds) {
        if (householdIds == null || householdIds.isEmpty()) {
            return;
        }
        Nonprofit_Settings__c settings = SettingsService.getSettings();
        if (settings == null || settings.Delete_Empty_Households__c != true) {
            return;
        }
        Id recordTypeId = householdRecordTypeId();
        Map<Id, List<Person>> membersByHousehold = getMembers(householdIds);
        List<Account> empties = new List<Account>();
        for (Account household : HouseholdSelector.getHouseholdsByIds(householdIds)) {
            List<Person> members = membersByHousehold.get(household.Id);
            Boolean isHousehold = recordTypeId != null && household.RecordTypeId == recordTypeId;
            if (isHousehold && (members == null || members.isEmpty())) {
                empties.add(new Account(Id = household.Id));
            }
        }
        if (!empties.isEmpty()) {
            HouseholdWriter.deleteHouseholds(empties);
        }
    }
}

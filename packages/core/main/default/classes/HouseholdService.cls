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
        if (contactId == null || targetHouseholdId == null) {
            throw new HouseholdException(Label.Core_Households_ErrorMoveMissingInput);
        }
        Boolean storedAsAccount = contactId.getSObjectType() == Account.SObjectType;
        List<Contact> people = storedAsAccount
            ? new List<Contact>()
            : HouseholdSelector.getContactsByIds(new Set<Id>{ contactId });
        List<Account> targets = HouseholdSelector.getHouseholdsByIds(
            new Set<Id>{ targetHouseholdId }
        );
        if (targets.isEmpty()) {
            throw new HouseholdException(Label.Core_Households_ErrorMoveNotFound);
        }
        if (targets[0].RecordTypeId != householdRecordTypeId()) {
            throw new HouseholdException(Label.Core_Households_ErrorNotAHousehold);
        }
        Boolean personMissing =
            storedAsAccount && PersonRecordSelector.getPersons(new Set<Id>{ contactId }).isEmpty();
        if (personMissing) {
            throw new HouseholdException(Label.Core_Households_ErrorMoveNotFound);
        }
        if (!storedAsAccount && people.isEmpty()) {
            throw new HouseholdException(Label.Core_Households_ErrorMoveNotFound);
        }
        Set<Id> affected = new Set<Id>{ targetHouseholdId };
        if (isJunctionMode()) {
            moveJunctionMember(contactId, targetHouseholdId, storedAsAccount, affected);
        } else if (storedAsAccount) {
            // A person stored as an account has no account reference of their own to move,
            // so this org has to be in the flexible membership mode to move them at all.
            throw new HouseholdException(Label.Core_Households_ErrorMoveNeedsJunction);
        } else {
            Contact person = people[0];
            if (person.AccountId != null) {
                affected.add(person.AccountId);
            }
            person.AccountId = targetHouseholdId;
            Database.update(new List<Contact>{ person }, AccessLevel.USER_MODE);
        }
        // One upkeep path, the same one the membership trigger uses, so the work is not
        // done twice when the trigger has already run for this move.
        afterMembershipChange(affected);
    }

    private static void moveJunctionMember(
        Id personId,
        Id targetHouseholdId,
        Boolean storedAsAccount,
        Set<Id> affected
    ) {
        List<Household_Member__c> current = HouseholdSelector.getMembershipsForPeople(
            new Set<Id>{ personId }
        );
        List<Household_Member__c> ended = new List<Household_Member__c>();
        String role;
        Boolean isPrimary = false;
        for (Household_Member__c membership : current) {
            if (membership.Household__c == targetHouseholdId) {
                continue;
            }
            affected.add(membership.Household__c);
            if (String.isBlank(role) && String.isNotBlank(membership.Role__c)) {
                role = membership.Role__c;
            }
            isPrimary = isPrimary || membership.Is_Primary__c == true;
            // Ended today, and the current-membership filter counts only a membership that
            // ends after today, so the person leaves the old household straight away.
            ended.add(new Household_Member__c(Id = membership.Id, End_Date__c = Date.today()));
        }
        if (!ended.isEmpty()) {
            Database.update(ended, AccessLevel.USER_MODE);
        }
        Household_Member__c joined = new Household_Member__c(
            Household__c = targetHouseholdId,
            Role__c = role,
            Is_Primary__c = isPrimary,
            Start_Date__c = Date.today()
        );
        if (storedAsAccount) {
            joined.Account__c = personId;
        } else {
            joined.Contact__c = personId;
        }
        Database.insert(new List<Household_Member__c>{ joined }, AccessLevel.USER_MODE);
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

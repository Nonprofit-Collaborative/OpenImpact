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
public with sharing class HouseholdService {
    public static final String MODE_JUNCTION = 'Junction';
    public static final String SOURCE_CONTACT = 'Contact';
    public static final String SOURCE_ACCOUNT = 'Account';
    public static final String RECORD_TYPE_HOUSEHOLD = 'Household';
    public static final String ROLE_HEAD = 'Head';

    /**
     * Set only by tests, so that the person account branches are exercised deterministically
     * on org shapes that do not have them. Production code always reads the detector.
     */
    @TestVisible
    private static Boolean personAccountOverride;

    private static Boolean creatingPersonHouseholds = false;

    /**
     * One member of a household, whichever object the person is stored on.
     */
    public class Person implements Comparable {
        public Id id;
        public String firstName;
        public String lastName;
        public String preferredName;
        public String salutation;
        public String role;
        public String sourceObject;
        public Boolean isDeceased = false;
        public Boolean isPrimary = false;
        public Boolean excludeFromName = false;
        public Boolean excludeFromGreetings = false;
        public Datetime createdDate;

        public Person() {
            this.sourceObject = SOURCE_CONTACT;
        }

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
    public static Boolean isPersonAccountOrg() {
        if (personAccountOverride != null) {
            return personAccountOverride;
        }
        OrgShapeDetector.OrgShape shape = OrgShapeDetector.detect();
        return shape != null && shape.hasPersonAccounts == true;
    }

    public static Boolean isJunctionMode() {
        Nonprofit_Settings__c settings = SettingsService.getSettings();
        return settings != null &&
            MODE_JUNCTION.equalsIgnoreCase(settings.Household_Membership_Mode__c);
    }

    public static Id householdRecordTypeId() {
        Schema.RecordTypeInfo info = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get(RECORD_TYPE_HOUSEHOLD);
        return info == null ? null : info.getRecordTypeId();
    }

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
    public static Map<Id, List<Person>> getMembers(Set<Id> householdIds) {
        Map<Id, List<Person>> result = new Map<Id, List<Person>>();
        if (householdIds == null || householdIds.isEmpty()) {
            return result;
        }
        for (Id householdId : householdIds) {
            result.put(householdId, new List<Person>());
        }
        if (isJunctionMode()) {
            addJunctionMembers(householdIds, result);
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

    private static void addJunctionMembers(Set<Id> householdIds, Map<Id, List<Person>> result) {
        List<Household_Member__c> memberships = HouseholdSelector.getMemberships(householdIds);
        Set<Id> contactIds = new Set<Id>();
        Set<Id> personRecordIds = new Set<Id>();
        for (Household_Member__c membership : memberships) {
            if (membership.Contact__c != null) {
                contactIds.add(membership.Contact__c);
            } else if (membership.Account__c != null) {
                personRecordIds.add(membership.Account__c);
            }
        }
        Map<Id, Person> peopleById = new Map<Id, Person>();
        for (Contact record : HouseholdSelector.getContactsByIds(contactIds)) {
            peopleById.put(record.Id, new Person(record));
        }
        if (!personRecordIds.isEmpty() && isPersonAccountOrg()) {
            for (Person person : PersonRecordSelector.getPersons(personRecordIds)) {
                peopleById.put(person.id, person);
            }
        }
        for (Household_Member__c membership : memberships) {
            Id personId = membership.Contact__c != null
                ? membership.Contact__c
                : membership.Account__c;
            Person source = peopleById.get(personId);
            List<Person> bucket = result.get(membership.Household__c);
            if (source == null || bucket == null) {
                continue;
            }
            Person member = source.copy();
            if (String.isNotBlank(membership.Role__c)) {
                member.role = membership.Role__c;
            }
            member.isPrimary = membership.Is_Primary__c == true;
            bucket.add(member);
        }
    }

    /**
     * Gives every contact that arrives without a household one of its own, named from the
     * org's pattern. Runs before insert, so the new household id is simply assigned to the
     * contact and no second pass over contacts is needed. R-H1.
     */
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
        // User mode: creating a contact is a user action, so the household is created with
        // the saving user's own access rather than with more.
        List<Database.SaveResult> results = Database.insert(households, AccessLevel.USER_MODE);
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                waiting[i].AccountId = results[i].getId();
            }
        }
    }

    /**
     * Creates a household and a membership row for each new person that the org stores as
     * an account. R-H2. Called only when the org has person records, membership is in
     * junction mode, and the setting is on.
     */
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
            List<Database.SaveResult> results = Database.insert(households, AccessLevel.USER_MODE);
            List<Household_Member__c> memberships = new List<Household_Member__c>();
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    continue;
                }
                memberships.add(
                    new Household_Member__c(
                        Household__c = results[i].getId(),
                        Account__c = people[i].id,
                        Role__c = ROLE_HEAD,
                        Is_Primary__c = true,
                        Start_Date__c = Date.today()
                    )
                );
            }
            if (!memberships.isEmpty()) {
                Database.insert(memberships, AccessLevel.USER_MODE);
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
    public static void moveContact(Id contactId, Id targetHouseholdId) {
        if (contactId == null || targetHouseholdId == null) {
            throw new HouseholdException(Label.Core_Households_ErrorMoveMissingInput);
        }
        List<Contact> people = HouseholdSelector.getContactsByIds(new Set<Id>{ contactId });
        List<Account> targets = HouseholdSelector.getHouseholdsByIds(
            new Set<Id>{ targetHouseholdId }
        );
        if (people.isEmpty() || targets.isEmpty()) {
            throw new HouseholdException(Label.Core_Households_ErrorMoveNotFound);
        }
        if (targets[0].RecordTypeId != householdRecordTypeId()) {
            throw new HouseholdException(Label.Core_Households_ErrorNotAHousehold);
        }
        Set<Id> affected = new Set<Id>{ targetHouseholdId };
        if (isJunctionMode()) {
            moveJunctionMember(contactId, targetHouseholdId, affected);
        } else {
            Contact person = people[0];
            if (person.AccountId != null) {
                affected.add(person.AccountId);
            }
            person.AccountId = targetHouseholdId;
            Database.update(new List<Contact>{ person }, AccessLevel.USER_MODE);
        }
        recalculateMemberCounts(affected);
        HouseholdNamingService.applyNaming(affected);
        deleteEmptyHouseholds(affected);
    }

    private static void moveJunctionMember(Id personId, Id targetHouseholdId, Set<Id> affected) {
        List<Household_Member__c> current = HouseholdSelector.getMembershipsForPeople(
            new Set<Id>{ personId }
        );
        List<Household_Member__c> ended = new List<Household_Member__c>();
        for (Household_Member__c membership : current) {
            if (membership.Household__c == targetHouseholdId) {
                continue;
            }
            affected.add(membership.Household__c);
            ended.add(new Household_Member__c(Id = membership.Id, End_Date__c = Date.today()));
        }
        if (!ended.isEmpty()) {
            Database.update(ended, AccessLevel.USER_MODE);
        }
        Database.insert(
            new List<Household_Member__c>{
                new Household_Member__c(
                    Household__c = targetHouseholdId,
                    Contact__c = personId,
                    Start_Date__c = Date.today()
                )
            },
            AccessLevel.USER_MODE
        );
    }

    /**
     * Recounts current members on each household given. R-H11.
     */
    public static void recalculateMemberCounts(Set<Id> householdIds) {
        if (householdIds == null || householdIds.isEmpty()) {
            return;
        }
        Map<Id, List<Person>> membersByHousehold = getMembers(householdIds);
        List<Account> updates = new List<Account>();
        for (Account household : HouseholdSelector.getHouseholdsByIds(householdIds)) {
            List<Person> members = membersByHousehold.get(household.Id);
            Decimal count = members == null ? 0 : members.size();
            if (household.Member_Count__c != count) {
                updates.add(new Account(Id = household.Id, Member_Count__c = count));
            }
        }
        if (!updates.isEmpty()) {
            Database.update(updates, AccessLevel.USER_MODE);
        }
    }

    /**
     * Deletes households that have been left with no members, when the org asks for that.
     * R-H12.
     */
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
            Database.delete(empties, AccessLevel.USER_MODE);
        }
    }
}

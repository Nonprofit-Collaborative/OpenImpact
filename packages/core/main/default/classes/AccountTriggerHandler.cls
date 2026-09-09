/**
 * Household upkeep when a household or a person record changes.
 *
 * A new household is never left without a name. When someone clears the custom name box,
 * the household goes back to being named from the org's patterns. In an org that stores
 * people as accounts, a new person gets a household and a membership of it, and every
 * later change to that person settles the households they belong to up again: a rename, a
 * deletion, a restore from the recycle bin.
 *
 * The person half of this class is the account side of what `ContactTriggerHandler` does
 * for a person stored as a contact, and it watches the same fields. What differs is where
 * the household is written down. A contact carries its household on the record itself, so
 * the contact handler can read it in any context, and it survives the contact being
 * deleted and restored. A person stored as an account is joined to a household by a
 * `Household_Member__c` row instead, and the platform empties that row's person lookup
 * when the account is deleted and does not fill it in again when the account is restored.
 * So the delete work happens in `beforeDelete`, while the rows still say what they are
 * for, and only the settling up is left to `afterDelete`.
 */
public with sharing class AccountTriggerHandler extends TriggerHandler {
    private static Boolean running = false;

    /**
     * The households the people currently being deleted are leaving. Filled in
     * `beforeDelete` and consumed in `afterDelete`, which is also where it is emptied
     * again: one DML of 400 records runs the pair twice, so each half has to hand over
     * only its own chunk.
     */
    private static Set<Id> departingHouseholdIds = new Set<Id>();

    public override void beforeInsert() {
        nameNewHouseholds((List<Account>) newRecords());
    }

    public override void beforeUpdate() {
        nameNewHouseholds((List<Account>) newRecords());
    }

    public override void afterInsert() {
        createHouseholdsForNewPeople((List<Account>) newRecords());
    }

    public override void afterUpdate() {
        Map<Id, Account> previousById = (Map<Id, Account>) oldRecordsById();
        Boolean watchPeople = handlesPeople();
        Set<Id> released = new Set<Id>();
        List<Account> renamedPeople = new List<Account>();
        for (Account record : (List<Account>) newRecords()) {
            Account previous = previousById.get(record.Id);
            Boolean wasCustom = previous != null && previous.Custom_Name__c == true;
            if (wasCustom && record.Custom_Name__c != true) {
                released.add(record.Id);
            }
            if (watchPeople && PersonRecordSelector.namingChanged(record, previous)) {
                renamedPeople.add(record);
            }
        }
        if (!released.isEmpty()) {
            HouseholdNamingService.applyNaming(released);
        }
        // R-H4 and R-H11. A person renamed, marked deceased, given a preferred name, moved
        // to another household role or excluded from the wording changes what every
        // household they belong to is called.
        HouseholdService.afterMembershipChange(householdIdsOf(renamedPeople), true);
    }

    /**
     * Takes the memberships of the people being deleted with them, while the rows still
     * say whose memberships they are, and remembers the households that affects.
     *
     * `Household_Member__c.Account__c` empties itself when the account it points at is
     * deleted, so by `afterDelete` the row no longer names anybody: the household it
     * belongs to cannot be worked out from it, and it cannot be put back either, because
     * the platform does not restore a lookup it emptied that way when the record comes
     * back out of the recycle bin. Removing the rows here, first, is what makes both the
     * delete and the undelete paths work.
     */
    public override void beforeDelete() {
        departingHouseholdIds = HouseholdService.removeMembershipsFor(
            personIdsOf((List<Account>) oldRecords())
        );
    }

    public override void afterDelete() {
        Set<Id> affected = departingHouseholdIds;
        departingHouseholdIds = new Set<Id>();
        // Tidying away is allowed here for the same reason it is on the contact delete
        // path: this is the household somebody was the last to leave (R-H12).
        HouseholdService.afterMembershipChange(affected, true);
    }

    /**
     * A person restored from the recycle bin gets their memberships back, and the
     * households they have rejoined are recounted and renamed. Never tidied away here:
     * nobody has left.
     */
    public override void afterUndelete() {
        Set<Id> personIds = personIdsOf((List<Account>) newRecords());
        Set<Id> affected = HouseholdService.restoreMembershipsFor(personIds);
        affected.addAll(HouseholdService.householdIdsForPeople(personIds));
        HouseholdService.afterMembershipChange(affected, false);
    }

    /**
     * True when this org keeps people on the account object and joins them to households
     * with membership rows. Asked once per context rather than once per record.
     */
    private static Boolean handlesPeople() {
        return HouseholdService.isPersonAccountOrg() && HouseholdService.isJunctionMode();
    }

    /**
     * The people among these records. A record that holds an organization or a household
     * rather than a person is left out, and on an org that does not keep people as
     * accounts the answer is empty without anything being read.
     */
    private static Set<Id> personIdsOf(List<Account> records) {
        Set<Id> result = new Set<Id>();
        if (records == null || records.isEmpty() || !handlesPeople()) {
            return result;
        }
        for (SObject person : PersonRecordSelector.filterPeople(records)) {
            if (person.Id != null) {
                result.add(person.Id);
            }
        }
        return result;
    }

    /**
     * The households every person among these records belongs to.
     */
    private static Set<Id> householdIdsOf(List<Account> records) {
        return HouseholdService.householdIdsForPeople(personIdsOf(records));
    }

    /**
     * A household saved with no name gets a placeholder rather than a save error. The
     * naming service replaces it as soon as the household has a member.
     */
    private static void nameNewHouseholds(List<Account> records) {
        Id recordTypeId = HouseholdService.householdRecordTypeId();
        if (recordTypeId == null) {
            return;
        }
        for (Account record : records) {
            Boolean isHousehold = record.RecordTypeId == recordTypeId;
            if (isHousehold && record.Custom_Name__c != true && String.isBlank(record.Name)) {
                record.Name = Label.Core_Households_NamePlaceholder;
            }
        }
    }

    /**
     * R-H2. Only in an org that stores people as accounts, only in junction mode, and only
     * when automatic household creation is on.
     *
     * That is the same setting a person stored as a contact is given a household by
     * (ADR-0037). The separate person account setting this used to read is retired: it
     * shipped off, so an org that took the recommended setup got no households at all and
     * was told nothing about it.
     */
    private static void createHouseholdsForNewPeople(List<Account> records) {
        if (running || records == null || records.isEmpty()) {
            return;
        }
        if (!handlesPeople()) {
            return;
        }
        Nonprofit_Settings__c settings = SettingsService.getSettings();
        if (settings == null || settings.Auto_Create_Households__c != true) {
            return;
        }
        List<SObject> people = PersonRecordSelector.filterPeople(records);
        if (people.isEmpty()) {
            return;
        }
        running = true;
        try {
            HouseholdService.createHouseholdsForPersonAccounts(people);
        } finally {
            running = false;
        }
    }
}

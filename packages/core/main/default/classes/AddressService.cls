/**
 * Addresses (C-17, canonical model Section 29).
 *
 * Two directions, and a single in-transaction flag keeps them from calling each other
 * round in a circle:
 *
 * 1. syncDefaultToStandardFields: the address marked default is copied into the standard
 *    address fields on its owner, and on every current household member, so mail merges,
 *    reports, and other apps keep reading the address they have always read (R-AD3).
 * 2. captureFromStandardFields: an address typed into the standard fields, or changed
 *    there, becomes or updates an address record, so the records stay the truth (R-AD5).
 *
 * No Person Account field is referenced statically anywhere in this class. Where people
 * are person accounts their mailing fields are written dynamically, by name, and only in
 * an org that has them (plan Section 4.2, ADR-0009).
 */
public with sharing class AddressService {
    @TestVisible
    private static Boolean isPropagating = false;

    @TestVisible
    private static final String BEHAVIOR_UPDATE_HOUSEHOLD = 'Update household';
    @TestVisible
    private static final String BEHAVIOR_PERSONAL_ADDRESS = 'Create personal address';

    private static final String TYPE_HOME = 'Home';
    private static final String TYPE_WORK = 'Work';
    private static final String TYPE_SEASONAL = 'Seasonal';

    private static final String RECORD_TYPE_HOUSEHOLD = 'Household';
    private static final String RECORD_TYPE_ORGANIZATION = 'Organization';

    // detection-only: Person Account orgs
    private static final String PERSON_MAILING_STREET = 'PersonMailingStreet';
    // detection-only: Person Account orgs
    private static final String PERSON_MAILING_CITY = 'PersonMailingCity';
    // detection-only: Person Account orgs
    private static final String PERSON_MAILING_STATE = 'PersonMailingState';
    // detection-only: Person Account orgs
    private static final String PERSON_MAILING_POSTAL_CODE = 'PersonMailingPostalCode';
    // detection-only: Person Account orgs
    private static final String PERSON_MAILING_COUNTRY = 'PersonMailingCountry';

    private static Map<String, Schema.SObjectField> accountFields;

    /**
     * Test seam. Household membership is read only through HouseholdService, which hides
     * whether the org uses contact mode or the membership junction. Junction mode, and
     * households whose people are person accounts, are reproduced here by handing this
     * class the membership HouseholdService would return, because the junction object and
     * person accounts cannot both be created in one org shape. Never set outside a test.
     */
    @TestVisible
    private static Map<Id, Set<Id>> membersByHouseholdOverride;

    // ---------------------------------------------------------------- direction one

    /**
     * Copies each default address into the standard address fields of its owner. An
     * address owned by an account writes the account's billing address and the mailing
     * address of every current household member; an address owned by one person writes
     * that person's mailing address only.
     */
    public static void syncDefaultToStandardFields(List<Address__c> addresses) {
        if (addresses == null || addresses.isEmpty() || isPropagating) {
            return;
        }
        List<Address__c> defaults = defaultsOnly(addresses);
        if (defaults.isEmpty()) {
            return;
        }
        isPropagating = true;
        try {
            clearOtherDefaults(defaults);
            applyToStandardFields(defaults);
        } finally {
            isPropagating = false;
        }
    }

    /**
     * After a default address is deleted, promotes the most recently created remaining
     * address for that owner. Deleting a default is allowed: refusing it would leave a
     * household stuck with an address it no longer uses.
     */
    public static void promoteDefaultAfterDelete(List<Address__c> deletedAddresses) {
        if (deletedAddresses == null || deletedAddresses.isEmpty() || isPropagating) {
            return;
        }
        Set<Id> ownerIds = new Set<Id>();
        Set<Id> deletedIds = new Set<Id>();
        for (Address__c address : deletedAddresses) {
            deletedIds.add(address.Id);
            if (address.Is_Default__c == true && ownerIdOf(address) != null) {
                ownerIds.add(ownerIdOf(address));
            }
        }
        if (ownerIds.isEmpty()) {
            return;
        }
        Map<Id, Address__c> newestByOwner = new Map<Id, Address__c>();
        for (Address__c address : AddressSelector.selectByOwnerIds(ownerIds)) {
            Id ownerId = ownerIdOf(address);
            if (deletedIds.contains(address.Id) || ownerId == null) {
                continue;
            }
            Address__c held = newestByOwner.get(ownerId);
            if (held == null || address.CreatedDate > held.CreatedDate) {
                newestByOwner.put(ownerId, address);
            }
        }
        if (newestByOwner.isEmpty()) {
            return;
        }
        List<Address__c> promoted = new List<Address__c>();
        for (Address__c address : newestByOwner.values()) {
            promoted.add(new Address__c(Id = address.Id, Is_Default__c = true));
        }
        Database.update(promoted, AccessLevel.USER_MODE);
        isPropagating = true;
        try {
            applyToStandardFields(new List<Address__c>(newestByOwner.values()));
        } finally {
            isPropagating = false;
        }
    }

    // ---------------------------------------------------------------- direction two

    /**
     * Turns an address typed into the standard fields into an address record.
     *
     * A household or organization account created with a billing address gets a default
     * address record of type Home (Work for an organization), so nothing staff typed or
     * an import loaded is lost. A person whose mailing address changes either moves their
     * whole household or gains an address of their own, depending on the org's
     * Contact_Address_Change_Behavior__c setting.
     */
    public static void captureFromStandardFields(List<Account> accounts, List<Contact> contacts) {
        Boolean nothingToDo =
            (accounts == null || accounts.isEmpty()) && (contacts == null || contacts.isEmpty());
        if (nothingToDo || isPropagating) {
            return;
        }
        isPropagating = true;
        try {
            List<Address__c> toInsert = new List<Address__c>();
            List<Address__c> toUpdate = new List<Address__c>();
            captureAccounts(accounts, toInsert);
            captureContacts(contacts, toInsert, toUpdate);
            if (!toUpdate.isEmpty()) {
                Database.update(toUpdate, AccessLevel.USER_MODE);
            }
            if (!toInsert.isEmpty()) {
                Database.insert(toInsert, AccessLevel.USER_MODE);
            }
            List<Address__c> touched = new List<Address__c>();
            touched.addAll(toUpdate);
            touched.addAll(toInsert);
            if (touched.isEmpty()) {
                return;
            }
            clearOtherDefaults(touched);
            applyToStandardFields(touched);
        } finally {
            isPropagating = false;
        }
    }

    // ---------------------------------------------------------------- seasonal helper

    /**
     * Whether a seasonal address covers today. A range may wrap the end of the year, so
     * November 1 to March 31 is one range and not two (R-AD4). The v0.4 seasonal swap job
     * (C-18) is the only planned caller; it needs no change to this object.
     */
    public static Boolean isSeasonalActiveToday(Address__c address) {
        return isSeasonalActiveOn(address, Date.today());
    }

    /** The same test against any day, so the swap job and its tests can name a date. */
    public static Boolean isSeasonalActiveOn(Address__c address, Date day) {
        if (address == null || day == null || address.Type__c != TYPE_SEASONAL) {
            return false;
        }
        if (
            address.Seasonal_Start_Month__c == null ||
            address.Seasonal_Start_Day__c == null ||
            address.Seasonal_End_Month__c == null ||
            address.Seasonal_End_Day__c == null
        ) {
            return false;
        }
        Integer today = (day.month() * 100) + day.day();
        Integer start =
            (address.Seasonal_Start_Month__c.intValue() * 100) +
            address.Seasonal_Start_Day__c.intValue();
        Integer finish =
            (address.Seasonal_End_Month__c.intValue() * 100) +
            address.Seasonal_End_Day__c.intValue();
        if (start <= finish) {
            return today >= start && today <= finish;
        }
        return today >= start || today <= finish;
    }

    // ---------------------------------------------------------------- internals

    private static List<Address__c> defaultsOnly(List<Address__c> addresses) {
        List<Address__c> defaults = new List<Address__c>();
        for (Address__c address : addresses) {
            if (address.Is_Default__c == true && ownerIdOf(address) != null) {
                defaults.add(address);
            }
        }
        return defaults;
    }

    private static Id ownerIdOf(Address__c address) {
        if (address.Account__c != null) {
            return address.Account__c;
        }
        if (address.Contact__c != null) {
            return address.Contact__c;
        }
        return address.Person_Account__c;
    }

    /** At most one address per owner is the default (R-AD2). */
    private static void clearOtherDefaults(List<Address__c> defaults) {
        Set<Id> ownerIds = new Set<Id>();
        Set<Id> keepIds = new Set<Id>();
        for (Address__c address : defaults) {
            if (address.Is_Default__c != true) {
                continue;
            }
            Id ownerId = ownerIdOf(address);
            if (ownerId != null) {
                ownerIds.add(ownerId);
                keepIds.add(address.Id);
            }
        }
        if (ownerIds.isEmpty()) {
            return;
        }
        List<Address__c> stale = new List<Address__c>();
        for (Address__c address : AddressSelector.selectDefaultsByOwnerIds(ownerIds, keepIds)) {
            stale.add(new Address__c(Id = address.Id, Is_Default__c = false));
        }
        if (!stale.isEmpty()) {
            Database.update(stale, AccessLevel.USER_MODE);
        }
    }

    /**
     * Writes the standard address fields. Only ever called with the propagation flag
     * already raised, so nothing it writes comes back round as another capture.
     */
    private static void applyToStandardFields(List<Address__c> defaults) {
        Map<Id, Address__c> byOwner = new Map<Id, Address__c>();
        for (Address__c address : defaults) {
            Id ownerId = ownerIdOf(address);
            if (address.Is_Default__c == true && ownerId != null) {
                byOwner.put(ownerId, address);
            }
        }
        if (byOwner.isEmpty()) {
            return;
        }

        Map<Id, Account> accountUpdates = new Map<Id, Account>();
        Map<Id, Contact> contactUpdates = new Map<Id, Contact>();
        Map<Id, Address__c> addressByHousehold = new Map<Id, Address__c>();

        for (Id ownerId : byOwner.keySet()) {
            Address__c address = byOwner.get(ownerId);
            if (address.Account__c != null) {
                accountUpdates.put(ownerId, billingCopy(ownerId, address));
                addressByHousehold.put(ownerId, address);
            } else if (address.Contact__c != null) {
                contactUpdates.put(ownerId, mailingCopy(ownerId, address));
            } else if (address.Person_Account__c != null) {
                Account personAccount = personMailingCopy(
                    ownerId,
                    address,
                    accountUpdates.get(ownerId)
                );
                if (personAccount != null) {
                    accountUpdates.put(ownerId, personAccount);
                }
            }
        }

        propagateToHouseholdMembers(addressByHousehold, accountUpdates, contactUpdates);

        if (!contactUpdates.isEmpty()) {
            Database.update(contactUpdates.values(), AccessLevel.USER_MODE);
        }
        if (!accountUpdates.isEmpty()) {
            Database.update(accountUpdates.values(), AccessLevel.USER_MODE);
        }
    }

    private static void propagateToHouseholdMembers(
        Map<Id, Address__c> addressByHousehold,
        Map<Id, Account> accountUpdates,
        Map<Id, Contact> contactUpdates
    ) {
        if (addressByHousehold.isEmpty()) {
            return;
        }
        Map<Id, Set<Id>> membersByHousehold = membersByHouseholdOverride != null
            ? membersByHouseholdOverride
            : HouseholdService.getMemberPersonIds(addressByHousehold.keySet());
        if (membersByHousehold == null || membersByHousehold.isEmpty()) {
            return;
        }
        Schema.SObjectType contactType = Contact.SObjectType;
        for (Id householdId : membersByHousehold.keySet()) {
            Address__c address = addressByHousehold.get(householdId);
            Set<Id> memberIds = membersByHousehold.get(householdId);
            if (address == null || memberIds == null) {
                continue;
            }
            for (Id memberId : memberIds) {
                if (memberId == null || memberId == householdId) {
                    continue;
                }
                if (memberId.getSObjectType() == contactType) {
                    contactUpdates.put(memberId, mailingCopy(memberId, address));
                } else {
                    Account personAccount = personMailingCopy(
                        memberId,
                        address,
                        accountUpdates.get(memberId)
                    );
                    if (personAccount != null) {
                        accountUpdates.put(memberId, personAccount);
                    }
                }
            }
        }
    }

    private static Account billingCopy(Id accountId, Address__c address) {
        return new Account(
            Id = accountId,
            BillingStreet = address.Street__c,
            BillingCity = address.City__c,
            BillingState = address.State__c,
            BillingPostalCode = address.Postal_Code__c,
            BillingCountry = address.Country__c
        );
    }

    private static Contact mailingCopy(Id contactId, Address__c address) {
        return new Contact(
            Id = contactId,
            MailingStreet = address.Street__c,
            MailingCity = address.City__c,
            MailingState = address.State__c,
            MailingPostalCode = address.Postal_Code__c,
            MailingCountry = address.Country__c
        );
    }

    /**
     * Writes the mailing fields a person account carries. The field names are held as
     * strings and written with put, so this class compiles and runs in an org where those
     * fields do not exist.
     */
    private static Account personMailingCopy(Id accountId, Address__c address, Account existing) {
        if (!personAccountFieldsAvailable()) {
            return null;
        }
        Account record = existing == null ? new Account(Id = accountId) : existing;
        record.put(PERSON_MAILING_STREET, address.Street__c);
        record.put(PERSON_MAILING_CITY, address.City__c);
        record.put(PERSON_MAILING_STATE, address.State__c);
        record.put(PERSON_MAILING_POSTAL_CODE, address.Postal_Code__c);
        record.put(PERSON_MAILING_COUNTRY, address.Country__c);
        return record;
    }

    private static Boolean personAccountFieldsAvailable() {
        if (!OrgShapeDetector.detect().hasPersonAccounts) {
            return false;
        }
        if (accountFields == null) {
            accountFields = Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                .fields
                .getMap();
        }
        return accountFields.containsKey(PERSON_MAILING_STREET.toLowerCase());
    }

    private static void captureAccounts(List<Account> accounts, List<Address__c> toInsert) {
        if (accounts == null || accounts.isEmpty()) {
            return;
        }
        Map<Id, Schema.RecordTypeInfo> recordTypes = Account.SObjectType.getDescribe(
                SObjectDescribeOptions.DEFERRED
            )
            .getRecordTypeInfosById();
        Set<Id> personAccountRecordTypeIds = OrgShapeDetector.detect().personAccountRecordTypeIds;
        for (Account account : accounts) {
            if (
                personAccountRecordTypeIds != null &&
                personAccountRecordTypeIds.contains(account.RecordTypeId)
            ) {
                continue;
            }
            String developerName = account.RecordTypeId == null ||
                recordTypes.get(account.RecordTypeId) == null
                ? null
                : recordTypes.get(account.RecordTypeId).getDeveloperName();
            if (
                developerName != RECORD_TYPE_HOUSEHOLD &&
                developerName != RECORD_TYPE_ORGANIZATION
            ) {
                continue;
            }
            if (
                !hasAnyValue(
                    account.BillingStreet,
                    account.BillingCity,
                    account.BillingState,
                    account.BillingPostalCode,
                    account.BillingCountry
                )
            ) {
                continue;
            }
            toInsert.add(
                new Address__c(
                    Account__c = account.Id,
                    Type__c = developerName == RECORD_TYPE_ORGANIZATION ? TYPE_WORK : TYPE_HOME,
                    Is_Default__c = true,
                    Street__c = account.BillingStreet,
                    City__c = account.BillingCity,
                    State__c = account.BillingState,
                    Postal_Code__c = account.BillingPostalCode,
                    Country__c = account.BillingCountry
                )
            );
        }
    }

    private static void captureContacts(
        List<Contact> contacts,
        List<Address__c> toInsert,
        List<Address__c> toUpdate
    ) {
        if (contacts == null || contacts.isEmpty()) {
            return;
        }
        List<Contact> withAddress = new List<Contact>();
        for (Contact contact : contacts) {
            if (
                hasAnyValue(
                    contact.MailingStreet,
                    contact.MailingCity,
                    contact.MailingState,
                    contact.MailingPostalCode,
                    contact.MailingCountry
                )
            ) {
                withAddress.add(contact);
            }
        }
        if (withAddress.isEmpty()) {
            return;
        }
        if (behavior() == BEHAVIOR_PERSONAL_ADDRESS) {
            capturePersonalAddresses(withAddress, toInsert, toUpdate);
        } else {
            captureHouseholdAddresses(withAddress, toInsert, toUpdate);
        }
    }

    private static void captureHouseholdAddresses(
        List<Contact> contacts,
        List<Address__c> toInsert,
        List<Address__c> toUpdate
    ) {
        Set<Id> contactIds = new Map<Id, Contact>(contacts).keySet();
        Map<Id, Set<Id>> householdsByPerson = HouseholdService.getHouseholdIdsFor(contactIds);
        if (householdsByPerson == null || householdsByPerson.isEmpty()) {
            return;
        }
        Map<Id, Contact> sourceByHousehold = new Map<Id, Contact>();
        for (Contact contact : contacts) {
            Set<Id> householdIds = householdsByPerson.get(contact.Id);
            if (householdIds == null) {
                continue;
            }
            for (Id householdId : householdIds) {
                sourceByHousehold.put(householdId, contact);
            }
        }
        if (sourceByHousehold.isEmpty()) {
            return;
        }
        Map<Id, Address__c> defaultByHousehold = new Map<Id, Address__c>();
        for (
            Address__c address : AddressSelector.selectDefaultsByOwnerIds(
                sourceByHousehold.keySet(),
                null
            )
        ) {
            if (address.Account__c != null) {
                defaultByHousehold.put(address.Account__c, address);
            }
        }
        for (Id householdId : sourceByHousehold.keySet()) {
            Contact source = sourceByHousehold.get(householdId);
            Address__c existing = defaultByHousehold.get(householdId);
            if (existing == null) {
                toInsert.add(newAddressFromContact(source, TYPE_HOME, householdId, null));
            } else {
                toUpdate.add(copyContactAddressOnto(new Address__c(Id = existing.Id), source));
            }
        }
    }

    private static void capturePersonalAddresses(
        List<Contact> contacts,
        List<Address__c> toInsert,
        List<Address__c> toUpdate
    ) {
        Set<Id> contactIds = new Map<Id, Contact>(contacts).keySet();
        Map<Id, Address__c> defaultByContact = new Map<Id, Address__c>();
        for (Address__c address : AddressSelector.selectDefaultsByOwnerIds(contactIds, null)) {
            if (address.Contact__c != null) {
                defaultByContact.put(address.Contact__c, address);
            }
        }
        for (Contact contact : contacts) {
            Address__c existing = defaultByContact.get(contact.Id);
            if (existing == null) {
                toInsert.add(newAddressFromContact(contact, TYPE_HOME, null, contact.Id));
            } else {
                toUpdate.add(copyContactAddressOnto(new Address__c(Id = existing.Id), contact));
            }
        }
    }

    private static Address__c newAddressFromContact(
        Contact source,
        String addressType,
        Id accountId,
        Id contactId
    ) {
        Address__c address = new Address__c(
            Account__c = accountId,
            Contact__c = contactId,
            Type__c = addressType,
            Is_Default__c = true
        );
        return copyContactAddressOnto(address, source);
    }

    private static Address__c copyContactAddressOnto(Address__c address, Contact source) {
        address.Street__c = source.MailingStreet;
        address.City__c = source.MailingCity;
        address.State__c = source.MailingState;
        address.Postal_Code__c = source.MailingPostalCode;
        address.Country__c = source.MailingCountry;
        address.Is_Default__c = true;
        return address;
    }

    private static String behavior() {
        Nonprofit_Settings__c settings = SettingsService.getSettings();
        String value = settings == null ? null : settings.Contact_Address_Change_Behavior__c;
        return String.isBlank(value) ? BEHAVIOR_UPDATE_HOUSEHOLD : value;
    }

    private static Boolean hasAnyValue(
        String street,
        String city,
        String state,
        String postalCode,
        String country
    ) {
        return String.isNotBlank(street) ||
            String.isNotBlank(city) ||
            String.isNotBlank(state) ||
            String.isNotBlank(postalCode) ||
            String.isNotBlank(country);
    }
}

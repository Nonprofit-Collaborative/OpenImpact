/**
 * Works out who gave, for the inbound gift API (feature X-03).
 *
 * The rule it enforces is the one the canonical model states in Section 4: a person reference is
 * a Contact and an Account, and exactly one of them is set. A gift therefore resolves to one
 * person or to one organization, never to both, never to several, and never to a donor this
 * endpoint invented. Where nothing matches, the gift is refused: creating constituents from an
 * inbound feed is how a database fills with duplicates, and the import framework already exists
 * for loading people with duplicate checking in front of it.
 *
 * Resolution is bulk. However many gifts are in one call, there are at most five queries.
 */
public with sharing class ConnectDonorResolver {
    private static final Integer MAX_EMAIL_LENGTH = 254;
    private static final Integer MAX_NAME_LENGTH = 255;

    /** Who one request resolved to, or why it did not. */
    public class Resolution {
        public Id contactId;
        public Id accountId;
        public String errorCode;
        public String message;

        public Boolean isResolved() {
            return errorCode == null && (contactId != null || accountId != null);
        }
    }

    /**
     * The donor for each request, keyed by the caller's own index so results line up with the
     * gifts that produced them.
     */
    public static Map<Integer, Resolution> resolve(Map<Integer, GiftIntakeRequest> requestsByIndex) {
        Map<Integer, Resolution> resolutions = new Map<Integer, Resolution>();
        if (requestsByIndex == null || requestsByIndex.isEmpty()) {
            return resolutions;
        }

        Set<Id> contactIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        Set<String> emails = new Set<String>();
        Set<String> organizationNames = new Set<String>();

        // First pass: everything that can be decided without a query, and the keys to look up.
        for (Integer index : requestsByIndex.keySet()) {
            GiftIntakeRequest request = requestsByIndex.get(index);
            Resolution resolution = new Resolution();
            resolutions.put(index, resolution);

            Integer named = 0;
            named += String.isNotBlank(request.donorContactId) ? 1 : 0;
            named += String.isNotBlank(request.donorAccountId) ? 1 : 0;
            named += String.isNotBlank(request.donorEmail) ? 1 : 0;
            named += String.isNotBlank(request.donorOrganizationName) ? 1 : 0;

            if (named == 0) {
                reject(resolution, GiftIntakeService.ERROR_DONOR_NOT_SPECIFIED, Label.Connect_Intake_DonorNotSpecified);
                continue;
            }
            if (named > 1) {
                reject(resolution, GiftIntakeService.ERROR_DONOR_CONFLICT, Label.Connect_Intake_DonorConflict);
                continue;
            }

            if (String.isNotBlank(request.donorContactId)) {
                Id parsed = asId(request.donorContactId, Contact.SObjectType);
                if (parsed == null) {
                    reject(resolution, GiftIntakeService.ERROR_DONOR_NOT_FOUND, Label.Connect_Intake_DonorNotFound);
                    continue;
                }
                resolution.contactId = parsed;
                contactIds.add(parsed);
                continue;
            }
            if (String.isNotBlank(request.donorAccountId)) {
                Id parsed = asId(request.donorAccountId, Account.SObjectType);
                if (parsed == null) {
                    reject(resolution, GiftIntakeService.ERROR_DONOR_NOT_FOUND, Label.Connect_Intake_DonorNotFound);
                    continue;
                }
                resolution.accountId = parsed;
                accountIds.add(parsed);
                continue;
            }
            if (String.isNotBlank(request.donorEmail)) {
                if (request.donorEmail.length() > MAX_EMAIL_LENGTH) {
                    reject(resolution, GiftIntakeService.ERROR_DONOR_NOT_FOUND, Label.Connect_Intake_DonorNotFound);
                    continue;
                }
                emails.add(request.donorEmail.trim().toLowerCase());
                continue;
            }
            if (request.donorOrganizationName.length() > MAX_NAME_LENGTH) {
                reject(resolution, GiftIntakeService.ERROR_DONOR_NOT_FOUND, Label.Connect_Intake_DonorNotFound);
                continue;
            }
            organizationNames.add(request.donorOrganizationName.trim());
        }

        // Second pass: the queries, one per way of naming a donor.
        Map<Id, Contact> contactsById = ConnectDonorSelector.selectContactsById(contactIds);
        Map<Id, Account> accountsById = ConnectDonorSelector.selectAccountsById(accountIds);
        Map<String, List<Id>> peopleByEmail = peopleByEmail(emails);
        Map<String, List<Id>> organizationsByName = organizationsByName(organizationNames);

        // Third pass: give every request its answer.
        for (Integer index : requestsByIndex.keySet()) {
            GiftIntakeRequest request = requestsByIndex.get(index);
            Resolution resolution = resolutions.get(index);
            if (resolution.errorCode != null) {
                continue;
            }

            if (resolution.contactId != null) {
                if (!contactsById.containsKey(resolution.contactId)) {
                    resolution.contactId = null;
                    reject(resolution, GiftIntakeService.ERROR_DONOR_NOT_FOUND, Label.Connect_Intake_DonorNotFound);
                }
                continue;
            }
            if (resolution.accountId != null) {
                if (!accountsById.containsKey(resolution.accountId)) {
                    resolution.accountId = null;
                    reject(resolution, GiftIntakeService.ERROR_DONOR_NOT_FOUND, Label.Connect_Intake_DonorNotFound);
                }
                continue;
            }
            if (String.isNotBlank(request.donorEmail)) {
                assign(resolution, peopleByEmail.get(request.donorEmail.trim().toLowerCase()));
                continue;
            }
            assign(resolution, organizationsByName.get(request.donorOrganizationName.trim()));
        }

        return resolutions;
    }

    /**
     * One match resolves, none is a rejection, and more than one is a rejection that says how
     * many, so the integrator knows to send an identifier instead. The count is the only thing
     * said about the matches: names and identifiers of people who did not give this gift are
     * not the caller's business (plan Section 4.13).
     */
    private static void assign(Resolution resolution, List<Id> matches) {
        if (matches == null || matches.isEmpty()) {
            reject(resolution, GiftIntakeService.ERROR_DONOR_NOT_FOUND, Label.Connect_Intake_DonorNotFound);
            return;
        }
        if (matches.size() > 1) {
            reject(
                resolution,
                GiftIntakeService.ERROR_DONOR_AMBIGUOUS,
                String.format(
                    Label.Connect_Intake_DonorAmbiguous,
                    new List<String>{ String.valueOf(matches.size()) }
                )
            );
            return;
        }
        Id match = matches[0];
        if (match.getSObjectType() == Contact.SObjectType) {
            resolution.contactId = match;
        } else {
            resolution.accountId = match;
        }
    }

    /**
     * People with each address, from both places a person can live: a contact record, and, in an
     * org that stores people as accounts, an account record. An address that finds one of each
     * is ambiguous and is refused, which is the honest answer: the two records are two donors
     * until somebody merges them.
     */
    private static Map<String, List<Id>> peopleByEmail(Set<String> emails) {
        Map<String, List<Id>> byEmail = new Map<String, List<Id>>();
        if (emails.isEmpty()) {
            return byEmail;
        }
        for (Contact person : ConnectDonorSelector.selectContactsByEmail(emails)) {
            add(byEmail, person.Email == null ? null : person.Email.toLowerCase(), person.Id);
        }
        Map<String, List<Id>> personAccounts = ConnectDonorSelector.selectPersonAccountIdsByEmail(
            emails
        );
        for (String address : personAccounts.keySet()) {
            for (Id personAccountId : personAccounts.get(address)) {
                add(byEmail, address, personAccountId);
            }
        }
        return byEmail;
    }

    private static Map<String, List<Id>> organizationsByName(Set<String> names) {
        Map<String, List<Id>> byName = new Map<String, List<Id>>();
        for (Account organization : ConnectDonorSelector.selectOrganizationsByName(names)) {
            add(byName, organization.Name, organization.Id);
        }
        return byName;
    }

    private static void add(Map<String, List<Id>> target, String key, Id value) {
        if (String.isBlank(key)) {
            return;
        }
        if (!target.containsKey(key)) {
            target.put(key, new List<Id>());
        }
        target.get(key).add(value);
    }

    private static void reject(Resolution resolution, String errorCode, String message) {
        resolution.errorCode = errorCode;
        resolution.message = message;
    }

    /**
     * The identifier the caller sent, when it is a well formed identifier of the object expected.
     * Anything else is not an error worth explaining in detail: it is answered as a donor that
     * could not be found, so a caller probing with made up identifiers learns nothing about what
     * is in the org.
     */
    private static Id asId(String value, Schema.SObjectType expected) {
        try {
            Id parsed = Id.valueOf(value.trim());
            return parsed.getSObjectType() == expected ? parsed : null;
        } catch (System.StringException malformed) {
            return null;
        }
    }
}

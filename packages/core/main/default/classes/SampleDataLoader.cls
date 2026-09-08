/**
 * Loads and removes the C-10 sample data set: 200 households, 440 contacts, and 25
 * organizations, read from the SampleData static resource. See data/sample/README.md for
 * the JSON format and docs/admin-guide/sample-data.md for the admin-facing behavior.
 *
 * load() is idempotent: it throws SampleDataException when sample data is already
 * present, and refuses to start while a load is still running. Because a synchronous
 * transaction cannot safely insert every household, organization, and contact (the
 * household naming and greeting triggers run on every contact insert), load() only
 * starts the queueable chain and returns immediately; call status() to track progress.
 * remove() runs synchronously; a few hundred deletes are well within limits for one
 * transaction, and it too refuses while a load is running so the chain cannot insert
 * contacts against households that have just been deleted.
 *
 * Errors are thrown, not logged here: SampleDataController logs once at the LWC
 * boundary, and the queueables log their own async failures.
 */
public with sharing class SampleDataLoader {
    /** Contacts inserted per contact-stage chunk (see SampleDataContactQueueable). */
    public static final Integer CONTACT_CHUNK_SIZE = 100;

    /** Injected by the tests in place of the static resource body. */
    @TestVisible
    private static String jsonOverride;

    /**
     * Injected by the tests in place of the AsyncApexJob query, so the refusal paths can
     * be asserted without an org that can hold a queued job. Null in production.
     */
    @TestVisible
    private static Boolean runningJobOverride;

    public class Counts {
        @AuraEnabled
        public Integer householdCount;
        @AuraEnabled
        public Integer organizationCount;
        @AuraEnabled
        public Integer contactCount;
        @AuraEnabled
        public Boolean loaded;
        @AuraEnabled
        public Boolean loading;
        /**
         * False when this org stores household membership as junction records, which the
         * sample set cannot express. The card says why rather than offering a load that
         * would produce 200 empty households.
         */
        @AuraEnabled
        public Boolean contactMembership;
    }

    /**
     * Starts loading the sample data set. Throws SampleDataException when this org keeps
     * household membership in junction records, when a load is already running, when
     * sample data is already present, or when the static resource is missing or does not
     * hold a usable payload.
     *
     * The sample set puts every member on its household through Contact.AccountId, which
     * is what contact membership means. In junction mode nothing would join a person to a
     * household, so the load is refused with a message naming the reason (canonical model
     * Section 3, household membership).
     */
    public static void load() {
        if (!isContactMembership()) {
            throw new SampleDataException(Label.Core_SampleData_ContactModeOnly);
        }
        if (hasRunningLoadJob()) {
            throw new SampleDataException(Label.Core_SampleData_LoadInProgress);
        }
        SampleDataSelector selector = new SampleDataSelector();
        if (selector.countSampleHouseholds() > 0 || selector.countSampleOrganizations() > 0) {
            throw new SampleDataException(Label.Core_SampleData_AlreadyLoaded);
        }
        // Parsed here so a malformed payload fails in front of the admin, with a readable
        // message, instead of inside a queueable the card can only report as "not loaded".
        SampleDataSet.parse(getSampleDataJson());
        System.enqueueJob(new SampleDataLoadQueueable());
    }

    /**
     * Deletes every household, organization, and contact flagged Sample_Data__c, and
     * returns the counts that were removed. Contacts are deleted first so no household is
     * ever left with a dangling AccountId reference mid-transaction.
     */
    public static Counts remove() {
        if (hasRunningLoadJob()) {
            throw new SampleDataException(Label.Core_SampleData_LoadInProgress);
        }
        SampleDataSelector selector = new SampleDataSelector();
        Counts result = new Counts();
        result.contactCount = selector.countSampleContacts();
        result.householdCount = selector.countSampleHouseholds();
        result.organizationCount = selector.countSampleOrganizations();

        List<Id> contactIds = selector.getSampleContactIds();
        if (!contactIds.isEmpty()) {
            Database.delete(contactIds, AccessLevel.USER_MODE);
        }
        List<Id> accountIds = selector.getSampleAccountIds();
        if (!accountIds.isEmpty()) {
            Database.delete(accountIds, AccessLevel.USER_MODE);
        }

        result.loaded = false;
        result.loading = false;
        result.contactMembership = isContactMembership();
        return result;
    }

    /**
     * Current counts of flagged records, and whether a load is still in progress. A user
     * who cannot read the Sample Data field gets zeros rather than an error, so the
     * read-only card still renders for them.
     */
    public static Counts status() {
        Counts result = new Counts();
        if (!canReadSampleDataFields()) {
            result.householdCount = 0;
            result.organizationCount = 0;
            result.contactCount = 0;
            result.loading = false;
            result.loaded = false;
            result.contactMembership = isContactMembership();
            return result;
        }

        SampleDataSelector selector = new SampleDataSelector();
        result.householdCount = selector.countSampleHouseholds();
        result.organizationCount = selector.countSampleOrganizations();
        result.contactCount = selector.countSampleContacts();
        result.loading = hasRunningLoadJob();
        result.loaded =
            !result.loading && (result.householdCount > 0 || result.organizationCount > 0);
        result.contactMembership = isContactMembership();
        return result;
    }

    /** True while any stage of the sample data load chain is queued or running. */
    public static Boolean hasRunningLoadJob() {
        if (runningJobOverride != null) {
            return runningJobOverride;
        }
        return new SampleDataSelector().hasRunningLoadJob();
    }

    /** The sample data JSON body, from the injected override or the static resource. */
    public static String getSampleDataJson() {
        if (jsonOverride != null) {
            return jsonOverride;
        }
        StaticResource resource = new SampleDataSelector().getSampleDataResource();
        if (resource == null) {
            throw new SampleDataException(Label.Core_SampleData_ResourceMissing);
        }
        return resource.Body.toString();
    }

    /** True while household members are stored as contacts, which is what the sample set assumes. */
    public static Boolean isContactMembership() {
        return !HouseholdService.isJunctionMode();
    }

    private static Boolean canReadSampleDataFields() {
        return Schema.SObjectType.Account.fields.Sample_Data__c.isAccessible() &&
            Schema.SObjectType.Contact.fields.Sample_Data__c.isAccessible();
    }
}

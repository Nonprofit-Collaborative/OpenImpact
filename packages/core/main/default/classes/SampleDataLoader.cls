/**
 * Loads and removes the C-10 sample data set: about 200 households, roughly 430 contacts,
 * and 25 organizations, read from the SampleData static resource. See
 * data/sample/README.md for the JSON format and docs/admin-guide/sample-data.md for the
 * admin-facing behavior.
 *
 * load() is idempotent: it throws SampleDataException when sample data is already
 * present. Because a synchronous transaction cannot safely insert every household,
 * organization, and contact (the household naming and greeting triggers run on every
 * contact insert), load() only starts a SampleDataLoadQueueable chain and returns
 * immediately; call status() to track progress. remove() runs synchronously; a few
 * hundred deletes are well within limits for one transaction.
 */
public with sharing class SampleDataLoader {
    /** Contacts inserted per SampleDataLoadQueueable chunk (see that class). */
    public static final Integer CONTACT_CHUNK_SIZE = 100;

    /** Injected by SampleDataLoaderTest in place of the static resource body. */
    @TestVisible
    private static String jsonOverride;

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
    }

    /**
     * Starts loading the sample data set. Throws SampleDataException, logged first, when
     * sample data is already present or the static resource cannot be read.
     */
    public static void load() {
        try {
            SampleDataSelector selector = new SampleDataSelector();
            if (selector.countSampleHouseholds() > 0 || selector.countSampleOrganizations() > 0) {
                throw new SampleDataException(Label.Core_SampleData_AlreadyLoaded);
            }
            String jsonBody = getSampleDataJson();
            System.enqueueJob(new SampleDataLoadQueueable(jsonBody));
        } catch (Exception e) {
            ErrorLogger.log(e, 'SampleDataLoader.load');
            throw e;
        }
    }

    /**
     * Deletes every household, organization, and contact flagged Sample_Data__c, and
     * returns the counts that were removed. Contacts are deleted first so no household is
     * ever left with a dangling AccountId reference mid-transaction.
     */
    public static Counts remove() {
        try {
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
            return result;
        } catch (Exception e) {
            ErrorLogger.log(e, 'SampleDataLoader.remove');
            throw e;
        }
    }

    /** Current counts of flagged records, and whether a load is still in progress. */
    public static Counts status() {
        try {
            SampleDataSelector selector = new SampleDataSelector();
            Counts result = new Counts();
            result.householdCount = selector.countSampleHouseholds();
            result.organizationCount = selector.countSampleOrganizations();
            result.contactCount = selector.countSampleContacts();
            result.loading = selector.hasRunningLoadJob();
            result.loaded =
                !result.loading && (result.householdCount > 0 || result.organizationCount > 0);
            return result;
        } catch (Exception e) {
            ErrorLogger.log(e, 'SampleDataLoader.status');
            throw e;
        }
    }

    private static String getSampleDataJson() {
        if (jsonOverride != null) {
            return jsonOverride;
        }
        StaticResource resource = new SampleDataSelector().getSampleDataResource();
        if (resource == null) {
            throw new SampleDataException(Label.Core_SampleData_ResourceMissing);
        }
        return resource.Body.toString();
    }
}

/**
 * Reads the shipped Setting Definition rows that tell the Nonprofit Settings console
 * what to show, in the order the console shows them.
 */
public with sharing class SettingDefinitionSelector {
    /**
     * Rows used instead of the shipped ones. Custom metadata records cannot be created in
     * a test, so tests set this to in-memory rows.
     */
    @TestVisible
    private static List<Setting_Definition__mdt> stubbedRows;

    /** Read once per transaction: the console, the service and the search all ask for the list. */
    private static List<Setting_Definition__mdt> cachedRows;

    public static List<Setting_Definition__mdt> getAll() {
        if (stubbedRows != null) {
            return stubbedRows;
        }
        if (cachedRows != null) {
            return cachedRows;
        }
        cachedRows = [
            SELECT
                DeveloperName,
                MasterLabel,
                Setting_Key__c,
                Settings_Object__c,
                Section__c,
                Module__c,
                Data_Type__c,
                Picklist_Values__c,
                Component__c,
                Navigation_Target__c,
                Description__c,
                Help_Path__c,
                Sort_Order__c
            FROM Setting_Definition__mdt
            WITH USER_MODE
            ORDER BY Section__c, Sort_Order__c, MasterLabel
        ];
        return cachedRows;
    }
}

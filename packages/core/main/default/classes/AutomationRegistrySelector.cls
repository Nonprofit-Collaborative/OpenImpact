/**
 * Every query against the shipped automation registry.
 *
 * The registry is package-shipped custom metadata, read only to administrators, and it holds no
 * organization data, so it is read as shipped rather than in user mode.
 *
 * v0.1 ships the type with no records. Feature C-01 adds the first entries, for the contact and
 * account handlers, in the same change that adds those triggers.
 */
public with sharing class AutomationRegistrySelector {
    public static List<Automation_Registry__mdt> selectAll() {
        return [
            SELECT
                DeveloperName,
                MasterLabel,
                Description__c,
                Handler_Class__c,
                Object_Name__c,
                Execution_Order__c,
                Enabled_By_Default__c
            FROM Automation_Registry__mdt
            WITH SYSTEM_MODE
            ORDER BY Execution_Order__c NULLS LAST, DeveloperName
            LIMIT 1000
        ];
    }
}

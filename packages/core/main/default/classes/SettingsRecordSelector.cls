/**
 * Reads the org-level record of a settings object the running package does not know at
 * compile time.
 *
 * Each package owns its own protected hierarchy custom setting (ADR-0017), so Core cannot
 * name a module's settings object statically. The query is built from describe results and
 * bound parameters only.
 *
 * It runs in system mode, the same access `Nonprofit_Settings__c.getOrgDefaults()` gives Core's
 * own settings. A setting is org configuration that package code reads on behalf of whoever is
 * saving (a fundraiser's gift save asks whether household members are credited), and a
 * protected custom setting cannot be granted to a subscriber user, so a user mode read failed
 * that save for every user without field access to the whole object. Changing a value is still
 * gated on the custom permission inside `SettingsWriter`.
 */
public with sharing class SettingsRecordSelector {
    public static SObject getOrgDefault(Schema.SObjectType type) {
        Schema.DescribeSObjectResult describe = type.getDescribe(SObjectDescribeOptions.DEFERRED);
        List<String> fields = new List<String>();
        for (Schema.SObjectField token : describe.fields.getMap().values()) {
            fields.add(token.getDescribe().getName());
        }
        String soql =
            'SELECT ' +
            String.join(fields, ', ') +
            ' FROM ' +
            describe.getName() +
            ' WHERE SetupOwnerId = :ownerId LIMIT 1';
        List<SObject> records = Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'ownerId' => UserInfo.getOrganizationId() },
            AccessLevel.SYSTEM_MODE
        );
        return records.isEmpty() ? null : records[0];
    }
}

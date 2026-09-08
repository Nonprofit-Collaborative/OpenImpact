/**
 * Reads the org-level record of a settings object the running package does not know at
 * compile time.
 *
 * Each package owns its own protected hierarchy custom setting (ADR-0017), so Core cannot
 * name a module's settings object statically. The query is built from describe results and
 * bound parameters only, and runs in user mode.
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
            AccessLevel.USER_MODE
        );
        return records.isEmpty() ? null : records[0];
    }
}

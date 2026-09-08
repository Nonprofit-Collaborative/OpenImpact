/**
 * Counts the errors the Hub tile shows.
 *
 * The Error Log belongs to another feature and may not be present in a given package
 * build, so the object and its status field are checked by describe and the count runs as
 * a dynamic query in user mode. When the object is absent, the tile shows zero.
 */
public with sharing class HubErrorCountSelector {
    private static final String ERROR_LOG = 'Error_Log__c';
    private static final String STATUS_FIELD = 'status__c';
    private static final String STATUS_NEW = 'New';

    public static Integer countNewErrors() {
        Schema.SObjectType errorLog = Schema.getGlobalDescribe().get(ERROR_LOG);
        if (errorLog == null) {
            return 0;
        }
        Schema.DescribeSObjectResult describe = errorLog.getDescribe(
            SObjectDescribeOptions.DEFERRED
        );
        if (!describe.isAccessible() || !describe.fields.getMap().containsKey(STATUS_FIELD)) {
            return 0;
        }
        return Database.countQueryWithBinds(
            'SELECT COUNT() FROM ' + ERROR_LOG + ' WHERE Status__c = :statusNew',
            new Map<String, Object>{ 'statusNew' => STATUS_NEW },
            AccessLevel.USER_MODE
        );
    }
}

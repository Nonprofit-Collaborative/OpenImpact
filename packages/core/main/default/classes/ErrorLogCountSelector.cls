/**
 * Counts Error Log rows for Health Check (plan Section 4.8). Counting, not listing: Health
 * Check says how many entries nobody has read and sends the administrator to the tab.
 */
public with sharing class ErrorLogCountSelector {
    @TestVisible
    private static final String STATUS_NEW = 'New';

    /**
     * How many Error Log entries nobody has looked at yet.
     */
    public static Integer countNew() {
        return [SELECT COUNT() FROM Error_Log__c WHERE Status__c = :STATUS_NEW WITH USER_MODE];
    }

    /**
     * The relative URL of the Error Log list view, resolved through describe so that it is
     * correct whatever namespace the package carries.
     */
    public static String listViewUrl() {
        return '/lightning/o/' +
            Error_Log__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName() +
            '/list';
    }
}

/** Reads the audit trail of settings changes, newest first. */
public with sharing class SettingChangeSelector {
    private static final Integer DEFAULT_LIMIT = 10;
    private static final Integer MAXIMUM_LIMIT = 200;

    public static List<Setting_Change__c> getRecent(Integer limitCount) {
        Integer size = (limitCount == null ||
            limitCount <= 0)
            ? DEFAULT_LIMIT
            : Math.min(limitCount, MAXIMUM_LIMIT);
        return [
            SELECT
                Id,
                Setting_Name__c,
                Old_Value__c,
                New_Value__c,
                Changed_By__c,
                Changed_By__r.Name,
                Changed_At__c
            FROM Setting_Change__c
            WITH USER_MODE
            ORDER BY Changed_At__c DESC
            LIMIT :size
        ];
    }
}

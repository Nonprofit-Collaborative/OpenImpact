/**
 * The one query org shape detection needs (feature C-07). It lives in a selector because
 * every SOQL statement does (plan Section 7.1).
 *
 * The query is dynamic on purpose. The field it filters on exists only in an org where
 * Person Accounts are enabled, so a static query would stop Core compiling on a
 * Platform-only org (ADR-0009, ADR-0013). OrgShapeDetector calls this only after it has
 * established from the Account field map that Person Accounts are on.
 */
public with sharing class OrgShapeSelector {
    private static final String PERSON_RECORD_TYPE_QUERY = 'SELECT Id FROM RecordType WHERE SobjectType = \'Account\' AND IsPersonType = true';

    /**
     * The Account record types that describe themselves as person types.
     */
    public static Set<Id> personTypeRecordTypeIds() {
        Set<Id> recordTypeIds = new Set<Id>();
        for (SObject recordType : Database.query(PERSON_RECORD_TYPE_QUERY, AccessLevel.USER_MODE)) {
            recordTypeIds.add((Id) recordType.get('Id'));
        }
        return recordTypeIds;
    }
}

/**
 * The reads behind the posting and closed period lock (G-20, ADR-NEXT).
 *
 * `selectLockStateByIds` runs in system mode for field and object access and keeps the running
 * user's sharing (the class is `with sharing`): it decides whether a save is refused, and a rule
 * that holds only for users granted read on Posted to Accounting is not a rule. It returns no
 * value to anyone; the lock reads it and refuses or allows (ADR-0021, reads that compute a
 * package decision). A person who can save an allocation can see its gift, because an
 * allocation's access comes from its gift.
 */
public with sharing class GiftPostingSelector {
    public static List<Gift__c> selectLockStateByIds(Set<Id> giftIds) {
        return [
            SELECT Id, Status__c, Type__c, Gift_Date__c, Accounting_Posted_At__c
            FROM Gift__c
            WHERE Id IN :giftIds
            WITH SYSTEM_MODE
        ];
    }
}

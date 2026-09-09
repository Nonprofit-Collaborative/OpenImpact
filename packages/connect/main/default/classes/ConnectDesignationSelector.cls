/**
 * All SOQL the inbound gift API runs against Fund__c and Appeal__c, in user mode.
 *
 * Every lookup is bulk: one query per way of naming a fund or an appeal, however many gifts are
 * in the call.
 */
public with sharing class ConnectDesignationSelector {
    public static Map<Id, Fund__c> selectFundsById(Set<Id> fundIds) {
        if (fundIds == null || fundIds.isEmpty()) {
            return new Map<Id, Fund__c>();
        }
        return new Map<Id, Fund__c>(
            [
                SELECT Id, Name, Active__c, Accounting_Code__c
                FROM Fund__c
                WHERE Id IN :fundIds
                WITH USER_MODE
                LIMIT 500
            ]
        );
    }

    /**
     * Funds by accounting code. R-F3 makes the code unique, so this is the naming a processor
     * should send.
     */
    public static List<Fund__c> selectFundsByAccountingCode(Set<String> codes) {
        if (codes == null || codes.isEmpty()) {
            return new List<Fund__c>();
        }
        return [
            SELECT Id, Name, Active__c, Accounting_Code__c
            FROM Fund__c
            WHERE Accounting_Code__c IN :codes
            WITH USER_MODE
            LIMIT 500
        ];
    }

    /** Funds by name, which is not unique, so a caller sending an ambiguous name is told so. */
    public static List<Fund__c> selectFundsByName(Set<String> names) {
        if (names == null || names.isEmpty()) {
            return new List<Fund__c>();
        }
        return [
            SELECT Id, Name, Active__c, Accounting_Code__c
            FROM Fund__c
            WHERE Name IN :names
            WITH USER_MODE
            LIMIT 500
        ];
    }

    public static Map<Id, Appeal__c> selectAppealsById(Set<Id> appealIds) {
        if (appealIds == null || appealIds.isEmpty()) {
            return new Map<Id, Appeal__c>();
        }
        return new Map<Id, Appeal__c>(
            [SELECT Id, Name, Active__c FROM Appeal__c WHERE Id IN :appealIds WITH USER_MODE LIMIT 500]
        );
    }

    public static List<Appeal__c> selectAppealsByName(Set<String> names) {
        if (names == null || names.isEmpty()) {
            return new List<Appeal__c>();
        }
        return [
            SELECT Id, Name, Active__c
            FROM Appeal__c
            WHERE Name IN :names
            WITH USER_MODE
            LIMIT 500
        ];
    }

    /**
     * The payment methods a gift may carry, read from the picklist rather than held as a list
     * here, so this endpoint accepts exactly what the app accepts and cannot fall behind it.
     */
    public static Set<String> paymentMethods() {
        Set<String> values = new Set<String>();
        for (
            Schema.PicklistEntry entry : Gift__c.Type__c.getDescribe().getPicklistValues()
        ) {
            if (entry.isActive()) {
                values.add(entry.getValue());
            }
        }
        return values;
    }
}

/**
 * The lookups a gift import makes within the importing user's sharing: funds and appeals (R-GI3,
 * R-GI4) and the credits on the gifts it just made. What already exists in the org is read by
 * GiftImportIntegritySelector.
 */
public with sharing class GiftImportSelector {
    /**
     * The funds a file could mean by these words: by identifier, by name or by accounting code.
     * Inactive funds are included, because a migration names funds that have closed (R-GI4).
     * Read in the user's own mode: a fund the user cannot see is one they cannot allocate to.
     */
    public static List<Fund__c> selectFundsNamed(Set<String> words) {
        Set<Id> ids = idsAmong(words);
        return [
            SELECT Id, Name, Accounting_Code__c
            FROM Fund__c
            WHERE Id IN :ids OR Name IN :words OR Accounting_Code__c IN :words
            WITH USER_MODE
            LIMIT 2000
        ];
    }

    /** The appeals a file could mean by these words: by identifier or by name. */
    public static List<Appeal__c> selectAppealsNamed(Set<String> words) {
        Set<Id> ids = idsAmong(words);
        return [
            SELECT Id, Name
            FROM Appeal__c
            WHERE Id IN :ids OR Name IN :words
            WITH USER_MODE
            LIMIT 2000
        ];
    }

    /**
     * The soft credits already on these gifts, the automatic household ones included. The
     * gifts are the ones this import just made, so the importing user can see them.
     */
    public static List<Soft_Credit__c> selectCreditsOnGifts(Set<Id> giftIds) {
        return [
            SELECT Id, Gift__c, Contact__c, Account__c, Role__c
            FROM Soft_Credit__c
            WHERE Gift__c IN :giftIds
            WITH SYSTEM_MODE
        ];
    }

    /** The words that are record identifiers; a word that is not one is simply not an id. */
    private static Set<Id> idsAmong(Set<String> words) {
        Set<Id> ids = new Set<Id>();
        for (String word : words) {
            if (word != null && (word.length() == 15 || word.length() == 18)) {
                try {
                    ids.add(Id.valueOf(word));
                } catch (Exception notAnId) {
                    continue;
                }
            }
        }
        return ids;
    }
}

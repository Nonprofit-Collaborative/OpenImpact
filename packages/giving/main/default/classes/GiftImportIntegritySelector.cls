/**
 * The reads a gift import makes about what already exists in the org, whoever is importing
 * (R-DM1, R-GI9). ADR-0021 (system mode for package owned data) and ADR-NEXT.
 *
 * `without sharing` and `WITH SYSTEM_MODE`, because each answer is a fact about the org, not
 * about what the importing user may see: a gift already loaded under this external ID that the
 * user cannot see must still stop a second copy (the platform refuses the duplicate anyway, and
 * the row would fail with a message naming nothing), and a receipt the user cannot see must still
 * keep its gift when an import is undone. None of these reads is shown to anybody: each only
 * decides whether a row is matched or a record is kept. The inputs are values from the staged
 * rows or identifiers the import itself made; nothing reaches a dynamic query.
 */
public without sharing class GiftImportIntegritySelector {
    /** The gifts already carrying these external identifiers (R-DM1). */
    public static List<Gift__c> selectByExternalIds(Set<String> externalIds) {
        return [
            SELECT Id, External_Id__c
            FROM Gift__c
            WHERE External_Id__c IN :externalIds
            WITH SYSTEM_MODE
        ];
    }
}

/**
 * The saved queries other people marked shared (R-Q6). The one read in Find that crosses
 * sharing, recorded as C-34 decision 2 in ADR-0047 (amended), the ADR the dynamic Apex guide
 * asks a user-facing system-mode read to have. It keeps these conditions:
 *
 * - It is reached only by a holder of `Find_And_Export_Records` or `Bulk_Update_Records`
 *   (C-35 decision 6), checked here, not only by the caller.
 * - It reads `Saved_Query__c` rows whose shared flag is set, and nothing else: never a
 *   record the query would return. Opening one compiles it again as the person opening it, so
 *   what they see is what their own access allows.
 * - It reads only the name, object, owner and document, and writes nothing. Changing or
 *   deleting a query stays in user mode, where only its owner may.
 */
@NamespaceAccessible
public without sharing class SavedQuerySharedReader {
    private static final Integer MAX_LISTED = 200;

    /** Set only by tests, so the gate can be asserted without assigning a permission. */
    @TestVisible
    private static Boolean permissionOverride;

    private static final String FIELDS = 'Id, Name, Object_Name__c, Is_Shared__c, Query_JSON__c, OwnerId, Owner.Name, LastModifiedDate';

    /** Queries other people shared, by name. Empty for someone who uses neither tool. */
    @NamespaceAccessible
    public static List<Saved_Query__c> sharedByOthers() {
        if (!mayRead()) {
            return new List<Saved_Query__c>();
        }
        return Database.queryWithBinds(
            'SELECT ' +
                FIELDS +
                ' FROM Saved_Query__c WHERE Is_Shared__c = true AND OwnerId != :me' +
                ' ORDER BY Name ASC LIMIT :maxListed',
            new Map<String, Object>{ 'me' => UserInfo.getUserId(), 'maxListed' => MAX_LISTED },
            AccessLevel.SYSTEM_MODE
        );
    }

    /** One shared query by its identifier, or null when it is not shared (or gone). */
    @NamespaceAccessible
    public static Saved_Query__c sharedById(Id queryId) {
        if (queryId == null || !mayRead()) {
            return null;
        }
        List<Saved_Query__c> found = Database.queryWithBinds(
            'SELECT ' +
                FIELDS +
                ' FROM Saved_Query__c WHERE Id = :queryId AND Is_Shared__c = true LIMIT 1',
            new Map<String, Object>{ 'queryId' => queryId },
            AccessLevel.SYSTEM_MODE
        );
        return found.isEmpty() ? null : found[0];
    }

    private static Boolean mayRead() {
        if (permissionOverride != null) {
            return permissionOverride;
        }
        return FeatureManagement.checkPermission(FindController.PERMISSION) ||
            FeatureManagement.checkPermission(BulkUpdateController.PERMISSION);
    }
}

/**
 * Saved queries (canonical model Section 17B, R-Q6): a person's own, read and written in user
 * mode, and the ones other people shared, listed through `SavedQuerySharedReader`.
 *
 * A document is compiled as the person saving it before it is kept, so a saved query is always
 * one that ran for its owner; it is compiled again as whoever opens it later. What is kept is
 * the document as `QueryDocument` reads it back, so nothing the browser added beyond the
 * document's own shape is stored.
 */
@NamespaceAccessible
public with sharing class SavedQueryService {
    private static final Integer MAX_OWN = 200;
    private static final Integer MAX_NAME = 80;

    /** One saved query as the screens show it. */
    @NamespaceAccessible
    public class SavedQueryView {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String objectName;
        @AuraEnabled
        public Boolean isShared;
        /** True when the running user owns it and may change or delete it. */
        @AuraEnabled
        public Boolean isOwn;
        @AuraEnabled
        public String ownerName;
        @AuraEnabled
        public String document;
    }

    /** The running user's own queries, then the ones others shared, each by name. */
    @NamespaceAccessible
    public static List<SavedQueryView> listAll() {
        List<SavedQueryView> result = new List<SavedQueryView>();
        for (Saved_Query__c query : own(null)) {
            result.add(toView(query, true));
        }
        for (Saved_Query__c query : SavedQuerySharedReader.sharedByOthers()) {
            result.add(toView(query, false));
        }
        return result;
    }

    /** One query the running user owns, or one somebody shared; refused otherwise. */
    @NamespaceAccessible
    public static SavedQueryView open(Id queryId) {
        List<Saved_Query__c> mine = own(queryId);
        if (!mine.isEmpty()) {
            return toView(mine[0], true);
        }
        Saved_Query__c shared = SavedQuerySharedReader.sharedById(queryId);
        if (shared == null) {
            throw new DataManagementException(Label.Core_Find_ErrorSavedGone);
        }
        return toView(shared, shared.OwnerId == UserInfo.getUserId());
    }

    /**
     * Saves a query. With an identifier, it replaces that query, which only its owner may do;
     * without one, it is a new query owned by the running user.
     */
    @NamespaceAccessible
    public static SavedQueryView save(
        Id queryId,
        String name,
        Boolean isShared,
        String documentJson
    ) {
        if (String.isBlank(name)) {
            throw new DataManagementException(Label.Core_Find_ErrorNameRequired);
        }
        QueryDocument document = QueryDocument.parse(documentJson);
        QueryCompiler.Compiled compiled = QueryCompiler.compile(document);
        Saved_Query__c record = new Saved_Query__c(
            Name = name.trim().abbreviate(MAX_NAME),
            Object_Name__c = compiled.objectName,
            Is_Shared__c = isShared == true,
            Query_JSON__c = document.serialize()
        );
        if (queryId != null) {
            if (own(queryId).isEmpty()) {
                throw new DataManagementException(Label.Core_Find_ErrorNotOwner);
            }
            record.Id = queryId;
            Database.update(record, AccessLevel.USER_MODE);
        } else {
            Database.insert(record, AccessLevel.USER_MODE);
        }
        return open(record.Id);
    }

    /** Deletes a query the running user owns; anybody else's is refused. */
    @NamespaceAccessible
    public static void remove(Id queryId) {
        List<Saved_Query__c> mine = own(queryId);
        if (mine.isEmpty()) {
            throw new DataManagementException(Label.Core_Find_ErrorNotOwner);
        }
        Database.delete(mine[0], AccessLevel.USER_MODE);
    }

    /** The running user's own queries, or the one named, in user mode. */
    private static List<Saved_Query__c> own(Id queryId) {
        Map<String, Object> binds = new Map<String, Object>{
            'me' => UserInfo.getUserId(),
            'maxOwn' => MAX_OWN
        };
        String filter = '';
        if (queryId != null) {
            filter = ' AND Id = :queryId';
            binds.put('queryId', queryId);
        }
        return Database.queryWithBinds(
            'SELECT Id, Name, Object_Name__c, Is_Shared__c, Query_JSON__c, OwnerId, Owner.Name ' +
                'FROM Saved_Query__c WHERE OwnerId = :me' +
                filter +
                ' ORDER BY Name ASC LIMIT :maxOwn',
            binds,
            AccessLevel.USER_MODE
        );
    }

    private static SavedQueryView toView(Saved_Query__c query, Boolean isOwn) {
        SavedQueryView view = new SavedQueryView();
        view.id = query.Id;
        view.name = query.Name;
        view.objectName = query.Object_Name__c;
        view.isShared = query.Is_Shared__c;
        view.isOwn = isOwn;
        view.ownerName = query.Owner?.Name;
        view.document = query.Query_JSON__c;
        return view;
    }
}

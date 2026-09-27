/**
 * The entry points the Find page calls (C-34, plan Section 4.9, ADR-0047 amended).
 *
 * Every method checks `Find_And_Export_Records` first. The permission opens the tool and grants
 * no record access: everything below reads in user mode through `QueryCompiler` and
 * `QuerySelector`, and the only thing the browser sends is a query document, never query text.
 *
 * A refusal the person can act on (a field they may not read, a filter that does not suit its
 * field) is shown as it is and not logged; anything else is logged once and shown with its own
 * message.
 */
public with sharing class FindController {
    /** The custom permission that opens Find. */
    @NamespaceAccessible
    public static final String PERMISSION = 'Find_And_Export_Records';

    /** Set only by tests, so the permitted path can be asserted without assigning a permission. */
    @TestVisible
    private static Boolean permissionOverride;

    private static final Set<String> HIDDEN_SUFFIXES = new Set<String>{
        '__mdt',
        '__e',
        '__b',
        '__x',
        'share',
        'history',
        'feed',
        'changeevent'
    };

    /** What the page needs before anything is chosen. */
    public class Context {
        @AuraEnabled
        public Boolean canUse = false;
        @AuraEnabled
        public Integer exportRowLimit;
        @AuraEnabled
        public Integer gridMaxRows = QuerySelector.GRID_MAX_ROWS;
        @AuraEnabled
        public Integer maxFields = QueryDocument.MAX_FIELDS;
        @AuraEnabled
        public Integer maxConditions = QueryDocument.MAX_CONDITIONS;
        @AuraEnabled
        public Integer maxSortFields = QueryDocument.MAX_SORT_FIELDS;
        /** The bulk update tab, with any namespace, when the person may use it; else null. */
        @AuraEnabled
        public String bulkUpdateTab;
    }

    /** One kind of record the person may query. */
    public class ObjectOption {
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String label;
    }

    /** One field of an object, as the pickers offer it. */
    public class FieldOption {
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String type;
        @AuraEnabled
        public Boolean filterable;
        @AuraEnabled
        public Boolean sortable;
        @AuraEnabled
        public Boolean showable;
        /** For a lookup that can be followed: its relationship name and the object it reaches. */
        @AuraEnabled
        public String relationshipName;
        @AuraEnabled
        public String relationshipLabel;
        @AuraEnabled
        public String referenceTo;
        @AuraEnabled
        public List<Map<String, String>> picklistValues;
    }

    /** One object's readable fields. */
    public class ObjectDescription {
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String pluralLabel;
        @AuraEnabled
        public List<FieldOption> fields = new List<FieldOption>();
    }

    /** What one run returns. */
    public class RunResult {
        @AuraEnabled
        public List<QueryCompiler.Column> columns;
        @AuraEnabled
        public List<Map<String, Object>> rows;
        @AuraEnabled
        public String soql;
        /** True when the grid holds as many rows as it may, so there may be more. */
        @AuraEnabled
        public Boolean limitReached;
    }

    /** The query as the administrator reads it, or why it cannot be built yet. */
    public class Preview {
        @AuraEnabled
        public String soql;
        @AuraEnabled
        public String error;
    }

    @AuraEnabled(cacheable=true)
    public static Context getContext() {
        Context context = new Context();
        context.canUse = hasPermission();
        context.exportRowLimit = DataManagementSettings.exportRowLimit();
        return context;
    }

    /**
     * Every kind of record the person may read and query, by label. Settings, metadata, events,
     * sharing, history and feed objects are left out: none is a record anybody finds.
     */
    @AuraEnabled(cacheable=true)
    public static List<ObjectOption> getObjects() {
        try {
            enforcePermission();
            List<ObjectOption> result = new List<ObjectOption>();
            for (Schema.SObjectType type : Schema.getGlobalDescribe().values()) {
                Schema.DescribeSObjectResult described = type.getDescribe(
                    SObjectDescribeOptions.DEFERRED
                );
                if (!isListed(described)) {
                    continue;
                }
                ObjectOption option = new ObjectOption();
                option.name = described.getName();
                option.label = described.getLabelPlural();
                result.add(option);
            }
            result.sort(new ByLabel());
            return result;
        } catch (Exception e) {
            throw auraError(e, 'FindController.getObjects');
        }
    }

    /** One object's fields the person may read, for the column, filter and sort pickers. */
    @AuraEnabled(cacheable=true)
    public static ObjectDescription describeObject(String objectName) {
        try {
            enforcePermission();
            Schema.SObjectType type = QueryCompiler.resolveObject(objectName);
            Schema.DescribeSObjectResult described = type.getDescribe(
                SObjectDescribeOptions.DEFERRED
            );
            ObjectDescription result = new ObjectDescription();
            result.name = described.getName();
            result.label = described.getLabel();
            result.pluralLabel = described.getLabelPlural();
            for (Schema.SObjectField token : QueryCompiler.fieldsOf(type).values()) {
                Schema.DescribeFieldResult field = token.getDescribe();
                if (field.isAccessible()) {
                    result.fields.add(toOption(field));
                }
            }
            result.fields.sort(new FieldByLabel());
            return result;
        } catch (Exception e) {
            throw auraError(e, 'FindController.describeObject');
        }
    }

    /** One path's label and type, so a saved query opens showing labels, not API names. */
    public class PathDescription {
        @AuraEnabled
        public String path;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String type;
        @AuraEnabled
        public List<Map<String, String>> picklistValues;
    }

    /**
     * Labels and types for the paths a saved query names. A path the person may not read is left
     * out, and the page shows its path until a run explains why it cannot be used.
     */
    @AuraEnabled
    public static List<PathDescription> describePaths(String objectName, List<String> paths) {
        try {
            enforcePermission();
            Schema.SObjectType type = QueryCompiler.resolveObject(objectName);
            List<PathDescription> result = new List<PathDescription>();
            Integer count = 0;
            for (String path : paths == null ? new List<String>() : paths) {
                count++;
                if (count > QueryDocument.MAX_FIELDS + QueryDocument.MAX_CONDITIONS + 3) {
                    break;
                }
                try {
                    QueryCompiler.ResolvedField field = QueryCompiler.resolvePath(type, path);
                    PathDescription description = new PathDescription();
                    description.path = field.path;
                    description.label = field.label;
                    FieldOption option = toOption(field.describe);
                    description.type = option.type;
                    description.picklistValues = option.picklistValues;
                    result.add(description);
                } catch (QueryCompiler.QueryCompilerException unreadable) {
                    continue;
                }
            }
            return result;
        } catch (Exception e) {
            throw auraError(e, 'FindController.describePaths');
        }
    }

    /**
     * The query a document compiles to, for the read-only box, or the sentence that says why it
     * does not compile yet. Never throws for a document still being built.
     */
    @AuraEnabled
    public static Preview preview(String documentJson) {
        Preview result = new Preview();
        try {
            enforcePermission();
            result.soql = QueryCompiler.compile(QueryDocument.parse(documentJson))
                .display(QuerySelector.GRID_MAX_ROWS);
        } catch (Exception e) {
            if (!isAnswer(e)) {
                ErrorLogger.log(e, 'FindController.preview');
            }
            result.error = e.getMessage();
        }
        return result;
    }

    /** Runs a document and returns at most the grid's rows. */
    @AuraEnabled
    public static RunResult run(String documentJson) {
        try {
            enforcePermission();
            QueryCompiler.Compiled compiled = QueryCompiler.compile(
                QueryDocument.parse(documentJson)
            );
            RunResult result = new RunResult();
            result.columns = compiled.columns();
            result.rows = QuerySelector.rows(compiled);
            result.soql = compiled.display(QuerySelector.GRID_MAX_ROWS);
            Integer ceiling = compiled.rowLimit == null
                ? QuerySelector.GRID_MAX_ROWS
                : Math.min(compiled.rowLimit, QuerySelector.GRID_MAX_ROWS);
            result.limitReached = result.rows.size() >= ceiling;
            return result;
        } catch (Exception e) {
            throw auraError(e, 'FindController.run');
        }
    }

    /**
     * One page of an export. The browser asks for the next page after the last identifier it
     * was given, and says how many rows it already has, until the page says it is done.
     */
    @AuraEnabled
    public static QuerySelector.ExportPage exportPage(
        String documentJson,
        String afterId,
        Integer alreadyExported
    ) {
        try {
            enforcePermission();
            QueryCompiler.Compiled compiled = QueryCompiler.compile(
                QueryDocument.parse(documentJson)
            );
            Id cursor = String.isBlank(afterId) ? null : Id.valueOf(afterId);
            if (cursor != null && cursor.getSObjectType() != compiled.objectType) {
                throw new DataManagementException(Label.Core_Find_ErrorInvalidDocument);
            }
            return QuerySelector.exportPage(compiled, cursor, alreadyExported);
        } catch (Exception e) {
            throw auraError(e, 'FindController.exportPage');
        }
    }

    @AuraEnabled
    public static List<SavedQueryService.SavedQueryView> getSavedQueries() {
        try {
            enforcePermission();
            return SavedQueryService.listAll();
        } catch (Exception e) {
            throw auraError(e, 'FindController.getSavedQueries');
        }
    }

    @AuraEnabled
    public static SavedQueryService.SavedQueryView openQuery(String queryId) {
        try {
            enforcePermission();
            return SavedQueryService.open(toId(queryId));
        } catch (Exception e) {
            throw auraError(e, 'FindController.openQuery');
        }
    }

    @AuraEnabled
    public static SavedQueryService.SavedQueryView saveQuery(
        String queryId,
        String name,
        Boolean isShared,
        String documentJson
    ) {
        try {
            enforcePermission();
            return SavedQueryService.save(
                String.isBlank(queryId) ? null : toId(queryId),
                name,
                isShared,
                documentJson
            );
        } catch (Exception e) {
            throw auraError(e, 'FindController.saveQuery');
        }
    }

    @AuraEnabled
    public static void deleteQuery(String queryId) {
        try {
            enforcePermission();
            SavedQueryService.remove(toId(queryId));
        } catch (Exception e) {
            throw auraError(e, 'FindController.deleteQuery');
        }
    }

    // -------------------------------------------------------------------------------------

    @TestVisible
    private static Boolean isListed(Schema.DescribeSObjectResult described) {
        if (
            !described.isAccessible() ||
            !described.isQueryable() ||
            described.isCustomSetting() ||
            described.isDeprecatedAndHidden()
        ) {
            return false;
        }
        String name = described.getName().toLowerCase();
        for (String suffix : HIDDEN_SUFFIXES) {
            if (name.endsWith(suffix)) {
                return false;
            }
        }
        return true;
    }

    private static FieldOption toOption(Schema.DescribeFieldResult field) {
        FieldOption option = new FieldOption();
        option.name = field.getName();
        option.label = field.getLabel();
        option.type = field.getType().name().toLowerCase();
        option.filterable = field.isFilterable();
        option.sortable = field.isSortable();
        option.showable = QueryCompiler.isShowable(field);
        List<Schema.SObjectType> targets = field.getReferenceTo();
        if (
            field.getType() == Schema.DisplayType.REFERENCE &&
            String.isNotBlank(field.getRelationshipName()) &&
            targets.size() == 1
        ) {
            Schema.DescribeSObjectResult target = targets[0]
                .getDescribe(SObjectDescribeOptions.DEFERRED);
            if (target.isAccessible()) {
                option.relationshipName = field.getRelationshipName();
                option.relationshipLabel = QueryCompiler.relationshipLabel(field);
                option.referenceTo = target.getName();
            }
        }
        if (
            field.getType() == Schema.DisplayType.PICKLIST ||
            field.getType() == Schema.DisplayType.MULTIPICKLIST
        ) {
            option.picklistValues = new List<Map<String, String>>();
            for (Schema.PicklistEntry entry : field.getPicklistValues()) {
                if (entry.isActive()) {
                    option.picklistValues.add(
                        new Map<String, String>{
                            'label' => entry.getLabel(),
                            'value' => entry.getValue()
                        }
                    );
                }
            }
        }
        return option;
    }

    private class ByLabel implements Comparator<ObjectOption> {
        public Integer compare(ObjectOption left, ObjectOption right) {
            return left.label.toLowerCase().compareTo(right.label.toLowerCase());
        }
    }

    private class FieldByLabel implements Comparator<FieldOption> {
        public Integer compare(FieldOption left, FieldOption right) {
            return left.label.toLowerCase().compareTo(right.label.toLowerCase());
        }
    }

    private static Id toId(String value) {
        try {
            return Id.valueOf(value);
        } catch (Exception notAnId) {
            throw new DataManagementException(Label.Core_Find_ErrorSavedGone);
        }
    }

    private static void enforcePermission() {
        if (!hasPermission()) {
            throw new DataManagementException(Label.Core_Find_ErrorNoPermission);
        }
    }

    @TestVisible
    private static Boolean hasPermission() {
        if (permissionOverride != null) {
            return permissionOverride;
        }
        return FeatureManagement.checkPermission(PERMISSION);
    }

    /** True for a refusal written for the person, which is shown and not logged. */
    @TestVisible
    private static Boolean isAnswer(Exception e) {
        return e instanceof DataManagementException ||
            e instanceof QueryCompiler.QueryCompilerException ||
            e instanceof QueryDocument.QueryDocumentException;
    }

    private static AuraHandledException auraError(Exception e, String context) {
        if (!isAnswer(e)) {
            ErrorLogger.log(e, context);
        }
        AuraHandledException wrapped = new AuraHandledException(e.getMessage());
        wrapped.setMessage(e.getMessage());
        return wrapped;
    }
}

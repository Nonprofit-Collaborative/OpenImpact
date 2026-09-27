/**
 * The entry points the Bulk Update page calls (C-35, plan Section 4.9, ADR-0047 amended).
 *
 * Every method checks `Bulk_Update_Records` first. The permission opens the tool and grants no
 * record access: the query runs, and every record is saved, in the person's own mode through
 * `BulkUpdateService` and `BulkUpdateBatch`. The browser sends a query document and up to five
 * changes, never query text or a field name that is not checked against describe.
 *
 * The undo is an import's (`ImportUndoService`); here it is offered only for bulk updates, so
 * this permission never reaches the undo of a file import.
 */
public with sharing class BulkUpdateController {
    /** The custom permission that opens bulk update. */
    @NamespaceAccessible
    public static final String PERMISSION = 'Bulk_Update_Records';
    /** The bulk update tab, without a namespace; qualify before navigating to it. */
    @NamespaceAccessible
    public static final String TAB = 'Bulk_Update';

    /** Set only by tests, so the permitted path can be asserted without assigning a permission. */
    @TestVisible
    private static Boolean permissionOverride;

    /** What the page needs before anything is chosen. */
    public class Context {
        @AuraEnabled
        public Boolean canUse = false;
        /** Whether the person may also build queries in Find. */
        @AuraEnabled
        public Boolean canFind = false;
        @AuraEnabled
        public Integer maximum;
        @AuraEnabled
        public Integer maxChanges = BulkUpdateService.MAX_CHANGES;
    }

    /** One field a bulk update may write, and the fields that may be copied into it. */
    public class Target {
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String type;
        @AuraEnabled
        public Boolean nillable;
        @AuraEnabled
        public List<Map<String, String>> picklistValues;
        @AuraEnabled
        public List<Map<String, String>> sources = new List<Map<String, String>>();
    }

    /** The query a page was handed, as the person may use it. */
    public class QueryView {
        @AuraEnabled
        public String objectName;
        @AuraEnabled
        public String objectLabel;
        @AuraEnabled
        public String soql;
        @AuraEnabled
        public List<Target> targets = new List<Target>();
    }

    /** A job just started. */
    public class Started {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String name;
    }

    @AuraEnabled(cacheable=true)
    public static Context getContext() {
        Context context = new Context();
        context.canUse = hasPermission();
        context.canFind = FeatureManagement.checkPermission(FindController.PERMISSION);
        context.maximum = DataManagementSettings.bulkUpdateMaxRecords();
        return context;
    }

    @AuraEnabled
    public static List<SavedQueryService.SavedQueryView> getSavedQueries() {
        try {
            enforcePermission();
            return SavedQueryService.listAll();
        } catch (Exception e) {
            throw auraError(e, 'BulkUpdateController.getSavedQueries');
        }
    }

    @AuraEnabled
    public static SavedQueryService.SavedQueryView openQuery(String queryId) {
        try {
            enforcePermission();
            return SavedQueryService.open(Id.valueOf(queryId));
        } catch (Exception e) {
            throw auraError(e, 'BulkUpdateController.openQuery');
        }
    }

    /**
     * The object a query document asks about, its read-only query, and every field of it the
     * person may bulk update, each with the fields that may be copied into it.
     */
    @AuraEnabled
    public static QueryView describeQuery(String documentJson) {
        try {
            enforcePermission();
            QueryCompiler.Compiled compiled = QueryCompiler.compile(
                QueryDocument.parse(documentJson)
            );
            Schema.SObjectType type = compiled.objectType;
            Schema.DescribeSObjectResult described = type.getDescribe(
                SObjectDescribeOptions.DEFERRED
            );
            QueryView view = new QueryView();
            view.objectName = compiled.objectName;
            view.objectLabel = described.getLabelPlural();
            view.soql = compiled.display(DataManagementSettings.bulkUpdateMaxRecords());
            if (DataProtectedFields.objectReason(type) != null) {
                return view;
            }
            List<Schema.DescribeFieldResult> readable = new List<Schema.DescribeFieldResult>();
            for (Schema.SObjectField token : QueryCompiler.fieldsOf(type).values()) {
                Schema.DescribeFieldResult field = token.getDescribe();
                if (field.isAccessible()) {
                    readable.add(field);
                }
            }
            for (Schema.DescribeFieldResult field : readable) {
                if (
                    DataProtectedFields.fieldReason(type, field) != null ||
                    !BulkUpdateService.isWritableType(field)
                ) {
                    continue;
                }
                view.targets.add(toTarget(field, readable));
            }
            view.targets.sort(new ByLabel());
            return view;
        } catch (Exception e) {
            throw auraError(e, 'BulkUpdateController.describeQuery');
        }
    }

    @AuraEnabled
    public static BulkUpdateService.Preview preview(String documentJson, String changesJson) {
        try {
            enforcePermission();
            return BulkUpdateService.preview(documentJson, changesJson);
        } catch (Exception e) {
            throw auraError(e, 'BulkUpdateController.preview');
        }
    }

    @AuraEnabled
    public static Started start(String documentJson, String changesJson, Integer confirmedCount) {
        try {
            enforcePermission();
            Import_Batch__c job = BulkUpdateService.start(
                documentJson,
                changesJson,
                confirmedCount
            );
            Started result = new Started();
            result.id = job.Id;
            result.name = job.Name;
            return result;
        } catch (Exception e) {
            throw auraError(e, 'BulkUpdateController.start');
        }
    }

    @AuraEnabled
    public static List<BulkUpdateService.JobView> getRecentJobs() {
        try {
            enforcePermission();
            return BulkUpdateService.recentJobs();
        } catch (Exception e) {
            throw auraError(e, 'BulkUpdateController.getRecentJobs');
        }
    }

    /** What undoing one bulk update would put back. */
    @AuraEnabled
    public static ImportUndoService.Preview previewUndo(String jobId) {
        try {
            enforcePermission();
            return ImportUndoService.preview(bulkUpdateId(jobId));
        } catch (Exception e) {
            throw auraError(e, 'BulkUpdateController.previewUndo');
        }
    }

    /** Starts the undo of one bulk update, with the total its preview showed. */
    @AuraEnabled
    public static void startUndo(String jobId, Integer confirmedTotal) {
        try {
            enforcePermission();
            ImportUndoService.start(bulkUpdateId(jobId), confirmedTotal);
        } catch (Exception e) {
            throw auraError(e, 'BulkUpdateController.startUndo');
        }
    }

    // -------------------------------------------------------------------------------------

    private static Target toTarget(
        Schema.DescribeFieldResult field,
        List<Schema.DescribeFieldResult> readable
    ) {
        Target target = new Target();
        target.name = field.getName();
        target.label = field.getLabel();
        target.type = field.getType().name().toLowerCase();
        target.nillable = field.isNillable();
        if (
            field.getType() == Schema.DisplayType.PICKLIST ||
            field.getType() == Schema.DisplayType.MULTIPICKLIST
        ) {
            target.picklistValues = new List<Map<String, String>>();
            for (Schema.PicklistEntry entry : field.getPicklistValues()) {
                if (entry.isActive()) {
                    target.picklistValues.add(
                        new Map<String, String>{
                            'label' => entry.getLabel(),
                            'value' => entry.getValue()
                        }
                    );
                }
            }
        }
        for (Schema.DescribeFieldResult source : readable) {
            if (
                source.getName() != field.getName() && BulkUpdateService.compatible(field, source)
            ) {
                target.sources.add(
                    new Map<String, String>{
                        'label' => source.getLabel(),
                        'value' => source.getName()
                    }
                );
            }
        }
        return target;
    }

    /** A job identifier, refused unless it names a bulk update the person can see. */
    private static Id bulkUpdateId(String jobId) {
        Id parsed;
        try {
            parsed = Id.valueOf(jobId);
        } catch (Exception notAnId) {
            throw new DataManagementException(Label.Core_BulkUpdate_ErrorNotABulkUpdate);
        }
        if (!BulkUpdateService.isBulkUpdate(parsed)) {
            throw new DataManagementException(Label.Core_BulkUpdate_ErrorNotABulkUpdate);
        }
        return parsed;
    }

    private class ByLabel implements Comparator<Target> {
        public Integer compare(Target left, Target right) {
            return left.label.toLowerCase().compareTo(right.label.toLowerCase());
        }
    }

    private static void enforcePermission() {
        if (!hasPermission()) {
            throw new DataManagementException(Label.Core_BulkUpdate_ErrorNoPermission);
        }
    }

    /** Whether the running user may use bulk update. */
    @NamespaceAccessible
    public static Boolean hasPermission() {
        if (permissionOverride != null) {
            return permissionOverride;
        }
        return FeatureManagement.checkPermission(PERMISSION);
    }

    private static Boolean isAnswer(Exception e) {
        return e instanceof DataManagementException ||
            e instanceof ImportException ||
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

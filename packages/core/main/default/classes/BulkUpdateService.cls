/**
 * Bulk update (C-35, canonical model R-IB14 and R-IB15, ADR-0047 amended): up to five changes
 * to every record a Find query returns, counted and confirmed before anything is saved, run by
 * `BulkUpdateBatch` as the person who started it, journaled, and undone as an import is.
 *
 * Everything the person sends is checked here, as them: the query through `QueryCompiler`, and
 * each change against the object's own describe and `DataProtectedFields`. Nothing they send is
 * written into a query or used as a field name without being found in describe first.
 */
@NamespaceAccessible
public with sharing class BulkUpdateService {
    @NamespaceAccessible
    public static final String OPERATION_IMPORT = 'Import';
    @NamespaceAccessible
    public static final String OPERATION_UPDATE = 'Update';
    @NamespaceAccessible
    public static final String ACTION_SET = 'set';
    @NamespaceAccessible
    public static final String ACTION_CLEAR = 'clear';
    @NamespaceAccessible
    public static final String ACTION_COPY = 'copy';
    @NamespaceAccessible
    public static final Integer MAX_CHANGES = 5;
    /** How many records the preview shows before and after. */
    @NamespaceAccessible
    public static final Integer SAMPLE_SIZE = 5;
    /** The widest chunk a bulk update runs in, so one journal page holds one chunk (R-IJ1). */
    @NamespaceAccessible
    public static final Integer MAX_CHUNK = 200;
    private static final Integer DEFINITION_VERSION = 1;
    private static final Integer RECENT_JOBS = 10;

    private static final Set<Schema.DisplayType> TEXT_TARGETS = new Set<Schema.DisplayType>{
        Schema.DisplayType.STRING,
        Schema.DisplayType.TEXTAREA
    };
    private static final Set<Schema.DisplayType> TEXT_SOURCES = new Set<Schema.DisplayType>{
        Schema.DisplayType.STRING,
        Schema.DisplayType.TEXTAREA,
        Schema.DisplayType.EMAIL,
        Schema.DisplayType.PHONE,
        Schema.DisplayType.URL,
        Schema.DisplayType.PICKLIST,
        Schema.DisplayType.COMBOBOX
    };
    private static final Set<Schema.DisplayType> NUMBERS = new Set<Schema.DisplayType>{
        Schema.DisplayType.INTEGER,
        Schema.DisplayType.LONG,
        Schema.DisplayType.DOUBLE,
        Schema.DisplayType.CURRENCY,
        Schema.DisplayType.PERCENT
    };
    /** Types a bulk update can write a value of; any other is refused. */
    private static final Set<Schema.DisplayType> WRITABLE = new Set<Schema.DisplayType>{
        Schema.DisplayType.STRING,
        Schema.DisplayType.TEXTAREA,
        Schema.DisplayType.EMAIL,
        Schema.DisplayType.PHONE,
        Schema.DisplayType.URL,
        Schema.DisplayType.PICKLIST,
        Schema.DisplayType.MULTIPICKLIST,
        Schema.DisplayType.COMBOBOX,
        Schema.DisplayType.BOOLEAN,
        Schema.DisplayType.INTEGER,
        Schema.DisplayType.LONG,
        Schema.DisplayType.DOUBLE,
        Schema.DisplayType.CURRENCY,
        Schema.DisplayType.PERCENT,
        Schema.DisplayType.DATE,
        Schema.DisplayType.DATETIME,
        Schema.DisplayType.REFERENCE
    };

    /** One change, as checked: the field it writes and the value or field it takes. */
    @NamespaceAccessible
    public class Change {
        @NamespaceAccessible
        public String action;
        @NamespaceAccessible
        public Schema.SObjectField target;
        @NamespaceAccessible
        public Schema.DescribeFieldResult targetDescribe;
        @NamespaceAccessible
        public Schema.SObjectField source;
        /** The value to set, typed for the target; null for clear and copy. */
        @NamespaceAccessible
        public Object value;
        /** What was sent, kept for the job's definition. */
        @NamespaceAccessible
        public Object rawValue;

        /** The value this change gives one record. */
        @NamespaceAccessible
        public Object newValueFor(SObject record) {
            if (action == ACTION_COPY) {
                return record.get(source);
            }
            return action == ACTION_CLEAR ? null : value;
        }

        @NamespaceAccessible
        public Map<String, Object> toMap() {
            Map<String, Object> result = new Map<String, Object>{
                'field' => targetDescribe.getName(),
                'action' => action
            };
            if (action == ACTION_SET) {
                result.put('value', rawValue);
            }
            if (action == ACTION_COPY) {
                result.put('source', source.getDescribe().getName());
            }
            return result;
        }
    }

    /** A checked bulk update: the compiled query and the changes. */
    @NamespaceAccessible
    public class Plan {
        @NamespaceAccessible
        public QueryDocument document;
        @NamespaceAccessible
        public QueryCompiler.Compiled compiled;
        @NamespaceAccessible
        public List<Change> changes = new List<Change>();

        /** The fields the job reads: every target, every copied source, and the name. */
        @NamespaceAccessible
        public Set<String> readFields() {
            Set<String> names = new Set<String>();
            for (Change change : changes) {
                names.add(change.targetDescribe.getName());
                if (change.source != null) {
                    names.add(change.source.getDescribe().getName());
                }
            }
            return names;
        }

        /** The object's name field, when the person may read it, for the sample. */
        @NamespaceAccessible
        public String nameField() {
            for (Schema.SObjectField token : QueryCompiler.fieldsOf(compiled.objectType).values()) {
                Schema.DescribeFieldResult field = token.getDescribe();
                if (field.isNameField() && field.isAccessible()) {
                    return field.getName();
                }
            }
            return null;
        }

        /** The definition a job keeps (R-IB14): the document, the changes, the count. */
        @NamespaceAccessible
        public String definition(Integer confirmedCount) {
            List<Object> rawChanges = new List<Object>();
            for (Change change : changes) {
                rawChanges.add(change.toMap());
            }
            return JSON.serialize(
                new Map<String, Object>{
                    'version' => DEFINITION_VERSION,
                    'query' => document.toMap(),
                    'changes' => rawChanges,
                    'confirmedCount' => confirmedCount
                }
            );
        }
    }

    /** One field before and after, as the preview shows it. */
    public class FieldChange {
        @AuraEnabled
        public String field;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public Object before;
        @AuraEnabled
        public Object after;
    }

    /** One record of the preview's sample. */
    public class SampleRecord {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public List<FieldChange> changes = new List<FieldChange>();
    }

    /** What a bulk update would do. */
    public class Preview {
        /** How many records match now: the number the person confirms. */
        @AuraEnabled
        public Integer count;
        @AuraEnabled
        public Integer maximum;
        @AuraEnabled
        public String objectLabel;
        @AuraEnabled
        public String soql;
        @AuraEnabled
        public List<SampleRecord> sample = new List<SampleRecord>();
    }

    /** A recent bulk update, as the page lists it. */
    public class JobView {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String objectName;
        @AuraEnabled
        public Integer matched;
        @AuraEnabled
        public Integer updated;
        @AuraEnabled
        public Integer unchanged;
        @AuraEnabled
        public Integer failed;
        @AuraEnabled
        public String runLog;
        @AuraEnabled
        public Datetime startedAt;
        @AuraEnabled
        public Datetime undoDeadline;
        @AuraEnabled
        public Boolean canUndo;
    }

    // -------------------------------------------------------------------------------------
    // Checking
    // -------------------------------------------------------------------------------------

    /** Checks a query document and its changes as the running user. */
    @NamespaceAccessible
    public static Plan plan(String documentJson, String changesJson) {
        List<Object> rawChanges;
        try {
            rawChanges = String.isBlank(changesJson)
                ? new List<Object>()
                : (List<Object>) JSON.deserializeUntyped(changesJson);
        } catch (Exception unreadable) {
            throw new DataManagementException(Label.Core_BulkUpdate_ErrorNoChanges);
        }
        return plan(QueryDocument.parse(documentJson), rawChanges);
    }

    /** Checks a job's stored definition again, as the person running the job (R-IB14). */
    @NamespaceAccessible
    public static Plan planFromDefinition(String definitionJson) {
        Map<String, Object> definition = (Map<String, Object>) JSON.deserializeUntyped(
            definitionJson
        );
        return plan(
            QueryDocument.fromMap((Map<String, Object>) definition.get('query')),
            (List<Object>) definition.get('changes')
        );
    }

    /** The confirmed count a job's definition holds. */
    @NamespaceAccessible
    public static Integer confirmedCountOf(String definitionJson) {
        Map<String, Object> definition = (Map<String, Object>) JSON.deserializeUntyped(
            definitionJson
        );
        return Integer.valueOf(definition.get('confirmedCount'));
    }

    private static Plan plan(QueryDocument document, List<Object> rawChanges) {
        Plan result = new Plan();
        result.document = document;
        result.compiled = QueryCompiler.compile(document);
        Schema.SObjectType type = result.compiled.objectType;
        String objectRefusal = DataProtectedFields.objectReason(type);
        if (objectRefusal != null) {
            throw new DataManagementException(
                String.format(
                    Label.Core_BulkUpdate_ErrorProtectedObject,
                    new List<String>{
                        type.getDescribe(SObjectDescribeOptions.DEFERRED).getLabelPlural(),
                        objectRefusal
                    }
                )
            );
        }
        if (rawChanges == null || rawChanges.isEmpty()) {
            throw new DataManagementException(Label.Core_BulkUpdate_ErrorNoChanges);
        }
        if (rawChanges.size() > MAX_CHANGES) {
            throw new DataManagementException(Label.Core_BulkUpdate_ErrorTooManyChanges);
        }
        Set<String> targets = new Set<String>();
        for (Object entry : rawChanges) {
            if (!(entry instanceof Map<String, Object>)) {
                throw new DataManagementException(Label.Core_BulkUpdate_ErrorNoChanges);
            }
            Change change = change(type, (Map<String, Object>) entry);
            String key = change.targetDescribe.getName().toLowerCase();
            if (targets.contains(key)) {
                throw new DataManagementException(
                    String.format(
                        Label.Core_BulkUpdate_ErrorDuplicateField,
                        new List<String>{ change.targetDescribe.getLabel() }
                    )
                );
            }
            targets.add(key);
            result.changes.add(change);
        }
        return result;
    }

    private static Change change(Schema.SObjectType type, Map<String, Object> raw) {
        Change change = new Change();
        change.action = raw.get('action') == null
            ? ''
            : String.valueOf(raw.get('action')).trim().toLowerCase();
        change.target = ownField(type, raw.get('field'));
        change.targetDescribe = change.target.getDescribe();
        String fieldLabel = change.targetDescribe.getLabel();
        String refusal = DataProtectedFields.fieldReason(type, change.targetDescribe);
        if (refusal == null && !WRITABLE.contains(change.targetDescribe.getType())) {
            refusal = Label.Core_BulkUpdate_ReasonType;
        }
        if (refusal != null) {
            throw new DataManagementException(
                String.format(
                    Label.Core_BulkUpdate_ErrorProtectedField,
                    new List<String>{ fieldLabel, refusal }
                )
            );
        }
        if (change.action == ACTION_CLEAR) {
            if (!change.targetDescribe.isNillable()) {
                throw new DataManagementException(
                    String.format(
                        Label.Core_BulkUpdate_ErrorRequired,
                        new List<String>{ fieldLabel }
                    )
                );
            }
            return change;
        }
        if (change.action == ACTION_COPY) {
            change.source = ownField(type, raw.get('source'));
            Schema.DescribeFieldResult source = change.source.getDescribe();
            if (
                change.source == change.target ||
                !source.isAccessible() ||
                !compatible(change.targetDescribe, source)
            ) {
                throw new DataManagementException(
                    String.format(
                        Label.Core_BulkUpdate_ErrorIncompatibleCopy,
                        new List<String>{ source.getLabel(), fieldLabel }
                    )
                );
            }
            return change;
        }
        if (change.action == ACTION_SET) {
            change.rawValue = raw.get('value');
            change.value = typed(change.targetDescribe, raw.get('value'));
            return change;
        }
        throw new DataManagementException(Label.Core_BulkUpdate_ErrorNoChanges);
    }

    /**
     * A field of the object itself, found in describe. A path to another record is refused: a
     * bulk update writes the records its query returns and nothing else.
     */
    private static Schema.SObjectField ownField(Schema.SObjectType type, Object rawName) {
        String name = rawName == null ? '' : String.valueOf(rawName).trim();
        Schema.SObjectField token = String.isBlank(name) || name.contains('.')
            ? null
            : QueryCompiler.fieldsOf(type).get(name.toLowerCase());
        if (token == null || !token.getDescribe().isAccessible()) {
            throw new DataManagementException(
                String.format(
                    Label.Core_Find_ErrorUnknownField,
                    new List<String>{
                        name.abbreviate(80),
                        type.getDescribe(SObjectDescribeOptions.DEFERRED).getLabel()
                    }
                )
            );
        }
        return token;
    }

    /** Whether a bulk update can write a value of this field's type at all. */
    @NamespaceAccessible
    public static Boolean isWritableType(Schema.DescribeFieldResult field) {
        return WRITABLE.contains(field.getType());
    }

    /** Whether `source` may be copied into `target` (C-35 decision 5). */
    @NamespaceAccessible
    public static Boolean compatible(
        Schema.DescribeFieldResult target,
        Schema.DescribeFieldResult source
    ) {
        Schema.DisplayType to = target.getType();
        Schema.DisplayType given = source.getType();
        if (!WRITABLE.contains(to)) {
            return false;
        }
        if (to == Schema.DisplayType.REFERENCE) {
            if (given != Schema.DisplayType.REFERENCE && given != Schema.DisplayType.ID) {
                return false;
            }
            Set<Schema.SObjectType> reachable = new Set<Schema.SObjectType>(
                target.getReferenceTo()
            );
            List<Schema.SObjectType> offered = given == Schema.DisplayType.ID
                ? new List<Schema.SObjectType>()
                : source.getReferenceTo();
            for (Schema.SObjectType type : offered) {
                if (reachable.contains(type)) {
                    return true;
                }
            }
            return false;
        }
        if (TEXT_TARGETS.contains(to)) {
            return TEXT_SOURCES.contains(given);
        }
        if (NUMBERS.contains(to)) {
            return NUMBERS.contains(given);
        }
        return to == given;
    }

    /** A value to set, as the target's own type, or refused with the field named. */
    @TestVisible
    private static Object typed(Schema.DescribeFieldResult field, Object raw) {
        DataManagementException refused = new DataManagementException(
            String.format(Label.Core_BulkUpdate_ErrorBadValue, new List<String>{ field.getLabel() })
        );
        if (raw == null || String.isBlank(String.valueOf(raw))) {
            throw refused;
        }
        String text = String.valueOf(raw);
        Schema.DisplayType kind = field.getType();
        try {
            switch on kind {
                when BOOLEAN {
                    if (raw instanceof Boolean) {
                        return raw;
                    }
                    if (text.equalsIgnoreCase('true') || text.equalsIgnoreCase('false')) {
                        return Boolean.valueOf(text);
                    }
                    throw refused;
                }
                when INTEGER {
                    return wholeNumber(text, refused).intValue();
                }
                when LONG {
                    return wholeNumber(text, refused).longValue();
                }
                when DOUBLE, CURRENCY, PERCENT {
                    return Decimal.valueOf(text.trim());
                }
                when DATE {
                    Date parsed = Date.valueOf(text.trim());
                    if (String.valueOf(parsed) != text.trim()) {
                        throw refused;
                    }
                    return parsed;
                }
                when DATETIME {
                    return (Datetime) JSON.deserialize('"' + text.trim() + '"', Datetime.class);
                }
                when REFERENCE {
                    Id value = Id.valueOf(text.trim());
                    if (!field.getReferenceTo().contains(value.getSObjectType())) {
                        throw refused;
                    }
                    return value;
                }
                when PICKLIST, MULTIPICKLIST {
                    checkPicklist(field, text, refused);
                    return text;
                }
                when else {
                    if (field.getLength() > 0 && text.length() > field.getLength()) {
                        throw refused;
                    }
                    return text;
                }
            }
        } catch (DataManagementException known) {
            throw known;
        } catch (Exception unreadable) {
            throw refused;
        }
    }

    private static Decimal wholeNumber(String text, DataManagementException refused) {
        Decimal value = Decimal.valueOf(text.trim());
        if (value != value.setScale(0, System.RoundingMode.DOWN)) {
            throw refused;
        }
        return value.setScale(0, System.RoundingMode.DOWN);
    }

    /** A restricted picklist takes only its active values; an open one takes any text. */
    private static void checkPicklist(
        Schema.DescribeFieldResult field,
        String text,
        DataManagementException refused
    ) {
        if (!field.isRestrictedPicklist()) {
            return;
        }
        Set<String> active = new Set<String>();
        for (Schema.PicklistEntry entry : field.getPicklistValues()) {
            if (entry.isActive()) {
                active.add(entry.getValue());
            }
        }
        List<String> chosen = field.getType() == Schema.DisplayType.MULTIPICKLIST
            ? text.split(';')
            : new List<String>{ text };
        for (String value : chosen) {
            if (!active.contains(value)) {
                throw refused;
            }
        }
    }

    // -------------------------------------------------------------------------------------
    // Preview and start
    // -------------------------------------------------------------------------------------

    /**
     * Counts the records the query matches now and shows the first few before and after. The
     * count is the number the person confirms; nothing is saved.
     */
    @NamespaceAccessible
    public static Preview preview(String documentJson, String changesJson) {
        Plan plan = plan(documentJson, changesJson);
        Integer maximum = DataManagementSettings.bulkUpdateMaxRecords();
        Preview result = new Preview();
        result.count = countWithin(plan, maximum);
        result.maximum = maximum;
        result.objectLabel = plan.compiled.objectType.getDescribe(SObjectDescribeOptions.DEFERRED)
            .getLabelPlural();
        result.soql = plan.compiled.display(maximum);
        Set<String> fields = plan.readFields();
        String nameField = plan.nameField();
        if (nameField != null) {
            fields.add(nameField);
        }
        for (SObject record : QuerySelector.records(plan.compiled.forUpdate(fields, SAMPLE_SIZE))) {
            SampleRecord sample = new SampleRecord();
            sample.id = record.Id;
            sample.name = nameField == null
                ? String.valueOf(record.Id)
                : String.valueOf(record.get(nameField));
            for (Change change : plan.changes) {
                FieldChange shown = new FieldChange();
                shown.field = change.targetDescribe.getName();
                shown.label = change.targetDescribe.getLabel();
                shown.before = record.get(change.target);
                shown.after = change.newValueFor(record);
                sample.changes.add(shown);
            }
            result.sample.add(sample);
        }
        return result;
    }

    /**
     * Starts a bulk update of at most `confirmedCount` records, after counting again: it is
     * refused when more records match now than were confirmed, or than the maximum allows
     * (R-IB14). The job record and its log are the package's own bookkeeping, written in
     * system mode (ADR-0021); every record the job changes is saved in the person's own mode.
     */
    @NamespaceAccessible
    public static Import_Batch__c start(
        String documentJson,
        String changesJson,
        Integer confirmedCount
    ) {
        Plan plan = plan(documentJson, changesJson);
        if (confirmedCount == null || confirmedCount < 1) {
            throw new DataManagementException(Label.Core_BulkUpdate_ErrorConfirm);
        }
        Integer maximum = DataManagementSettings.bulkUpdateMaxRecords();
        if (confirmedCount > maximum) {
            throw new DataManagementException(overMaximum(maximum));
        }
        Integer cap = Math.min(confirmedCount + 1, QuerySelector.countHeadroom());
        Integer count = QuerySelector.count(plan.compiled, cap);
        if (count > confirmedCount) {
            throw new DataManagementException(
                String.format(
                    Label.Core_BulkUpdate_ErrorMoreThanConfirmed,
                    new List<String>{ String.valueOf(confirmedCount) }
                )
            );
        }
        if (count >= cap && cap <= confirmedCount) {
            throw new DataManagementException(Label.Core_BulkUpdate_ErrorTooManyToCount);
        }
        if (count == 0) {
            throw new DataManagementException(Label.Core_BulkUpdate_ErrorNothingMatches);
        }
        Datetime now = Datetime.now();
        String objectName = plan.compiled.objectName;
        Import_Batch__c job = new Import_Batch__c(
            Operation__c = OPERATION_UPDATE,
            Operation_JSON__c = plan.definition(confirmedCount),
            Status__c = ImportBatchService.STATUS_COMMITTING,
            Is_Dry_Run__c = false,
            Row_Count__c = count,
            Rows_Created__c = 0,
            Rows_Updated__c = 0,
            Rows_Matched__c = 0,
            Rows_Rejected__c = 0,
            Chunk_Size__c = Math.min(ImportBatchService.chunkSize(), MAX_CHUNK),
            Started_At__c = now,
            Committed_By__c = UserInfo.getUserId(),
            // Stamped at commit, as an import's is, so a later change to the setting never
            // moves it (R-IB7).
            Undo_Deadline__c = now.addDays(ImportBatchService.undoWindowDays()),
            Run_Log__c = String.format(
                Label.Core_BulkUpdate_LogStarted,
                new List<String>{
                    UserInfo.getName(),
                    now.format(),
                    String.valueOf(count),
                    objectName,
                    String.valueOf(confirmedCount)
                }
            )
        );
        Database.insert(job, AccessLevel.SYSTEM_MODE);
        Id jobId = Database.executeBatch(new BulkUpdateBatch(job.Id), job.Chunk_Size__c.intValue());
        job.Job_Id__c = jobId;
        Database.update(
            new Import_Batch__c(Id = job.Id, Job_Id__c = jobId),
            AccessLevel.SYSTEM_MODE
        );
        return job;
    }

    /**
     * How many records match, refused when there are none, more than the maximum, or more than
     * one request can count (C-35 decision 2).
     */
    private static Integer countWithin(Plan plan, Integer maximum) {
        Integer cap = Math.min(maximum + 1, QuerySelector.countHeadroom());
        Integer count = QuerySelector.count(plan.compiled, cap);
        if (count > maximum) {
            throw new DataManagementException(overMaximum(maximum));
        }
        if (count >= cap) {
            throw new DataManagementException(Label.Core_BulkUpdate_ErrorTooManyToCount);
        }
        if (count == 0) {
            throw new DataManagementException(Label.Core_BulkUpdate_ErrorNothingMatches);
        }
        return count;
    }

    private static String overMaximum(Integer maximum) {
        return String.format(
            Label.Core_BulkUpdate_ErrorOverMaximum,
            new List<String>{ String.valueOf(maximum) }
        );
    }

    // -------------------------------------------------------------------------------------
    // Jobs and undo
    // -------------------------------------------------------------------------------------

    /** The most recent bulk updates, newest first, in the person's own mode. */
    @NamespaceAccessible
    public static List<JobView> recentJobs() {
        List<JobView> result = new List<JobView>();
        for (
            Import_Batch__c job : (List<Import_Batch__c>) Database.queryWithBinds(
                'SELECT Id, Name, Status__c, Is_Dry_Run__c, Operation_JSON__c, Row_Count__c, ' +
                    'Rows_Updated__c, Rows_Matched__c, Rows_Rejected__c, Run_Log__c, ' +
                    'Started_At__c, Completed_At__c, Undo_Deadline__c, Job_Id__c ' +
                    'FROM Import_Batch__c WHERE Operation__c = :operation ' +
                    'ORDER BY CreatedDate DESC LIMIT :howMany',
                new Map<String, Object>{
                    'operation' => OPERATION_UPDATE,
                    'howMany' => RECENT_JOBS
                },
                AccessLevel.USER_MODE
            )
        ) {
            result.add(toView(job));
        }
        return result;
    }

    /** Whether this data job is a bulk update, read in the person's own mode. */
    @NamespaceAccessible
    public static Boolean isBulkUpdate(Id jobId) {
        if (jobId == null) {
            return false;
        }
        List<Import_Batch__c> found = Database.queryWithBinds(
            'SELECT Id FROM Import_Batch__c WHERE Id = :jobId AND Operation__c = :operation LIMIT 1',
            new Map<String, Object>{ 'jobId' => jobId, 'operation' => OPERATION_UPDATE },
            AccessLevel.USER_MODE
        );
        return !found.isEmpty();
    }

    private static JobView toView(Import_Batch__c job) {
        JobView view = new JobView();
        view.id = job.Id;
        view.name = job.Name;
        view.status = ImportUndoService.effectiveStatus(job);
        view.matched = intOf(job.Row_Count__c);
        view.updated = intOf(job.Rows_Updated__c);
        view.unchanged = intOf(job.Rows_Matched__c);
        view.failed = intOf(job.Rows_Rejected__c);
        view.runLog = job.Run_Log__c;
        view.startedAt = job.Started_At__c;
        view.undoDeadline = job.Undo_Deadline__c;
        view.canUndo = String.isBlank(ImportUndoService.refusal(job));
        try {
            Map<String, Object> definition = (Map<String, Object>) JSON.deserializeUntyped(
                job.Operation_JSON__c
            );
            view.objectName = String.valueOf(
                ((Map<String, Object>) definition.get('query')).get('object')
            );
        } catch (Exception unreadable) {
            view.objectName = null;
        }
        return view;
    }

    private static Integer intOf(Decimal value) {
        return value == null ? 0 : value.intValue();
    }
}

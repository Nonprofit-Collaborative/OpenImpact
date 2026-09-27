/**
 * Loads rows into one object (C-33, canonical model R-IT10 to R-IT12): insert, update by record
 * Id, or upsert by an external ID field, for any object the org has, including custom ones.
 *
 * The object and its fields come from describe at run time, so Core names no object here and
 * runs on a Platform-only org (ADR-0013). Every read and write is in the running user's own
 * mode; the only system-mode writes are the staged rows and the journal, the package's own
 * bookkeeping (ADR-0021). What is never written comes from `DataProtectedFields`.
 *
 * The rules of the people model hold here too: bulk safe (a query or a save per chunk, never
 * per row), a dry run makes the same decisions as the commit, and a row that fails does not
 * take the chunk with it. What differs is that a row describes one record: a value its field
 * cannot take rejects the row rather than being skipped, and a row repeating an earlier row's
 * key is rejected wherever the file's chunks fall.
 *
 * The chunk runs through `ImportRowProcessor.process`, which hands a template with an Object
 * here, so the batch, the dry run, the control totals, the journal and undo are the ones every
 * import uses.
 */
@NamespaceAccessible
public with sharing class ImportObjectLoader {
    @NamespaceAccessible
    public static final String OPERATION_INSERT = 'Insert';
    @NamespaceAccessible
    public static final String OPERATION_UPDATE = 'Update by record Id';
    @NamespaceAccessible
    public static final String OPERATION_UPSERT = 'Upsert by external ID';

    @NamespaceAccessible
    public static final String LOOKUP_REJECT = 'Reject the row';
    @NamespaceAccessible
    public static final String LOOKUP_LEAVE_EMPTY = 'Leave it empty';

    /** The attribute a row names its record by under Update by record Id. */
    @NamespaceAccessible
    public static final String ID_ATTRIBUTE = 'Id';

    /** Prefixes a record key before its digest, apart from people and organizations (R-IB12). */
    private static final String RECORD_DIGEST = 'record:';

    /** How many records one read of stored values takes, a chunk's worth and more. */
    private static final Integer READ_LIMIT = 10000;

    /** The global describe, asked once per transaction. */
    private static Map<String, Schema.SObjectType> globalDescribe;

    /** One row's working state while the chunk is resolved. */
    private class Item {
        Import_Row__c row;
        /** The row's Record attributes, as the template names them, with defaults applied. */
        Map<String, String> held;
        /** Field API name to the value to write, converted to the field's type. */
        Map<String, Object> values = new Map<String, Object>();
        /** The record key: an Id, or an external ID folded to lower case. */
        String key;
        Id recordId;
        SObject stored;
        Boolean creates = false;
        Boolean changes = false;
        String error;

        Item(Import_Row__c row, Map<String, String> held) {
            this.row = row;
            this.held = held == null ? new Map<String, String>() : held;
        }
    }

    /** One mapped attribute, worked out once per chunk. */
    private class Plan {
        String attribute;
        Schema.DescribeFieldResult field;
        Boolean lookup = false;
        Schema.SObjectType parentType;
        /** The parent field a lookup names its parent by; null for the record Id. */
        String parentField;
    }

    /** True when this template loads one object rather than people and organizations. */
    @NamespaceAccessible
    public static Boolean loadsOneObject(Import_Template__c template) {
        return ImportTemplateService.textOf(template, Import_Template__c.Target_Object__c) != null;
    }

    /** The object this template loads, or null when the org has no object of that name. */
    @NamespaceAccessible
    public static Schema.SObjectType typeOf(Import_Template__c template) {
        return typeNamed(
            ImportTemplateService.textOf(template, Import_Template__c.Target_Object__c)
        );
    }

    /** The object of this API name in this org, or null. */
    @NamespaceAccessible
    public static Schema.SObjectType typeNamed(String objectName) {
        if (String.isBlank(objectName)) {
            return null;
        }
        if (globalDescribe == null) {
            globalDescribe = Schema.getGlobalDescribe();
        }
        return globalDescribe.get(objectName.trim().toLowerCase());
    }

    /** The template's load operation; an empty or unknown one is Insert. */
    @NamespaceAccessible
    public static String operationOf(Import_Template__c template) {
        String chosen = ImportTemplateService.textOf(
            template,
            Import_Template__c.Load_Operation__c
        );
        for (String known : new List<String>{ OPERATION_UPDATE, OPERATION_UPSERT }) {
            if (known.equalsIgnoreCase(chosen)) {
                return known;
            }
        }
        return OPERATION_INSERT;
    }

    /** Whether a lookup that finds nobody leaves the lookup empty rather than rejecting. */
    private static Boolean leavesLookupEmpty(Import_Template__c template) {
        return LOOKUP_LEAVE_EMPTY.equalsIgnoreCase(
            ImportTemplateService.textOf(template, Import_Template__c.Lookup_Not_Found__c)
        );
    }

    // -------------------------------------------------------------------------------------
    // What the wizard offers
    // -------------------------------------------------------------------------------------

    /**
     * The objects a template may load (R-IT12): those the user can read and create or edit
     * records of, that are queryable, and that `DataProtectedFields` does not refuse. Sorted by
     * label. Found in describe, so every object the org has is a candidate and Core names none.
     */
    @NamespaceAccessible
    public static List<ImportMapping.Target> loadableObjects() {
        if (globalDescribe == null) {
            globalDescribe = Schema.getGlobalDescribe();
        }
        Map<String, ImportMapping.Target> byLabel = new Map<String, ImportMapping.Target>();
        for (Schema.SObjectType type : globalDescribe.values()) {
            Schema.DescribeSObjectResult described = type.getDescribe(
                SObjectDescribeOptions.DEFERRED
            );
            if (
                !described.isAccessible() ||
                !described.isQueryable() ||
                !(described.isCreateable() || described.isUpdateable()) ||
                DataProtectedFields.objectRefusal(type) != null
            ) {
                continue;
            }
            byLabel.put(
                described.getLabel() + ' ' + described.getName(),
                new ImportMapping.Target(described.getName(), described.getLabel())
            );
        }
        List<String> labels = new List<String>(byLabel.keySet());
        labels.sort();
        List<ImportMapping.Target> result = new List<ImportMapping.Target>();
        for (String label : labels) {
            result.add(byLabel.get(label));
        }
        return result;
    }

    /**
     * The fields an upsert may match on (R-IT10): the object's own external ID text or email
     * fields that the user may read and filter on. Upsert is the platform's own meaning, so a
     * unique field that is not an external ID is not offered.
     */
    @NamespaceAccessible
    public static List<ImportMapping.Target> keyFields(Schema.SObjectType type) {
        List<ImportMapping.Target> result = new List<ImportMapping.Target>();
        for (ImportMapping.Target candidate : ImportMatcher.matchFields(type)) {
            if (keyField(type, candidate.value) != null) {
                result.add(candidate);
            }
        }
        return result;
    }

    /** The field's API name when an upsert may match on it, or null. */
    @NamespaceAccessible
    public static String keyField(Schema.SObjectType type, String fieldName) {
        String found = ImportMatcher.matchField(type, fieldName);
        if (found == null) {
            return null;
        }
        Schema.DescribeFieldResult field = type.getDescribe(SObjectDescribeOptions.DEFERRED)
            .fields.getMap()
            .get(found.toLowerCase())
            .getDescribe();
        return field.isExternalId() ? found : null;
    }

    /**
     * The fields a lookup column may name its parent by (R-IT11): the record Id, the parent's
     * external ID and unique fields, and its name field. A lookup that can point at more than
     * one object is named by Id only.
     */
    @NamespaceAccessible
    public static List<ImportMapping.Target> parentFields(Schema.DescribeFieldResult lookup) {
        List<ImportMapping.Target> result = new List<ImportMapping.Target>{
            new ImportMapping.Target(ID_ATTRIBUTE, Label.Core_Import_RecordIdOption)
        };
        List<Schema.SObjectType> parents = lookup.getReferenceTo();
        if (parents.size() != 1) {
            return result;
        }
        Set<String> offered = new Set<String>();
        String nameField = nameFieldOf(parents[0]);
        if (nameField != null) {
            Schema.DescribeFieldResult name = fieldsOf(parents[0])
                .get(nameField.toLowerCase())
                .getDescribe();
            result.add(new ImportMapping.Target(name.getName(), name.getLabel()));
            offered.add(name.getName().toLowerCase());
        }
        for (ImportMapping.Target field : ImportMatcher.matchFields(parents[0])) {
            if (!offered.contains(field.value.toLowerCase())) {
                result.add(field);
            }
        }
        return result;
    }

    /**
     * A mapping suggested from a file's header row for one object (R-IT10): a heading that is a
     * writable field's label or API name, ignoring case, spaces and punctuation, is mapped to it,
     * and Id or Record Id to the record Id; anything else is Do not load, never a guess, as the
     * people model's column library does. A second heading for one field is left for the
     * administrator.
     */
    @NamespaceAccessible
    public static ImportMapping suggestMapping(Schema.SObjectType type, List<String> headers) {
        ImportMapping mapping = new ImportMapping();
        if (headers == null) {
            return mapping;
        }
        Map<String, String> known = new Map<String, String>{
            'id' => ID_ATTRIBUTE,
            'recordid' => ID_ATTRIBUTE
        };
        if (type != null) {
            for (Schema.SObjectField token : fieldsOf(type).values()) {
                Schema.DescribeFieldResult field = token.getDescribe();
                if (
                    !(field.isCreateable() || field.isUpdateable()) ||
                    DataProtectedFields.isProtected(type, field.getName())
                ) {
                    continue;
                }
                String byName = normalized(
                    localName(field.getName().toLowerCase()).removeEnd('__c')
                );
                String byLabel = normalized(field.getLabel());
                if (!known.containsKey(byLabel)) {
                    known.put(byLabel, field.getName());
                }
                if (!known.containsKey(byName)) {
                    known.put(byName, field.getName());
                }
            }
        }
        Set<String> used = new Set<String>();
        for (String header : headers) {
            String field = known.get(normalized(header));
            String target = field == null || used.contains(field)
                ? ImportMapping.TARGET_IGNORE
                : ImportMapping.ENTITY_RECORD + '.' + field;
            if (field != null) {
                used.add(field);
            }
            mapping.columns.add(new ImportMapping.Column(header, target));
        }
        return mapping;
    }

    /** A heading or a name folded for comparison: lower case, letters and digits only. */
    private static String normalized(String text) {
        return text == null ? '' : text.toLowerCase().replaceAll('[^a-z0-9]', '');
    }

    /** The parent's name field when the user may read and filter on it, or null. */
    private static String nameFieldOf(Schema.SObjectType type) {
        for (Schema.SObjectField token : fieldsOf(type).values()) {
            Schema.DescribeFieldResult field = token.getDescribe();
            if (field.isNameField() && field.isAccessible() && field.isFilterable()) {
                return field.getName();
            }
        }
        return null;
    }

    /** Whether a lookup column may name its parent by this field (R-IT11). */
    private static Boolean isParentField(Schema.SObjectType parent, String fieldName) {
        if (ImportMatcher.matchField(parent, fieldName) != null) {
            return true;
        }
        String nameField = nameFieldOf(parent);
        return nameField != null && nameField.equalsIgnoreCase(fieldName);
    }

    // -------------------------------------------------------------------------------------
    // Refusals before any row is read
    // -------------------------------------------------------------------------------------

    /**
     * Why this template cannot load its rows, or null (R-IT10, R-IT12): an object that is gone
     * or protected, access the operation needs and the user lacks, no column mapped to the
     * object, and the key column an update or an upsert needs. Asked when a template is saved
     * and when a dry run or a commit starts, and again for every chunk.
     */
    @NamespaceAccessible
    public static String refusal(Import_Template__c template, ImportMapping mapping) {
        Schema.SObjectType type = typeOf(template);
        String refused = DataProtectedFields.objectRefusal(type);
        if (refused != null) {
            return refused;
        }
        Schema.DescribeSObjectResult described = type.getDescribe(SObjectDescribeOptions.DEFERRED);
        String operation = operationOf(template);
        Boolean access =
            described.isAccessible() &&
            described.isQueryable() &&
            (operation == OPERATION_INSERT
                ? described.isCreateable()
                : operation == OPERATION_UPDATE
                      ? described.isUpdateable()
                      : described.isCreateable() && described.isUpdateable());
        if (!access) {
            return String.format(
                Label.Core_Import_ErrorObjectNoAccess,
                new List<String>{ described.getLabelPlural() }
            );
        }
        Set<String> attributes = recordAttributes(mapping);
        if (attributes.isEmpty()) {
            return Label.Core_Import_ErrorNothingMapped;
        }
        if (operation == OPERATION_UPDATE && !attributes.contains(ID_ATTRIBUTE.toLowerCase())) {
            return Label.Core_Import_ErrorIdColumnMissing;
        }
        if (operation == OPERATION_UPSERT) {
            String chosen = ImportTemplateService.textOf(
                template,
                Import_Template__c.Load_Match_Field__c
            );
            if (chosen == null) {
                return Label.Core_Import_ErrorKeyFieldRequired;
            }
            String key = keyField(type, chosen);
            if (key == null) {
                return String.format(
                    Label.Core_Import_ErrorKeyFieldUnusable,
                    new List<String>{ chosen.abbreviate(80) }
                );
            }
            if (!mapsField(attributes, key)) {
                return String.format(
                    Label.Core_Import_ErrorKeyColumnMissing,
                    new List<String>{
                        fieldsOf(type).get(key.toLowerCase()).getDescribe().getLabel()
                    }
                );
            }
        }
        return null;
    }

    /** The Record attributes a mapping writes, from its columns and its values, in lower case. */
    private static Set<String> recordAttributes(ImportMapping mapping) {
        Set<String> result = new Set<String>();
        List<String> targets = new List<String>(mapping.targetsBySourceKey().values());
        for (ImportMapping.Assignment assignment : mapping.assignments()) {
            targets.add(assignment.target);
        }
        for (String target : targets) {
            if (ImportMapping.ENTITY_RECORD.equalsIgnoreCase(ImportMapping.entityOf(target))) {
                result.add(ImportMapping.attributeOf(target).toLowerCase());
            }
        }
        return result;
    }

    /** Whether one of these attributes names this field, with or without the namespace. */
    private static Boolean mapsField(Set<String> attributes, String fieldName) {
        String lower = fieldName.toLowerCase();
        return attributes.contains(lower) || attributes.contains(localName(lower));
    }

    // -------------------------------------------------------------------------------------
    // One chunk
    // -------------------------------------------------------------------------------------

    /**
     * Resolves one chunk. Writes nothing but the staged rows when dryRun is true. Each row is
     * updated in place with its status, its error and the record it resulted in, and saved.
     */
    @NamespaceAccessible
    public static ImportRowProcessor.Outcome process(
        Import_Batch__c batch,
        Import_Template__c template,
        ImportMapping mapping,
        List<Import_Row__c> rows,
        Boolean dryRun
    ) {
        ImportRowProcessor.Outcome outcome = new ImportRowProcessor.Outcome();
        List<Item> items = new List<Item>();
        Decimal pass = ImportRowSelector.passOf(batch);
        for (Import_Row__c row : rows) {
            ImportRowProcessor.startPass(row, pass);
            Map<String, Map<String, String>> byEntity = ImportRowProcessor.valuesByEntity(
                row,
                mapping
            );
            Item item = new Item(row, byEntity.get(ImportMapping.ENTITY_RECORD));
            if (String.isBlank(row.Raw_Values_JSON__c)) {
                item.error = Label.Core_Import_ErrorRowUnreadable;
            } else if (!hasAnyValue(item.held)) {
                // Nothing to create or change: the row's mapped cells are all empty.
                item.error = Label.Core_Import_ErrorRowEmpty;
            }
            items.add(item);
        }
        String refused = refusal(template, mapping);
        if (refused != null) {
            // Nothing can load: every row says why, in words the administrator can act on.
            for (Item item : items) {
                item.error = refused;
            }
            writeBack(items, outcome);
            return outcome;
        }
        Schema.SObjectType type = typeOf(template);
        String operation = operationOf(template);
        Map<String, Plan> plans = plan(type, mapping, items, outcome);
        readValues(items, plans);
        resolveLookups(
            items,
            plans,
            leavesLookupEmpty(template),
            ImportTemplateService.usesMostRecent(template),
            outcome
        );
        findRecords(batch, template, type, operation, items, plans);
        decide(type, items, plans, outcome);
        if (!dryRun) {
            save(type, items, outcome);
        }
        writeBack(items, outcome);
        if (
            !dryRun &&
            !ImportJournalService.write(
                batch.Id,
                ImportJournalService.PHASE_COMMIT,
                outcome.journal
            )
        ) {
            outcome.notes.add(Label.Core_Import_LogJournalFailed);
        }
        return outcome;
    }

    /**
     * Works out, once per chunk, what each mapped attribute is: a value field, a lookup and how
     * it names its parent, or something not loaded, said once in the run log (a field the object
     * does not have, or one that is protected, R-IT12). Access is asked when the record is built,
     * because an upsert does not know yet whether a row creates or updates.
     */
    private static Map<String, Plan> plan(
        Schema.SObjectType type,
        ImportMapping mapping,
        List<Item> items,
        ImportRowProcessor.Outcome outcome
    ) {
        Map<String, Plan> plans = new Map<String, Plan>();
        Map<String, String> lookupFields = mapping.lookupFieldsByAttribute();
        Set<String> attributes = new Set<String>();
        for (Item item : items) {
            attributes.addAll(item.held.keySet());
        }
        Map<String, Schema.SObjectField> fields = fieldsOf(type);
        for (String attribute : attributes) {
            String lower = attribute.toLowerCase();
            if (lower == ID_ATTRIBUTE.toLowerCase() || plans.containsKey(lower)) {
                // The record Id names the record under Update; it is never a value to write.
                continue;
            }
            Schema.SObjectField token = fields.get(lower);
            if (token == null) {
                outcome.notes.add(
                    String.format(
                        Label.Core_Import_LogAttributeUnknown,
                        new List<String>{ attribute }
                    )
                );
                continue;
            }
            Schema.DescribeFieldResult field = token.getDescribe();
            if (DataProtectedFields.isProtected(type, field.getName())) {
                outcome.notes.add(
                    String.format(
                        Label.Core_Import_LogFieldProtected,
                        new List<String>{ field.getLabel() }
                    )
                );
                continue;
            }
            Plan planned = new Plan();
            planned.attribute = lower;
            planned.field = field;
            if (field.getType() == Schema.DisplayType.REFERENCE) {
                planned.lookup = true;
                List<Schema.SObjectType> parents = field.getReferenceTo();
                planned.parentType = parents.size() == 1 ? parents[0] : null;
                String chosen = lookupFields.get(lower);
                if (chosen != null && planned.parentType == null) {
                    // A lookup to several objects is read by record Id only (R-IT11).
                    outcome.notes.add(
                        String.format(
                            Label.Core_Import_LogLookupPolymorphic,
                            new List<String>{ field.getLabel() }
                        )
                    );
                } else if (chosen != null) {
                    // A field the user cannot search by finds nobody, and each row's rule then
                    // decides, rather than the row being matched on something else.
                    planned.parentField = chosen;
                }
            }
            plans.put(lower, planned);
        }
        return plans;
    }

    /**
     * Converts each row's values to their fields' types. A value the field cannot take (an
     * unreadable date, a number with letters, a checkbox value that is neither yes nor no, text
     * longer than the field) rejects the row, naming the field and the value (R-IT10).
     */
    private static void readValues(List<Item> items, Map<String, Plan> plans) {
        for (Item item : items) {
            if (item.error != null) {
                continue;
            }
            for (String attribute : item.held.keySet()) {
                Plan planned = plans.get(attribute.toLowerCase());
                String value = item.held.get(attribute);
                if (planned == null || planned.lookup || String.isBlank(value)) {
                    continue;
                }
                String problem = unreadable(value, planned.field);
                if (problem != null) {
                    item.error = problem;
                    break;
                }
                item.values.put(planned.field.getName(), typed(value, planned.field));
            }
        }
    }

    /** Why this value cannot be written to this field, or null when it can. */
    private static String unreadable(String value, Schema.DescribeFieldResult field) {
        Schema.DisplayType kind = field.getType();
        Integer length = field.getLength();
        Boolean text =
            kind == Schema.DisplayType.STRING ||
            kind == Schema.DisplayType.TEXTAREA ||
            kind == Schema.DisplayType.EMAIL ||
            kind == Schema.DisplayType.PHONE ||
            kind == Schema.DisplayType.URL ||
            kind == Schema.DisplayType.PICKLIST ||
            kind == Schema.DisplayType.MULTIPICKLIST;
        if (text && length != null && length > 0 && value.length() > length) {
            return String.format(
                Label.Core_Import_ErrorValueTooLong,
                new List<String>{ field.getLabel(), String.valueOf(length) }
            );
        }
        try {
            if (typed(value, field) == null) {
                throw new ImportException(value);
            }
            return null;
        } catch (Exception notReadable) {
            return String.format(
                Label.Core_Import_ErrorValueUnreadable,
                new List<String>{ field.getLabel(), value.abbreviate(80) }
            );
        }
    }

    /**
     * A value as its field's type: the people model's reading (`ImportRowProcessor.convert`),
     * with a date also read in the running user's locale and a date and time also read as ISO
     * 8601, since a one-object file is often another system's export. Throws, or returns null
     * for a checkbox value that is neither yes nor no, when the value cannot be read.
     */
    private static Object typed(String value, Schema.DescribeFieldResult field) {
        Schema.DisplayType kind = field.getType();
        String trimmed = value.trim();
        if (kind == Schema.DisplayType.DATE) {
            try {
                return Date.valueOf(trimmed);
            } catch (Exception notIso) {
                return Date.parse(trimmed);
            }
        }
        if (kind == Schema.DisplayType.DATETIME) {
            try {
                return Datetime.valueOf(trimmed);
            } catch (Exception notSpaced) {
                return (Datetime) JSON.deserialize('"' + trimmed + '"', Datetime.class);
            }
        }
        if (kind == Schema.DisplayType.TIME) {
            List<String> parts = trimmed.split(':');
            return Time.newInstance(
                Integer.valueOf(parts[0]),
                parts.size() > 1 ? Integer.valueOf(parts[1]) : 0,
                parts.size() > 2 ? Integer.valueOf(parts[2]) : 0,
                0
            );
        }
        if (
            kind == Schema.DisplayType.CURRENCY ||
            kind == Schema.DisplayType.DOUBLE ||
            kind == Schema.DisplayType.PERCENT
        ) {
            // Thousands separators and a currency sign are dropped; anything else is refused.
            return Decimal.valueOf(trimmed.replaceAll('[\\s,$%]', ''));
        }
        if (kind == Schema.DisplayType.INTEGER) {
            return Integer.valueOf(trimmed.replaceAll('[\\s,]', ''));
        }
        return ImportRowProcessor.convert(trimmed, field);
    }

    /**
     * Finds the parent each lookup column names (R-IT11), one query per column and chunk, in
     * user mode: by record Id, or by the chosen field through the importer's own matcher, which
     * says when several records hold a value and which was changed most recently (R-IT9).
     */
    private static void resolveLookups(
        List<Item> items,
        Map<String, Plan> plans,
        Boolean leaveEmpty,
        Boolean mostRecent,
        ImportRowProcessor.Outcome outcome
    ) {
        for (Plan planned : plans.values()) {
            if (planned.lookup) {
                resolveLookup(items, planned, leaveEmpty, mostRecent, outcome);
            }
        }
    }

    private static void resolveLookup(
        List<Item> items,
        Plan planned,
        Boolean leaveEmpty,
        Boolean mostRecent,
        ImportRowProcessor.Outcome outcome
    ) {
        Set<String> keys = new Set<String>();
        for (Item item : items) {
            String value = valueOf(item, planned.attribute);
            if (item.error == null && String.isNotBlank(value)) {
                keys.add(planned.parentField == null ? value.trim() : ImportMatcher.nameKey(value));
            }
        }
        if (keys.isEmpty()) {
            return;
        }
        Map<String, Id> found = planned.parentField == null
            ? parentsById(planned, keys)
            : parentsByField(planned, keys);
        Boolean leftEmpty = false;
        for (Item item : items) {
            String value = valueOf(item, planned.attribute);
            if (item.error != null || String.isBlank(value)) {
                continue;
            }
            String key = planned.parentField == null ? value.trim() : ImportMatcher.nameKey(value);
            Id parent = found.get(key);
            if (parent != null && planned.parentField != null && ImportMatcher.isHeldByMany(key)) {
                item.row.Several_Matches__c = true;
                if (!mostRecent) {
                    item.error = String.format(
                        Label.Core_Import_ErrorLookupSeveral,
                        new List<String>{ planned.field.getLabel(), value.abbreviate(80) }
                    );
                    continue;
                }
                parent = ImportMatcher.mostRecent(key);
            }
            if (parent != null) {
                item.values.put(planned.field.getName(), parent);
            } else if (leaveEmpty) {
                leftEmpty = true;
            } else {
                item.error = String.format(
                    Label.Core_Import_ErrorLookupNotFound,
                    new List<String>{ planned.field.getLabel(), value.abbreviate(80) }
                );
            }
        }
        if (leftEmpty) {
            outcome.notes.add(
                String.format(
                    Label.Core_Import_LogLookupLeftEmpty,
                    new List<String>{ planned.field.getLabel() }
                )
            );
        }
    }

    /**
     * The parents named by record Id that the user can see, keyed by the value as given. A value
     * that is not an Id of the lookup's object is not found, which the row's rule then decides.
     */
    private static Map<String, Id> parentsById(Plan planned, Set<String> values) {
        Map<String, Id> result = new Map<String, Id>();
        Map<Schema.SObjectType, Set<Id>> idsByType = new Map<Schema.SObjectType, Set<Id>>();
        Set<Schema.SObjectType> allowed = new Set<Schema.SObjectType>(
            planned.field.getReferenceTo()
        );
        // A 15 and an 18 character form of one Id are one record, named by both values.
        Map<Id, List<String>> valuesById = new Map<Id, List<String>>();
        for (String value : values) {
            Id candidate = idOrNull(value);
            if (candidate == null || !allowed.contains(candidate.getSObjectType())) {
                continue;
            }
            if (!idsByType.containsKey(candidate.getSObjectType())) {
                idsByType.put(candidate.getSObjectType(), new Set<Id>());
            }
            idsByType.get(candidate.getSObjectType()).add(candidate);
            if (!valuesById.containsKey(candidate)) {
                valuesById.put(candidate, new List<String>());
            }
            valuesById.get(candidate).add(value);
        }
        for (Schema.SObjectType parentType : idsByType.keySet()) {
            for (Id seen : visibleIds(parentType, idsByType.get(parentType))) {
                for (String value : valuesById.get(seen)) {
                    result.put(value, seen);
                }
            }
        }
        return result;
    }

    /** The parents named by the chosen field, keyed by the value in lower case (R-IT11). */
    private static Map<String, Id> parentsByField(Plan planned, Set<String> keys) {
        if (planned.parentType == null || !isParentField(planned.parentType, planned.parentField)) {
            // Nothing can be found by a field the user cannot search: each row's rule decides.
            return new Map<String, Id>();
        }
        ImportMatcher.forgetHeldKeys();
        return ImportMatcher.byField(planned.parentType, planned.parentField, keys, null);
    }

    /** The records of these Ids the user can see, in user mode, kept out of the caller's loop. */
    private static Set<Id> visibleIds(Schema.SObjectType type, Set<Id> ids) {
        Schema.DescribeSObjectResult described = type.getDescribe(SObjectDescribeOptions.DEFERRED);
        if (!described.isAccessible() || !described.isQueryable()) {
            return new Set<Id>();
        }
        Set<Id> result = new Set<Id>();
        for (
            SObject record : Database.queryWithBinds(
                'SELECT Id FROM ' + described.getName() + ' WHERE Id IN :ids',
                new Map<String, Object>{ 'ids' => ids },
                AccessLevel.USER_MODE
            )
        ) {
            result.add(record.Id);
        }
        return result;
    }

    /**
     * Finds the record each row names under Update by record Id and Upsert by external ID,
     * reads what it holds now, and rejects a row whose key an earlier row of the file used
     * (R-IT10). The key's digest is written to the row in the dry run and the commit alike, so a
     * later chunk finds it however the file was cut.
     */
    private static void findRecords(
        Import_Batch__c batch,
        Import_Template__c template,
        Schema.SObjectType type,
        String operation,
        List<Item> items,
        Map<String, Plan> plans
    ) {
        if (operation == OPERATION_INSERT) {
            for (Item item : items) {
                item.creates = item.error == null;
            }
            return;
        }
        String keyField = operation == OPERATION_UPSERT
            ? keyField(
                  type,
                  ImportTemplateService.textOf(template, Import_Template__c.Load_Match_Field__c)
              )
            : null;
        for (Item item : items) {
            if (item.error != null) {
                continue;
            }
            if (operation == OPERATION_UPDATE) {
                String value = valueOf(item, ID_ATTRIBUTE.toLowerCase());
                Id candidate = idOrNull(value);
                if (candidate == null || candidate.getSObjectType() != type) {
                    item.error = String.format(
                        Label.Core_Import_ErrorRecordIdInvalid,
                        new List<String>{ String.isBlank(value) ? '' : value.abbreviate(40) }
                    );
                    continue;
                }
                item.recordId = candidate;
                item.key = String.valueOf(candidate);
            } else {
                String value = valueByField(item, keyField);
                if (String.isBlank(value)) {
                    item.error = String.format(
                        Label.Core_Import_ErrorKeyMissing,
                        new List<String>{
                            fieldsOf(type).get(keyField.toLowerCase()).getDescribe().getLabel()
                        }
                    );
                    continue;
                }
                item.key = ImportMatcher.nameKey(value);
            }
        }
        rejectRepeats(batch, items);
        if (operation == OPERATION_UPSERT) {
            Set<String> keys = new Set<String>();
            for (Item item : items) {
                if (item.error == null) {
                    keys.add(item.key);
                }
            }
            ImportMatcher.forgetHeldKeys();
            Map<String, Id> found = ImportMatcher.byField(type, keyField, keys, null);
            for (Item item : items) {
                if (item.error != null) {
                    continue;
                }
                Id match = found.get(item.key);
                if (match != null && ImportMatcher.isHeldByMany(item.key)) {
                    item.row.Several_Matches__c = true;
                    if (!ImportTemplateService.usesMostRecent(template)) {
                        item.error = Label.Core_Import_ErrorSeveralRecords;
                        continue;
                    }
                    match = ImportMatcher.mostRecent(item.key);
                }
                item.recordId = match;
                item.creates = match == null;
            }
        }
        Map<Id, SObject> stored = readStored(type, items, plans);
        for (Item item : items) {
            if (item.error != null || item.recordId == null) {
                continue;
            }
            item.stored = stored.get(item.recordId);
            if (item.stored == null) {
                item.error = Label.Core_Import_ErrorRecordNotFound;
            }
        }
    }

    /**
     * Rejects a row whose record key an earlier row of this file used: in this chunk, or in an
     * earlier chunk of the same pass, found by digest (R-IT10, R-IB13). Every other row with a
     * key carries its digest for the chunks after it.
     */
    private static void rejectRepeats(Import_Batch__c batch, List<Item> items) {
        Set<String> digests = new Set<String>();
        for (Item item : items) {
            if (item.error == null && item.key != null) {
                digests.add(digest(item.key));
            }
        }
        if (digests.isEmpty()) {
            return;
        }
        Set<String> earlier = ImportRowSelector.processorDigestsWrittenEarlier(batch, digests);
        Set<String> inChunk = new Set<String>();
        for (Item item : items) {
            if (item.error != null || item.key == null) {
                continue;
            }
            String digest = digest(item.key);
            if (earlier.contains(digest) || inChunk.contains(digest)) {
                item.error = Label.Core_Import_ErrorRecordRepeated;
                continue;
            }
            inChunk.add(digest);
            item.row.Processor_Key__c = digest;
        }
    }

    /**
     * The records the rows update, with the fields the load would write that the user may read,
     * in user mode, so a change can be compared and its value before journaled. A field the user
     * cannot read is never written to a record that exists (`decide`), so nothing is put back
     * that was not read.
     */
    private static Map<Id, SObject> readStored(
        Schema.SObjectType type,
        List<Item> items,
        Map<String, Plan> plans
    ) {
        Set<Id> ids = new Set<Id>();
        for (Item item : items) {
            if (item.error == null && item.recordId != null) {
                ids.add(item.recordId);
            }
        }
        if (ids.isEmpty()) {
            return new Map<Id, SObject>();
        }
        Set<String> selected = new Set<String>{ 'Id' };
        if (fieldsOf(type).containsKey('recordtypeid')) {
            selected.add('RecordTypeId');
        }
        for (Plan planned : plans.values()) {
            if (planned.field.isAccessible()) {
                selected.add(planned.field.getName());
            }
        }
        return new Map<Id, SObject>(
            Database.queryWithBinds(
                'SELECT ' +
                    String.join(new List<String>(selected), ', ') +
                    ' FROM ' +
                    type.getDescribe(SObjectDescribeOptions.DEFERRED).getName() +
                    ' WHERE Id IN :ids LIMIT ' +
                    READ_LIMIT,
                new Map<String, Object>{ 'ids' => ids },
                AccessLevel.USER_MODE
            )
        );
    }

    /**
     * Decides what each row does, the same in the dry run as in the commit: a new record with
     * every value the user may set on one, or the values that differ on an existing record that
     * the user may read and edit, leaving a household's name alone (R-IT12). A field skipped for
     * access is named once in the run log.
     */
    private static void decide(
        Schema.SObjectType type,
        List<Item> items,
        Map<String, Plan> plans,
        ImportRowProcessor.Outcome outcome
    ) {
        Map<String, Schema.DescribeFieldResult> byName = new Map<String, Schema.DescribeFieldResult>();
        for (Plan planned : plans.values()) {
            byName.put(planned.field.getName(), planned.field);
        }
        for (Item item : items) {
            if (item.error != null) {
                continue;
            }
            Map<String, Object> kept = new Map<String, Object>();
            for (String name : item.values.keySet()) {
                Schema.DescribeFieldResult field = byName.get(name);
                Object value = item.values.get(name);
                if (item.creates) {
                    if (!field.isCreateable()) {
                        outcome.notes.add(noAccess(field));
                        continue;
                    }
                    kept.put(name, value);
                    continue;
                }
                if (!field.isUpdateable() || !field.isAccessible()) {
                    outcome.notes.add(noAccess(field));
                    continue;
                }
                Id recordType = fieldsOf(type).containsKey('recordtypeid')
                    ? (Id) item.stored.get('RecordTypeId')
                    : null;
                if (DataProtectedFields.isProtectedOnRecord(type, name, recordType)) {
                    outcome.notes.add(
                        String.format(
                            Label.Core_Import_LogFieldProtected,
                            new List<String>{ field.getLabel() }
                        )
                    );
                    continue;
                }
                if (!same(item.stored.get(name), value)) {
                    kept.put(name, value);
                }
            }
            item.values = kept;
            item.changes = item.creates || !kept.isEmpty();
        }
    }

    /**
     * Saves the chunk's new records and changes in the running user's own mode, each record on
     * its own and past a duplicate rule that only alerts, as the people model saves (R-IB12), and
     * journals each creation and each update with the values it replaced (R-IJ3).
     */
    private static void save(
        Schema.SObjectType type,
        List<Item> items,
        ImportRowProcessor.Outcome outcome
    ) {
        String objectName = type.getDescribe(SObjectDescribeOptions.DEFERRED).getName();
        List<SObject> toCreate = new List<SObject>();
        List<Item> creators = new List<Item>();
        List<SObject> toUpdate = new List<SObject>();
        List<Item> updaters = new List<Item>();
        for (Item item : items) {
            if (item.error != null || !item.changes) {
                continue;
            }
            SObject record = item.creates ? type.newSObject() : type.newSObject(item.recordId);
            for (String name : item.values.keySet()) {
                record.put(name, item.values.get(name));
            }
            if (item.creates) {
                toCreate.add(record);
                creators.add(item);
            } else {
                toUpdate.add(record);
                updaters.add(item);
            }
        }
        List<Database.SaveResult> created = toCreate.isEmpty()
            ? new List<Database.SaveResult>()
            : Database.insert(toCreate, ImportRowProcessor.saveOptions(), AccessLevel.USER_MODE);
        for (Integer i = 0; i < created.size(); i++) {
            Item item = creators[i];
            if (created[i].isSuccess()) {
                item.recordId = created[i].getId();
                outcome.journal.add(
                    ImportJournalService.created(objectName, item.recordId, rowNumber(item.row))
                );
            } else {
                item.error = ImportRowProcessor.message(created[i]);
            }
        }
        List<Database.SaveResult> updated = toUpdate.isEmpty()
            ? new List<Database.SaveResult>()
            : Database.update(toUpdate, ImportRowProcessor.saveOptions(), AccessLevel.USER_MODE);
        for (Integer i = 0; i < updated.size(); i++) {
            Item item = updaters[i];
            if (!updated[i].isSuccess()) {
                item.error = ImportRowProcessor.message(updated[i]);
                continue;
            }
            Map<String, Object> before = new Map<String, Object>();
            for (String name : item.values.keySet()) {
                before.put(name, item.stored.get(name));
            }
            outcome.journal.add(
                ImportJournalService.updated(
                    objectName,
                    item.recordId,
                    rowNumber(item.row),
                    before,
                    item.values
                )
            );
        }
    }

    /**
     * Writes each row's outcome back, in system mode (ADR-0021): Rejected with the reason,
     * Created, Updated, or Matched when the record already held every value, with the record it
     * resulted in as its Resulting Record.
     */
    private static void writeBack(List<Item> items, ImportRowProcessor.Outcome outcome) {
        List<Import_Row__c> rows = new List<Import_Row__c>();
        for (Item item : items) {
            Import_Row__c row = item.row;
            if (item.error != null) {
                row.Status__c = ImportRowProcessor.STATUS_REJECTED;
                row.Error_Message__c = item.error.abbreviate(4000);
                row.Processor_Key__c = null;
                outcome.rejected++;
            } else if (item.creates) {
                row.Status__c = ImportRowProcessor.STATUS_CREATED;
                outcome.created++;
            } else if (item.changes) {
                row.Status__c = ImportRowProcessor.STATUS_UPDATED;
                outcome.updated++;
            } else {
                row.Status__c = ImportRowProcessor.STATUS_MATCHED;
                outcome.matched++;
            }
            row.Gift_Id__c = item.error == null &&
                item.recordId != null
                ? String.valueOf(item.recordId)
                : null;
            rows.add(row);
        }
        if (!rows.isEmpty()) {
            Database.update(rows, false, AccessLevel.SYSTEM_MODE);
        }
    }

    // -------------------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------------------

    private static Boolean hasAnyValue(Map<String, String> held) {
        for (String value : held.values()) {
            if (String.isNotBlank(value)) {
                return true;
            }
        }
        return false;
    }

    /** A row's value for an attribute, found ignoring case. */
    private static String valueOf(Item item, String lowerCaseAttribute) {
        for (String attribute : item.held.keySet()) {
            if (attribute.toLowerCase() == lowerCaseAttribute) {
                return item.held.get(attribute);
            }
        }
        return null;
    }

    /** A row's value for a field, named with or without the package's namespace (R-IT1). */
    private static String valueByField(Item item, String fieldName) {
        String lower = fieldName.toLowerCase();
        String found = valueOf(item, lower);
        return found != null ? found : valueOf(item, localName(lower));
    }

    /**
     * Whether a stored value equals the one a row would write, as the undo compares them (R-IJ2):
     * numbers as numbers, dates and times as themselves, identifiers in either length, and text
     * exactly, since a correction of capitals is a correction.
     */
    private static Boolean same(Object stored, Object incoming) {
        if (stored == null || incoming == null) {
            return stored == null && incoming == null;
        }
        if (incoming instanceof Decimal || incoming instanceof Integer) {
            return Decimal.valueOf(String.valueOf(stored)) ==
                Decimal.valueOf(String.valueOf(incoming));
        }
        if (incoming instanceof Id) {
            return idOrNull(String.valueOf(stored)) == incoming;
        }
        if (incoming instanceof Date || incoming instanceof Datetime || incoming instanceof Time) {
            return stored == incoming;
        }
        if (incoming instanceof Boolean) {
            return stored == incoming;
        }
        return String.valueOf(stored).equals(String.valueOf(incoming));
    }

    private static Id idOrNull(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Id.valueOf(value.trim());
        } catch (Exception notAnId) {
            return null;
        }
    }

    /** A record key as sixteen hex digits, as the people model digests its keys (R-IB12). */
    private static String digest(String key) {
        return EncodingUtil.convertToHex(
                Crypto.generateDigest('MD5', Blob.valueOf(RECORD_DIGEST + key))
            )
            .left(16);
    }

    private static Integer rowNumber(Import_Row__c row) {
        return row == null || row.Row_Number__c == null ? null : row.Row_Number__c.intValue();
    }

    private static String noAccess(Schema.DescribeFieldResult field) {
        return String.format(
            Label.Core_Import_LogAttributeNoAccess,
            new List<String>{ field.getLabel() }
        );
    }

    /** A lower case API name without this package's namespace. */
    private static String localName(String lowerCaseName) {
        String prefix = NamespaceUtil.prefix().toLowerCase();
        return String.isNotBlank(prefix) && lowerCaseName.startsWith(prefix)
            ? lowerCaseName.removeStart(prefix)
            : lowerCaseName;
    }

    /** Each object's fields, described once per transaction. */
    private static final Map<Schema.SObjectType, Map<String, Schema.SObjectField>> FIELD_MAPS = new Map<Schema.SObjectType, Map<String, Schema.SObjectField>>();

    private static Map<String, Schema.SObjectField> fieldsOf(Schema.SObjectType type) {
        if (!FIELD_MAPS.containsKey(type)) {
            FIELD_MAPS.put(type, type.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap());
        }
        return FIELD_MAPS.get(type);
    }
}

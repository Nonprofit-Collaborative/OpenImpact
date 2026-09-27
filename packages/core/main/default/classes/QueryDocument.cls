/**
 * The query document Find, saved queries and bulk update share (canonical model Section 17B,
 * ADR-0047 amended): which kind of record, which fields, which records (an R-R2 filter extended
 * by R-Q2), in what order and how many.
 *
 * This class only reads and checks the document's shape. It never decides whether a name is
 * real or readable: that is `QueryCompiler`'s job, against the running user's own describe
 * results. Nothing here builds query text.
 */
@NamespaceAccessible
public with sharing class QueryDocument {
    @NamespaceAccessible
    public static final Integer SUPPORTED_VERSION = 1;
    /** The longest document accepted, in characters: the size of the saved query's field. */
    @NamespaceAccessible
    public static final Integer MAX_LENGTH = 32768;
    @NamespaceAccessible
    public static final Integer MAX_FIELDS = 50;
    @NamespaceAccessible
    public static final Integer MAX_CONDITIONS = 20;
    @NamespaceAccessible
    public static final Integer MAX_LIST_VALUES = 100;
    @NamespaceAccessible
    public static final Integer MAX_SORT_FIELDS = 3;
    @NamespaceAccessible
    public static final Integer MAX_VALUE_LENGTH = 255;
    /** The largest row limit a document may carry (R-Q2 table: Row Limit). */
    @NamespaceAccessible
    public static final Integer MAX_ROW_LIMIT = 100000;

    /** Raised when a document cannot be read or breaks one of the limits above. */
    @NamespaceAccessible
    public class QueryDocumentException extends Exception {
    }

    /** One filter condition, as R-R2 writes it, with the R-Q2 relative period. */
    @NamespaceAccessible
    public class Condition {
        @NamespaceAccessible
        public String id;
        @NamespaceAccessible
        public String field;
        @NamespaceAccessible
        public String operator;
        /** A single value, or a list for in and not in; null for the two empty operators. */
        @NamespaceAccessible
        public Object value;
        /** A relative period (R-Q2) in place of a value, or null. */
        @NamespaceAccessible
        public String relative;
        /** The N of LAST_N_DAYS and NEXT_N_DAYS. */
        @NamespaceAccessible
        public Integer n;
    }

    /** One sort field. */
    @NamespaceAccessible
    public class SortField {
        @NamespaceAccessible
        public String field;
        @NamespaceAccessible
        public Boolean descending = false;
        @NamespaceAccessible
        public Boolean nullsFirst = false;
    }

    @NamespaceAccessible
    public String objectName;
    @NamespaceAccessible
    public List<String> fields = new List<String>();
    @NamespaceAccessible
    public String logic;
    @NamespaceAccessible
    public List<Condition> conditions = new List<Condition>();
    @NamespaceAccessible
    public List<SortField> orderBy = new List<SortField>();
    /** Null means as many as the tool that runs it allows. */
    @NamespaceAccessible
    public Integer rowLimit;

    /**
     * Reads a document, checking only its shape and its limits (R-Q4). Every failure is the
     * same plain sentence, because the person who sees it built the document in a screen and
     * cannot act on which bracket was wrong.
     */
    @NamespaceAccessible
    public static QueryDocument parse(String documentJson) {
        if (String.isBlank(documentJson) || documentJson.length() > MAX_LENGTH) {
            throw new QueryDocumentException(
                String.isBlank(documentJson)
                    ? Label.Core_Find_ErrorInvalidDocument
                    : Label.Core_Find_ErrorTooBig
            );
        }
        Map<String, Object> raw;
        try {
            raw = (Map<String, Object>) JSON.deserializeUntyped(documentJson);
        } catch (Exception unreadable) {
            throw new QueryDocumentException(Label.Core_Find_ErrorInvalidDocument);
        }
        return fromMap(raw);
    }

    /** Reads a document already parsed into a map (a bulk update carries one inside its own). */
    @NamespaceAccessible
    public static QueryDocument fromMap(Map<String, Object> raw) {
        if (raw == null) {
            throw new QueryDocumentException(Label.Core_Find_ErrorInvalidDocument);
        }
        try {
            QueryDocument document = new QueryDocument();
            Object version = raw.get('version');
            if (version != null && Integer.valueOf(version) != SUPPORTED_VERSION) {
                throw new QueryDocumentException(Label.Core_Find_ErrorInvalidDocument);
            }
            document.objectName = text(raw.get('object'));
            if (String.isBlank(document.objectName)) {
                throw new QueryDocumentException(Label.Core_Find_ErrorInvalidDocument);
            }
            for (Object field : asList(raw.get('fields'))) {
                if (String.isNotBlank(text(field))) {
                    document.fields.add(text(field));
                }
            }
            readFilter(document, raw.get('filter'));
            for (Object entry : asList(raw.get('orderBy'))) {
                Map<String, Object> rawSort = (Map<String, Object>) entry;
                SortField sortField = new SortField();
                sortField.field = text(rawSort.get('field'));
                sortField.descending = 'DESC'.equalsIgnoreCase(text(rawSort.get('direction')));
                sortField.nullsFirst = 'FIRST'.equalsIgnoreCase(text(rawSort.get('nulls')));
                if (String.isNotBlank(sortField.field)) {
                    document.orderBy.add(sortField);
                }
            }
            Object rowLimit = raw.get('limit');
            if (rowLimit != null && String.isNotBlank(String.valueOf(rowLimit))) {
                Decimal wanted = Decimal.valueOf(String.valueOf(rowLimit));
                if (wanted < 1 || wanted > MAX_ROW_LIMIT || wanted.scale() > 0) {
                    throw new QueryDocumentException(Label.Core_Find_ErrorRowLimit);
                }
                document.rowLimit = wanted.intValue();
            }
            document.checkLimits();
            return document;
        } catch (QueryDocumentException known) {
            throw known;
        } catch (Exception wrongShape) {
            throw new QueryDocumentException(Label.Core_Find_ErrorInvalidDocument);
        }
    }

    /** The document as JSON, in the shape `parse` reads, for saving and for display. */
    @NamespaceAccessible
    public String serialize() {
        return JSON.serialize(toMap());
    }

    /** The document as a map, in the shape `fromMap` reads. */
    @NamespaceAccessible
    public Map<String, Object> toMap() {
        List<Object> rawConditions = new List<Object>();
        for (Condition condition : conditions) {
            Map<String, Object> entry = new Map<String, Object>{
                'id' => condition.id,
                'field' => condition.field,
                'operator' => condition.operator
            };
            if (condition.value != null) {
                entry.put('value', condition.value);
            }
            if (String.isNotBlank(condition.relative)) {
                entry.put('relative', condition.relative);
            }
            if (condition.n != null) {
                entry.put('n', condition.n);
            }
            rawConditions.add(entry);
        }
        List<Object> rawSort = new List<Object>();
        for (SortField sortField : orderBy) {
            rawSort.add(
                new Map<String, Object>{
                    'field' => sortField.field,
                    'direction' => sortField.descending == true ? 'DESC' : 'ASC',
                    'nulls' => sortField.nullsFirst == true ? 'FIRST' : 'LAST'
                }
            );
        }
        Map<String, Object> filter = new Map<String, Object>{ 'conditions' => rawConditions };
        if (String.isNotBlank(logic)) {
            filter.put('logic', logic);
        }
        Map<String, Object> result = new Map<String, Object>{
            'version' => SUPPORTED_VERSION,
            'object' => objectName,
            'fields' => fields,
            'filter' => filter,
            'orderBy' => rawSort
        };
        if (rowLimit != null) {
            result.put('limit', rowLimit);
        }
        return result;
    }

    private static void readFilter(QueryDocument document, Object rawFilter) {
        if (rawFilter == null) {
            return;
        }
        Map<String, Object> filter = (Map<String, Object>) rawFilter;
        Object version = filter.get('version');
        if (version != null && Integer.valueOf(version) != SUPPORTED_VERSION) {
            throw new QueryDocumentException(Label.Core_Find_ErrorInvalidDocument);
        }
        document.logic = text(filter.get('logic'));
        Integer fallbackId = 0;
        for (Object entry : asList(filter.get('conditions'))) {
            fallbackId++;
            Map<String, Object> raw = (Map<String, Object>) entry;
            Condition condition = new Condition();
            condition.id = raw.get('id') == null
                ? String.valueOf(fallbackId)
                : String.valueOf(raw.get('id'));
            condition.field = text(raw.get('field'));
            condition.operator = text(raw.get('operator'))?.toLowerCase();
            condition.value = raw.get('value');
            condition.relative = text(raw.get('relative'))?.toUpperCase();
            Object n = raw.get('n');
            condition.n = n == null || String.isBlank(String.valueOf(n))
                ? null
                : Integer.valueOf(String.valueOf(n));
            document.conditions.add(condition);
        }
    }

    private void checkLimits() {
        Integer listValues = 0;
        for (Condition condition : conditions) {
            if (condition.value instanceof List<Object>) {
                List<Object> values = (List<Object>) condition.value;
                listValues = Math.max(listValues, values.size());
                for (Object value : values) {
                    checkValueLength(value);
                }
            } else {
                checkValueLength(condition.value);
            }
        }
        if (
            fields.size() > MAX_FIELDS ||
            conditions.size() > MAX_CONDITIONS ||
            orderBy.size() > MAX_SORT_FIELDS ||
            listValues > MAX_LIST_VALUES
        ) {
            throw new QueryDocumentException(Label.Core_Find_ErrorTooBig);
        }
    }

    private static void checkValueLength(Object value) {
        if (value instanceof Map<String, Object> || value instanceof List<Object>) {
            // A nested list or an object where a value belongs is not a value.
            throw new QueryDocumentException(Label.Core_Find_ErrorInvalidDocument);
        }
        if (value != null && String.valueOf(value).length() > MAX_VALUE_LENGTH) {
            throw new QueryDocumentException(Label.Core_Find_ErrorTooBig);
        }
    }

    private static List<Object> asList(Object raw) {
        if (raw == null) {
            return new List<Object>();
        }
        return (List<Object>) raw;
    }

    private static String text(Object raw) {
        return raw == null ? null : String.valueOf(raw).trim();
    }
}

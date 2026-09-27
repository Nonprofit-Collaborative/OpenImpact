/**
 * Turns a query document (canonical model Section 17B) into SOQL that runs in user mode, and
 * renders the same query for display. The security review notes in ADR-0047 (amended) are the
 * specification of this class; each rule below is one of them.
 *
 * 1. **Names come from describe (R-Q1).** The object, every relationship on a path and every
 *    field are looked up in the running user's own describe results and refused when they are
 *    not there or not readable. The query is written with the names describe returned, never
 *    with the text the document carried.
 * 2. **Values are bound (R-Q3).** Every value, the row limit, the export cursor and the ids a
 *    bulk update re-reads are bind variables. The only text a person typed that reaches the
 *    displayed query is escaped there, and the displayed query is never run.
 * 3. **Operators and logic are fixed lists.** An operator must be one R-R2 defines and must
 *    suit the field's type; the logic string may hold only condition numbers, brackets, AND, OR
 *    and NOT, in a shape SOQL accepts.
 *
 * This class runs nothing. `QuerySelector` runs what it returns, in user mode.
 */
@NamespaceAccessible
public with sharing class QueryCompiler {
    /** Raised with a sentence the person who built the query can act on. */
    @NamespaceAccessible
    public class QueryCompilerException extends Exception {
    }

    /** How many relationships a path may follow (R-Q1). */
    @NamespaceAccessible
    public static final Integer MAX_DEPTH = 2;
    /** The longest N of LAST_N_DAYS and NEXT_N_DAYS (R-Q2). */
    private static final Integer MAX_RELATIVE_DAYS = 3650;
    private static final Integer MAX_MESSAGE_NAME = 80;

    private static final Pattern IDENTIFIER = Pattern.compile('^[A-Za-z][A-Za-z0-9_]{0,79}$');
    private static final Pattern DATE_VALUE = Pattern.compile('^\\d{4}-\\d{2}-\\d{2}$');
    private static final Pattern DATETIME_VALUE = Pattern.compile(
        '^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}(:\\d{2}(\\.\\d{1,3})?)?(Z|[+-]\\d{2}:\\d{2})$'
    );
    private static final Pattern LOGIC_TOKEN = Pattern.compile('^(\\d{1,3}|AND|OR|NOT|\\(|\\))$');

    @NamespaceAccessible
    public static final String OP_EQUALS = 'equals';
    @NamespaceAccessible
    public static final String OP_NOT_EQUALS = 'not equals';
    @NamespaceAccessible
    public static final String OP_LESS = 'less than';
    @NamespaceAccessible
    public static final String OP_LESS_EQUAL = 'less or equal';
    @NamespaceAccessible
    public static final String OP_GREATER = 'greater than';
    @NamespaceAccessible
    public static final String OP_GREATER_EQUAL = 'greater or equal';
    @NamespaceAccessible
    public static final String OP_CONTAINS = 'contains';
    @NamespaceAccessible
    public static final String OP_NOT_CONTAINS = 'does not contain';
    @NamespaceAccessible
    public static final String OP_STARTS = 'starts with';
    @NamespaceAccessible
    public static final String OP_NULL = 'is null';
    @NamespaceAccessible
    public static final String OP_NOT_NULL = 'is not null';
    @NamespaceAccessible
    public static final String OP_IN = 'in';
    @NamespaceAccessible
    public static final String OP_NOT_IN = 'not in';

    private static final Map<String, String> COMPARISON = new Map<String, String>{
        OP_EQUALS => '=',
        OP_NOT_EQUALS => '!=',
        OP_LESS => '<',
        OP_LESS_EQUAL => '<=',
        OP_GREATER => '>',
        OP_GREATER_EQUAL => '>='
    };
    private static final Set<String> NULL_OPERATORS = new Set<String>{ OP_NULL, OP_NOT_NULL };
    private static final Set<String> LIKE_OPERATORS = new Set<String>{
        OP_CONTAINS,
        OP_NOT_CONTAINS,
        OP_STARTS
    };
    private static final Set<String> LIST_OPERATORS = new Set<String>{ OP_IN, OP_NOT_IN };
    private static final Set<String> ORDER_OPERATORS = new Set<String>{
        OP_LESS,
        OP_LESS_EQUAL,
        OP_GREATER,
        OP_GREATER_EQUAL
    };
    /** The R-Q2 periods. */
    @NamespaceAccessible
    public static final Set<String> RELATIVE_PERIODS = new Set<String>{
        'TODAY',
        'THIS_MONTH',
        'LAST_MONTH',
        'THIS_YEAR',
        'LAST_YEAR',
        'LAST_N_DAYS',
        'NEXT_N_DAYS'
    };

    private static final Set<Schema.DisplayType> TEXT_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.STRING,
        Schema.DisplayType.TEXTAREA,
        Schema.DisplayType.EMAIL,
        Schema.DisplayType.PHONE,
        Schema.DisplayType.URL,
        Schema.DisplayType.COMBOBOX
    };
    private static final Set<Schema.DisplayType> NUMBER_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.INTEGER,
        Schema.DisplayType.LONG,
        Schema.DisplayType.DOUBLE,
        Schema.DisplayType.CURRENCY,
        Schema.DisplayType.PERCENT
    };
    private static final Set<Schema.DisplayType> ID_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.ID,
        Schema.DisplayType.REFERENCE
    };

    /** Set only by tests, so a relative period can be asserted on a fixed day. */
    @TestVisible
    private static Date todayForTest;

    private static Map<String, Schema.SObjectType> globalDescribe;
    private static final Map<Schema.SObjectType, Map<String, Schema.SObjectField>> FIELDS = new Map<Schema.SObjectType, Map<String, Schema.SObjectField>>();
    private static final Map<Schema.SObjectType, Map<String, Schema.SObjectField>> RELATIONSHIPS = new Map<Schema.SObjectType, Map<String, Schema.SObjectField>>();

    /** A field reached from the query's object, possibly through relationships. */
    @NamespaceAccessible
    public class ResolvedField {
        /** The path as describe spells it, for example `Account.Owner.Name`. */
        @NamespaceAccessible
        public String path;
        /** The relationship names followed, in order; empty for the object's own field. */
        @NamespaceAccessible
        public List<String> relationships = new List<String>();
        /** The label a person reads, for example `Account > Owner > Full Name`. */
        @NamespaceAccessible
        public String label;
        @NamespaceAccessible
        public Schema.SObjectField token;
        @NamespaceAccessible
        public Schema.DescribeFieldResult describe;

        /** The value this field holds on one queried record, through its relationships. */
        @NamespaceAccessible
        public Object valueOn(SObject record) {
            SObject current = record;
            for (String relationship : relationships) {
                if (current == null) {
                    return null;
                }
                current = current.getSObject(relationship);
            }
            return current == null ? null : current.get(describe.getName());
        }
    }

    /** One column as the grid and the export show it. */
    @NamespaceAccessible
    public class Column {
        @AuraEnabled
        public String path;
        @AuraEnabled
        public String label;
        /** The describe type in lower case, for example `string`, `date`, `currency`. */
        @AuraEnabled
        public String type;
    }

    /** One query ready to run: its text, with binds only, and the binds. */
    @NamespaceAccessible
    public class Query {
        @NamespaceAccessible
        public String soql;
        @NamespaceAccessible
        public Map<String, Object> binds;
    }

    /** A compiled document: everything a query over it needs. */
    @NamespaceAccessible
    public class Compiled {
        @NamespaceAccessible
        public String objectName;
        @NamespaceAccessible
        public Schema.SObjectType objectType;
        /** The fields read, the record identifier first. */
        @NamespaceAccessible
        public List<ResolvedField> fields = new List<ResolvedField>();
        @NamespaceAccessible
        public Integer rowLimit;
        public String selectList;
        public String filterClause = '';
        public String displayFilter = '';
        public String orderClause = '';
        public Map<String, Object> filterBinds = new Map<String, Object>();

        @NamespaceAccessible
        public List<Column> columns() {
            List<Column> result = new List<Column>();
            for (ResolvedField field : fields) {
                Column column = new Column();
                column.path = field.path;
                column.label = field.label;
                column.type = field.describe.getType().name().toLowerCase();
                result.add(column);
            }
            return result;
        }

        /** The rows the grid shows: the document's order, at most `maxRows` of them. */
        @NamespaceAccessible
        public Query rows(Integer maxRows) {
            Query query = base(selectList);
            query.soql += whereClause(null) + orderClause + ' LIMIT :rowLimit';
            query.binds.put('rowLimit', effectiveLimit(maxRows));
            return query;
        }

        /** A count of the matching records, reading at most `cap` of them (R-Q4). */
        @NamespaceAccessible
        public Query count(Integer cap) {
            Query query = base(null);
            query.soql += whereClause(null) + ' LIMIT :countCap';
            query.binds.put('countCap', Math.max(cap, 1));
            return query;
        }

        /**
         * One page of an export (R-Q5): in record identifier order, after the last identifier
         * the previous page returned, so no row is skipped or repeated while others edit.
         */
        @NamespaceAccessible
        public Query exportPage(Id afterId, Integer pageSize) {
            Query query = base(selectList);
            String cursor = afterId == null ? null : 'Id > :afterId';
            if (afterId != null) {
                query.binds.put('afterId', afterId);
            }
            query.soql += whereClause(cursor) + ' ORDER BY Id ASC LIMIT :pageSize';
            query.binds.put('pageSize', Math.max(pageSize, 1));
            return query;
        }

        /**
         * The records a bulk update would change, in record identifier order, with the fields
         * it reads. `extraFields` are names the caller took from this object's own describe.
         */
        @NamespaceAccessible
        public Query forUpdate(Set<String> extraFields, Integer maxRecords) {
            Query query = base(selectFor(extraFields));
            query.soql += whereClause(null) + ' ORDER BY Id ASC LIMIT :maxRecords';
            query.binds.put('maxRecords', Math.max(maxRecords, 1));
            return query;
        }

        /** Those of `recordIds` that still match the filter, with the fields named. */
        @NamespaceAccessible
        public Query stillMatching(Set<String> extraFields, Set<Id> recordIds) {
            Query query = base(selectFor(extraFields));
            query.binds.put('recordIds', recordIds);
            query.soql += whereClause('Id IN :recordIds');
            return query;
        }

        /** The query as the administrator reads it, with every value written out (R-Q3). */
        @NamespaceAccessible
        public String display(Integer maxRows) {
            return 'SELECT ' +
                selectList +
                ' FROM ' +
                objectName +
                (String.isBlank(displayFilter) ? '' : ' WHERE ' + displayFilter) +
                orderClause +
                ' LIMIT ' +
                effectiveLimit(maxRows);
        }

        private Integer effectiveLimit(Integer maxRows) {
            Integer ceiling = maxRows == null || maxRows < 1 ? 1 : maxRows;
            return rowLimit == null ? ceiling : Math.min(rowLimit, ceiling);
        }

        private String selectFor(Set<String> extraFields) {
            Set<String> names = new Set<String>{ 'Id' };
            List<String> ordered = new List<String>{ 'Id' };
            Map<String, Schema.SObjectField> own = fieldsOf(objectType);
            for (String name : extraFields == null ? new Set<String>() : extraFields) {
                Schema.SObjectField token = String.isBlank(name)
                    ? null
                    : own.get(name.toLowerCase());
                if (token == null) {
                    throw new QueryCompilerException(Label.Core_Find_ErrorInvalidDocument);
                }
                String described = token.getDescribe().getName();
                if (!names.contains(described.toLowerCase())) {
                    names.add(described.toLowerCase());
                    ordered.add(described);
                }
            }
            return String.join(ordered, ', ');
        }

        private Query base(String selected) {
            Query query = new Query();
            query.binds = new Map<String, Object>(filterBinds);
            query.soql =
                'SELECT ' +
                (selected == null ? 'COUNT()' : selected) +
                ' FROM ' +
                objectName;
            return query;
        }

        private String whereClause(String extra) {
            List<String> parts = new List<String>();
            if (String.isNotBlank(filterClause)) {
                parts.add('(' + filterClause + ')');
            }
            if (String.isNotBlank(extra)) {
                parts.add(extra);
            }
            return parts.isEmpty() ? '' : ' WHERE ' + String.join(parts, ' AND ');
        }
    }

    /**
     * Compiles a document for the running user. Every name, operator and value is checked
     * here, so a document that compiles can only fail to run where the platform itself
     * refuses (a limit, or access that changed in between).
     */
    @NamespaceAccessible
    public static Compiled compile(QueryDocument document) {
        if (document == null) {
            throw new QueryCompilerException(Label.Core_Find_ErrorInvalidDocument);
        }
        Compiled compiled = new Compiled();
        compiled.objectType = resolveObject(document.objectName);
        compiled.objectName = compiled.objectType.getDescribe(SObjectDescribeOptions.DEFERRED)
            .getName();
        compiled.rowLimit = document.rowLimit;

        Set<String> seen = new Set<String>();
        List<String> selected = new List<String>();
        List<String> wanted = new List<String>{ 'Id' };
        wanted.addAll(document.fields);
        for (String path : wanted) {
            ResolvedField field = resolvePath(compiled.objectType, path);
            if (!isShowable(field.describe)) {
                throw new QueryCompilerException(
                    String.format(Label.Core_Find_ErrorNotShowable, new List<String>{ field.label })
                );
            }
            if (seen.contains(field.path.toLowerCase())) {
                continue;
            }
            seen.add(field.path.toLowerCase());
            compiled.fields.add(field);
            selected.add(field.path);
        }
        compiled.selectList = String.join(selected, ', ');

        FilterRender render = new FilterRender();
        Map<String, String[]> clauseById = new Map<String, String[]>();
        List<String> order = new List<String>();
        for (QueryDocument.Condition condition : document.conditions) {
            if (clauseById.containsKey(condition.id)) {
                throw new QueryCompilerException(Label.Core_Find_ErrorLogic);
            }
            clauseById.put(condition.id, render.condition(compiled.objectType, condition));
            order.add(condition.id);
        }
        compiled.filterBinds = render.binds;
        if (!order.isEmpty()) {
            String[] rendered = String.isBlank(document.logic)
                ? joinAll(order, clauseById)
                : renderLogic(document.logic, clauseById);
            compiled.filterClause = rendered[0];
            compiled.displayFilter = rendered[1];
        }

        List<String> sorts = new List<String>();
        for (QueryDocument.SortField sortField : document.orderBy) {
            ResolvedField field = resolvePath(compiled.objectType, sortField.field);
            if (!field.describe.isSortable()) {
                throw new QueryCompilerException(
                    String.format(Label.Core_Find_ErrorNotSortable, new List<String>{ field.label })
                );
            }
            sorts.add(
                field.path +
                    (sortField.descending == true ? ' DESC' : ' ASC') +
                    (sortField.nullsFirst == true ? ' NULLS FIRST' : ' NULLS LAST')
            );
        }
        compiled.orderClause = sorts.isEmpty() ? '' : ' ORDER BY ' + String.join(sorts, ', ');
        return compiled;
    }

    /**
     * The object a document names, when the running user may read and query it. Anything else,
     * including a name that is not an identifier, is refused with the same sentence, so the
     * answer does not tell anybody which objects exist that they cannot see.
     */
    @NamespaceAccessible
    public static Schema.SObjectType resolveObject(String name) {
        if (String.isBlank(name) || !IDENTIFIER.matcher(name).matches()) {
            throw new QueryCompilerException(Label.Core_Find_ErrorUnknownObject);
        }
        if (globalDescribe == null) {
            globalDescribe = Schema.getGlobalDescribe();
        }
        Schema.SObjectType type = globalDescribe.get(name.toLowerCase());
        if (type == null) {
            throw new QueryCompilerException(Label.Core_Find_ErrorUnknownObject);
        }
        Schema.DescribeSObjectResult described = type.getDescribe(SObjectDescribeOptions.DEFERRED);
        if (!described.isAccessible() || !described.isQueryable()) {
            throw new QueryCompilerException(Label.Core_Find_ErrorUnknownObject);
        }
        return type;
    }

    /**
     * A path from `root`: at most two relationships and then a field, every step readable by
     * the running user, and never a relationship that may point at more than one kind of
     * record (R-Q1).
     */
    @NamespaceAccessible
    public static ResolvedField resolvePath(Schema.SObjectType root, String path) {
        String objectLabel = root.getDescribe(SObjectDescribeOptions.DEFERRED).getLabel();
        if (String.isBlank(path)) {
            throw unknownField(path, objectLabel);
        }
        List<String> parts = path.trim().split('\\.');
        if (parts.size() > MAX_DEPTH + 1) {
            throw new QueryCompilerException(
                String.format(Label.Core_Find_ErrorPath, new List<String>{ shortName(path) })
            );
        }
        ResolvedField resolved = new ResolvedField();
        List<String> labels = new List<String>();
        Schema.SObjectType current = root;
        for (Integer i = 0; i < parts.size() - 1; i++) {
            String segment = parts[i];
            if (!IDENTIFIER.matcher(segment).matches()) {
                throw unknownField(path, objectLabel);
            }
            Schema.SObjectField reference = relationshipsOf(current).get(segment.toLowerCase());
            if (reference == null) {
                throw unknownField(path, objectLabel);
            }
            Schema.DescribeFieldResult described = reference.getDescribe();
            List<Schema.SObjectType> targets = described.getReferenceTo();
            if (!described.isAccessible()) {
                throw unknownField(path, objectLabel);
            }
            if (targets.size() != 1) {
                throw new QueryCompilerException(
                    String.format(Label.Core_Find_ErrorPath, new List<String>{ shortName(path) })
                );
            }
            if (!targets[0].getDescribe(SObjectDescribeOptions.DEFERRED).isAccessible()) {
                throw unknownField(path, objectLabel);
            }
            resolved.relationships.add(described.getRelationshipName());
            labels.add(relationshipLabel(described));
            current = targets[0];
        }
        String last = parts[parts.size() - 1];
        if (!IDENTIFIER.matcher(last).matches()) {
            throw unknownField(path, objectLabel);
        }
        Schema.SObjectField token = fieldsOf(current).get(last.toLowerCase());
        if (token == null) {
            throw unknownField(path, objectLabel);
        }
        Schema.DescribeFieldResult described = token.getDescribe();
        if (!described.isAccessible()) {
            throw unknownField(path, objectLabel);
        }
        resolved.token = token;
        resolved.describe = described;
        labels.add(described.getLabel());
        List<String> names = new List<String>(resolved.relationships);
        names.add(described.getName());
        resolved.path = String.join(names, '.');
        resolved.label = String.join(labels, ' > ');
        return resolved;
    }

    /**
     * Whether a field can be a column: not a compound address or location, whose parts are
     * columns of their own, and not a file body.
     */
    @NamespaceAccessible
    public static Boolean isShowable(Schema.DescribeFieldResult field) {
        Schema.DisplayType kind = field.getType();
        return kind != Schema.DisplayType.ADDRESS &&
            kind != Schema.DisplayType.LOCATION &&
            kind != Schema.DisplayType.BASE64;
    }

    /** The object's fields by lower-case API name, described once per transaction. */
    @NamespaceAccessible
    public static Map<String, Schema.SObjectField> fieldsOf(Schema.SObjectType type) {
        if (!FIELDS.containsKey(type)) {
            FIELDS.put(type, type.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap());
        }
        return FIELDS.get(type);
    }

    /** The object's lookups by lower-case relationship name, described once per transaction. */
    @NamespaceAccessible
    public static Map<String, Schema.SObjectField> relationshipsOf(Schema.SObjectType type) {
        if (!RELATIONSHIPS.containsKey(type)) {
            Map<String, Schema.SObjectField> byName = new Map<String, Schema.SObjectField>();
            for (Schema.SObjectField token : fieldsOf(type).values()) {
                Schema.DescribeFieldResult described = token.getDescribe();
                if (
                    described.getType() == Schema.DisplayType.REFERENCE &&
                    String.isNotBlank(described.getRelationshipName())
                ) {
                    byName.put(described.getRelationshipName().toLowerCase(), token);
                }
            }
            RELATIONSHIPS.put(type, byName);
        }
        return RELATIONSHIPS.get(type);
    }

    /** A lookup's label without the trailing " ID" the platform adds, for example "Account". */
    @NamespaceAccessible
    public static String relationshipLabel(Schema.DescribeFieldResult reference) {
        String label = reference.getLabel();
        return label.endsWith(' ID') ? label.removeEnd(' ID') : label;
    }

    /** The day the relative periods are measured from, in the running user's time zone. */
    @NamespaceAccessible
    public static Date today() {
        return todayForTest == null ? Date.today() : todayForTest;
    }

    // -------------------------------------------------------------------------------------
    // Conditions
    // -------------------------------------------------------------------------------------

    /** Renders conditions, numbering their binds as it goes. */
    private class FilterRender {
        public Map<String, Object> binds = new Map<String, Object>();
        public Integer counter = 0;

        /** The condition as [clause with binds, clause for display]. */
        public String[] condition(Schema.SObjectType root, QueryDocument.Condition condition) {
            ResolvedField field = resolvePath(root, condition.field);
            String operator = condition.operator == null ? '' : condition.operator.trim();
            if (!field.describe.isFilterable()) {
                throw new QueryCompilerException(
                    String.format(
                        Label.Core_Find_ErrorNotFilterable,
                        new List<String>{ field.label }
                    )
                );
            }
            if (!allowed(field.describe.getType(), operator, condition)) {
                throw new QueryCompilerException(
                    String.format(
                        Label.Core_Find_ErrorOperator,
                        new List<String>{ shortName(condition.id), field.label }
                    )
                );
            }
            String lhs = field.path;
            if (operator == OP_NULL) {
                return pair(lhs + ' = null');
            }
            if (operator == OP_NOT_NULL) {
                return pair(lhs + ' != null');
            }
            Schema.DisplayType kind = field.describe.getType();
            Range period = rangeFor(kind, condition, field.label);
            if (period != null) {
                return rangeClause(lhs, operator, period);
            }
            if (LIST_OPERATORS.contains(operator)) {
                List<Object> raw = condition.value instanceof List<Object>
                    ? (List<Object>) condition.value
                    : new List<Object>{ condition.value };
                if (raw.isEmpty()) {
                    throw badValue(condition, field);
                }
                Object typedList = typedList(kind, raw, condition, field);
                List<String> shown = new List<String>();
                for (Object value : (List<Object>) typedList) {
                    shown.add(literal(value));
                }
                String name = bind(typedList);
                String sql = operator == OP_IN ? ' IN ' : ' NOT IN ';
                return new List<String>{
                    lhs +
                    sql +
                    ':' +
                    name,
                    lhs +
                    sql +
                    '(' +
                    String.join(shown, ', ') +
                    ')'
                };
            }
            if (LIKE_OPERATORS.contains(operator)) {
                String text = condition.value == null ? '' : String.valueOf(condition.value);
                if (String.isEmpty(text)) {
                    throw badValue(condition, field);
                }
                String pattern = operator == OP_STARTS
                    ? escapeLike(text) + '%'
                    : '%' + escapeLike(text) + '%';
                String name = bind(pattern);
                if (operator == OP_NOT_CONTAINS) {
                    return new List<String>{
                        '(NOT ' +
                        lhs +
                        ' LIKE :' +
                        name +
                        ')',
                        '(NOT ' +
                        lhs +
                        ' LIKE ' +
                        literal(pattern) +
                        ')'
                    };
                }
                return new List<String>{
                    lhs +
                    ' LIKE :' +
                    name,
                    lhs +
                    ' LIKE ' +
                    literal(pattern)
                };
            }
            Object typed = typedValue(kind, condition.value, condition, field);
            String name = bind(typed);
            String comparison = COMPARISON.get(operator);
            return new List<String>{
                lhs +
                ' ' +
                comparison +
                ' :' +
                name,
                lhs +
                ' ' +
                comparison +
                ' ' +
                literal(typed)
            };
        }

        public String bind(Object value) {
            String name = 'b' + counter;
            counter++;
            binds.put(name, value);
            return name;
        }

        /** A period as a comparison: dates inclusive of both ends, times up to the next day. */
        public String[] rangeClause(String lhs, String operator, Range period) {
            String start = bind(period.start);
            String finish = bind(period.finish);
            String startShown = literal(period.start);
            String finishShown = literal(period.finish);
            // A date's period ends on its last day; a date and time's ends at the start of the
            // day after, so the comparison with its end is strict.
            String upTo = period.isDatetime ? ' < ' : ' <= ';
            String beyond = period.isDatetime ? ' >= ' : ' > ';
            switch on operator {
                when 'equals' {
                    return new List<String>{
                        '(' +
                        lhs +
                        ' >= :' +
                        start +
                        ' AND ' +
                        lhs +
                        upTo +
                        ':' +
                        finish +
                        ')',
                        '(' +
                        lhs +
                        ' >= ' +
                        startShown +
                        ' AND ' +
                        lhs +
                        upTo +
                        finishShown +
                        ')'
                    };
                }
                when 'not equals' {
                    return new List<String>{
                        '(' +
                        lhs +
                        ' < :' +
                        start +
                        ' OR ' +
                        lhs +
                        beyond +
                        ':' +
                        finish +
                        ')',
                        '(' +
                        lhs +
                        ' < ' +
                        startShown +
                        ' OR ' +
                        lhs +
                        beyond +
                        finishShown +
                        ')'
                    };
                }
                when 'less than' {
                    return new List<String>{ lhs + ' < :' + start, lhs + ' < ' + startShown };
                }
                when 'greater or equal' {
                    return new List<String>{ lhs + ' >= :' + start, lhs + ' >= ' + startShown };
                }
                when 'less or equal' {
                    return new List<String>{ lhs + upTo + ':' + finish, lhs + upTo + finishShown };
                }
                when else {
                    return new List<String>{
                        lhs +
                        beyond +
                        ':' +
                        finish,
                        lhs +
                        beyond +
                        finishShown
                    };
                }
            }
        }
    }

    /** A period to compare with: its first moment and its end (see `rangeClause`). */
    private class Range {
        public Object start;
        public Object finish;
        public Boolean isDatetime = false;
    }

    /**
     * The period a condition compares with, or null for an ordinary value. A relative period
     * (R-Q2) is one; so is a plain date given for a date and time field, which means that day.
     */
    private static Range rangeFor(
        Schema.DisplayType kind,
        QueryDocument.Condition condition,
        String fieldLabel
    ) {
        Boolean isDate = kind == Schema.DisplayType.DATE;
        Boolean isDatetime = kind == Schema.DisplayType.DATETIME;
        Date first;
        Date last;
        if (String.isNotBlank(condition.relative)) {
            Date today = today();
            Integer n = condition.n;
            switch on condition.relative {
                when 'TODAY' {
                    first = today;
                    last = today;
                }
                when 'THIS_MONTH' {
                    first = today.toStartOfMonth();
                    last = first.addMonths(1).addDays(-1);
                }
                when 'LAST_MONTH' {
                    first = today.toStartOfMonth().addMonths(-1);
                    last = today.toStartOfMonth().addDays(-1);
                }
                when 'THIS_YEAR' {
                    first = Date.newInstance(today.year(), 1, 1);
                    last = Date.newInstance(today.year(), 12, 31);
                }
                when 'LAST_YEAR' {
                    first = Date.newInstance(today.year() - 1, 1, 1);
                    last = Date.newInstance(today.year() - 1, 12, 31);
                }
                when 'LAST_N_DAYS', 'NEXT_N_DAYS' {
                    if (n == null || n < 1 || n > MAX_RELATIVE_DAYS) {
                        throw new QueryCompilerException(
                            String.format(
                                Label.Core_Find_ErrorBadValue,
                                new List<String>{ shortName(condition.id), fieldLabel }
                            )
                        );
                    }
                    first = condition.relative == 'LAST_N_DAYS' ? today.addDays(-(n - 1)) : today;
                    last = condition.relative == 'LAST_N_DAYS' ? today : today.addDays(n - 1);
                }
            }
        } else if (isDatetime && condition.value != null) {
            String text = String.valueOf(condition.value).trim();
            if (!DATE_VALUE.matcher(text).matches()) {
                return null;
            }
            first = parseDate(text, condition, fieldLabel);
            last = first;
        } else {
            return null;
        }
        Range period = new Range();
        period.isDatetime = isDatetime;
        if (isDatetime) {
            period.start = Datetime.newInstance(first, Time.newInstance(0, 0, 0, 0));
            period.finish = Datetime.newInstance(last.addDays(1), Time.newInstance(0, 0, 0, 0));
        } else if (isDate) {
            period.start = first;
            period.finish = last;
        }
        return period;
    }

    /** Whether an operator suits a field of this type (and a relative period its operator). */
    private static Boolean allowed(
        Schema.DisplayType kind,
        String operator,
        QueryDocument.Condition condition
    ) {
        Boolean isDateKind = kind == Schema.DisplayType.DATE || kind == Schema.DisplayType.DATETIME;
        if (String.isNotBlank(condition.relative)) {
            return isDateKind &&
                RELATIVE_PERIODS.contains(condition.relative) &&
                (COMPARISON.containsKey(operator));
        }
        if (NULL_OPERATORS.contains(operator)) {
            return kind != Schema.DisplayType.BOOLEAN;
        }
        if (kind == Schema.DisplayType.BOOLEAN || kind == Schema.DisplayType.MULTIPICKLIST) {
            return operator == OP_EQUALS || operator == OP_NOT_EQUALS;
        }
        if (ID_TYPES.contains(kind)) {
            return operator == OP_EQUALS ||
                operator == OP_NOT_EQUALS ||
                LIST_OPERATORS.contains(operator);
        }
        if (kind == Schema.DisplayType.PICKLIST) {
            return operator == OP_EQUALS ||
                operator == OP_NOT_EQUALS ||
                LIST_OPERATORS.contains(operator) ||
                LIKE_OPERATORS.contains(operator);
        }
        if (TEXT_TYPES.contains(kind)) {
            return COMPARISON.containsKey(operator) ||
                LIST_OPERATORS.contains(operator) ||
                LIKE_OPERATORS.contains(operator);
        }
        if (NUMBER_TYPES.contains(kind) || isDateKind) {
            return COMPARISON.containsKey(operator) || LIST_OPERATORS.contains(operator);
        }
        return false;
    }

    /** One value as the field's own type, so the bind compares like with like. */
    @TestVisible
    private static Object typedValue(
        Schema.DisplayType kind,
        Object raw,
        QueryDocument.Condition condition,
        ResolvedField field
    ) {
        if (raw == null || String.isBlank(String.valueOf(raw))) {
            throw badValue(condition, field);
        }
        String text = String.valueOf(raw).trim();
        try {
            if (kind == Schema.DisplayType.BOOLEAN) {
                if (raw instanceof Boolean) {
                    return raw;
                }
                if (text.equalsIgnoreCase('true') || text.equalsIgnoreCase('false')) {
                    return Boolean.valueOf(text);
                }
                throw badValue(condition, field);
            }
            if (kind == Schema.DisplayType.INTEGER) {
                return Integer.valueOf(wholeNumber(text));
            }
            if (kind == Schema.DisplayType.LONG) {
                return Long.valueOf(wholeNumber(text));
            }
            if (NUMBER_TYPES.contains(kind)) {
                return Decimal.valueOf(text);
            }
            if (kind == Schema.DisplayType.DATE) {
                return parseDate(text, condition, field.label);
            }
            if (kind == Schema.DisplayType.DATETIME) {
                if (!DATETIME_VALUE.matcher(text).matches()) {
                    throw badValue(condition, field);
                }
                return (Datetime) JSON.deserialize('"' + text + '"', Datetime.class);
            }
            if (ID_TYPES.contains(kind)) {
                return Id.valueOf(text);
            }
        } catch (QueryCompilerException known) {
            throw known;
        } catch (Exception unreadable) {
            throw badValue(condition, field);
        }
        // Text, picklists and the rest are compared as the text given, untrimmed.
        return String.valueOf(raw);
    }

    /** A list of values as a list of the field's own type, which a bind to IN needs. */
    private static Object typedList(
        Schema.DisplayType kind,
        List<Object> raw,
        QueryDocument.Condition condition,
        ResolvedField field
    ) {
        List<Object> typed = new List<Object>();
        for (Object value : raw) {
            typed.add(typedValue(kind, value, condition, field));
        }
        if (kind == Schema.DisplayType.INTEGER) {
            List<Integer> result = new List<Integer>();
            for (Object value : typed) {
                result.add((Integer) value);
            }
            return result;
        }
        if (kind == Schema.DisplayType.LONG) {
            List<Long> result = new List<Long>();
            for (Object value : typed) {
                result.add((Long) value);
            }
            return result;
        }
        if (NUMBER_TYPES.contains(kind)) {
            List<Decimal> result = new List<Decimal>();
            for (Object value : typed) {
                result.add((Decimal) value);
            }
            return result;
        }
        if (kind == Schema.DisplayType.DATE) {
            List<Date> result = new List<Date>();
            for (Object value : typed) {
                result.add((Date) value);
            }
            return result;
        }
        if (kind == Schema.DisplayType.DATETIME) {
            List<Datetime> result = new List<Datetime>();
            for (Object value : typed) {
                result.add((Datetime) value);
            }
            return result;
        }
        if (ID_TYPES.contains(kind)) {
            List<Id> result = new List<Id>();
            for (Object value : typed) {
                result.add((Id) value);
            }
            return result;
        }
        List<String> result = new List<String>();
        for (Object value : typed) {
            result.add((String) value);
        }
        return result;
    }

    private static String wholeNumber(String text) {
        Decimal value = Decimal.valueOf(text);
        if (value.scale() > 0 && value != value.setScale(0, System.RoundingMode.DOWN)) {
            throw new IllegalArgumentException();
        }
        return String.valueOf(value.setScale(0).longValue());
    }

    private static Date parseDate(
        String text,
        QueryDocument.Condition condition,
        String fieldLabel
    ) {
        if (!DATE_VALUE.matcher(text).matches()) {
            throw new QueryCompilerException(
                String.format(
                    Label.Core_Find_ErrorBadValue,
                    new List<String>{ shortName(condition.id), fieldLabel }
                )
            );
        }
        try {
            Date parsed = Date.valueOf(text);
            // Date.valueOf rolls an impossible day into the next month; refuse it instead.
            if (String.valueOf(parsed) != text) {
                throw new IllegalArgumentException();
            }
            return parsed;
        } catch (Exception unreadable) {
            throw new QueryCompilerException(
                String.format(
                    Label.Core_Find_ErrorBadValue,
                    new List<String>{ shortName(condition.id), fieldLabel }
                )
            );
        }
    }

    /** A LIKE pattern's own wildcards, escaped so what was typed is matched as typed. */
    @TestVisible
    private static String escapeLike(String text) {
        return text.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
    }

    /** A value written out for the displayed query only. Never run. */
    @TestVisible
    private static String literal(Object value) {
        if (value == null) {
            return 'null';
        }
        if (value instanceof Datetime) {
            return ((Datetime) value).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        }
        if (value instanceof Date) {
            return String.valueOf(value);
        }
        if (value instanceof Decimal) {
            return ((Decimal) value).toPlainString();
        }
        if (
            value instanceof Boolean ||
            value instanceof Integer ||
            value instanceof Long ||
            value instanceof Double
        ) {
            return String.valueOf(value);
        }
        return '\'' + String.escapeSingleQuotes(String.valueOf(value)) + '\'';
    }

    // -------------------------------------------------------------------------------------
    // Logic
    // -------------------------------------------------------------------------------------

    private static String[] joinAll(List<String> order, Map<String, String[]> clauseById) {
        List<String> run = new List<String>();
        List<String> shown = new List<String>();
        for (String id : order) {
            run.add('(' + clauseById.get(id)[0] + ')');
            shown.add('(' + clauseById.get(id)[1] + ')');
        }
        return new List<String>{ String.join(run, ' AND '), String.join(shown, ' AND ') };
    }

    /**
     * Substitutes each condition number in the logic string with its clause, after checking
     * that the string is made only of condition numbers, brackets, AND, OR and NOT, that it
     * names every condition, and that it has a shape SOQL accepts: AND and OR are not mixed
     * without brackets.
     */
    @TestVisible
    private static String[] renderLogic(String logic, Map<String, String[]> clauseById) {
        String spaced = logic.replace('(', ' ( ').replace(')', ' ) ');
        List<String> tokens = new List<String>();
        for (String token : spaced.trim().split('\\s+')) {
            String upper = token.toUpperCase();
            if (!LOGIC_TOKEN.matcher(upper).matches()) {
                throw new QueryCompilerException(Label.Core_Find_ErrorLogic);
            }
            if (upper.isNumeric() && !clauseById.containsKey(upper)) {
                throw new QueryCompilerException(Label.Core_Find_ErrorLogic);
            }
            tokens.add(upper);
        }
        LogicParser parser = new LogicParser(tokens);
        parser.expression();
        if (parser.position != tokens.size() || !parser.used.containsAll(clauseById.keySet())) {
            throw new QueryCompilerException(Label.Core_Find_ErrorLogic);
        }
        List<String> run = new List<String>();
        List<String> shown = new List<String>();
        for (String token : tokens) {
            if (token.isNumeric()) {
                run.add('(' + clauseById.get(token)[0] + ')');
                shown.add('(' + clauseById.get(token)[1] + ')');
            } else {
                run.add(token);
                shown.add(token);
            }
        }
        return new List<String>{ String.join(run, ' '), String.join(shown, ' ') };
    }

    /**
     * expression := factor ((AND factor)* | (OR factor)*)
     * factor := NOT factor | ( expression ) | number
     */
    private class LogicParser {
        public List<String> tokens;
        public Integer position = 0;
        public Set<String> used = new Set<String>();
        public Integer depth = 0;

        public LogicParser(List<String> tokens) {
            this.tokens = tokens;
        }

        public void expression() {
            factor();
            String joiner;
            while (position < tokens.size() && (peek() == 'AND' || peek() == 'OR')) {
                if (joiner != null && joiner != peek()) {
                    throw new QueryCompilerException(Label.Core_Find_ErrorLogic);
                }
                joiner = peek();
                position++;
                factor();
            }
        }

        public void factor() {
            if (position >= tokens.size() || depth > 20) {
                throw new QueryCompilerException(Label.Core_Find_ErrorLogic);
            }
            String token = tokens[position];
            position++;
            if (token == 'NOT') {
                depth++;
                factor();
                depth--;
                return;
            }
            if (token == '(') {
                depth++;
                expression();
                depth--;
                if (position >= tokens.size() || tokens[position] != ')') {
                    throw new QueryCompilerException(Label.Core_Find_ErrorLogic);
                }
                position++;
                return;
            }
            if (!token.isNumeric()) {
                throw new QueryCompilerException(Label.Core_Find_ErrorLogic);
            }
            used.add(token);
        }

        public String peek() {
            return tokens[position];
        }
    }

    // -------------------------------------------------------------------------------------
    // Messages
    // -------------------------------------------------------------------------------------

    private static String[] pair(String clause) {
        return new List<String>{ clause, clause };
    }

    private static QueryCompilerException unknownField(String path, String objectLabel) {
        return new QueryCompilerException(
            String.format(
                Label.Core_Find_ErrorUnknownField,
                new List<String>{ shortName(path), objectLabel }
            )
        );
    }

    private static QueryCompilerException badValue(
        QueryDocument.Condition condition,
        ResolvedField field
    ) {
        return new QueryCompilerException(
            String.format(
                Label.Core_Find_ErrorBadValue,
                new List<String>{ shortName(condition.id), field.label }
            )
        );
    }

    /** Text from the document, shortened before it is repeated back in a message. */
    private static String shortName(String text) {
        return String.isBlank(text) ? '' : text.abbreviate(MAX_MESSAGE_NAME);
    }
}

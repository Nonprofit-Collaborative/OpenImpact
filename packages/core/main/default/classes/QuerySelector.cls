/**
 * Runs what `QueryCompiler` compiled, and nothing else, always in user mode (R-Q4): object
 * access, field access and sharing apply to every record and every value Find, the export and
 * bulk update read.
 */
@NamespaceAccessible
public with sharing class QuerySelector {
    /** The most rows the grid shows from one run. */
    @NamespaceAccessible
    public static final Integer GRID_MAX_ROWS = 2000;
    /** Rows in one export page (R-Q5). A test lowers it to page through fewer records. */
    @TestVisible
    private static Integer exportPageSize = 1000;
    /** Query rows left for everything else in the transaction when a count sizes itself. */
    private static final Integer QUERY_ROW_MARGIN = 500;

    /** One page of an export. */
    @NamespaceAccessible
    public class ExportPage {
        @AuraEnabled
        public List<QueryCompiler.Column> columns;
        @AuraEnabled
        public List<Map<String, Object>> rows = new List<Map<String, Object>>();
        /** The identifier to ask for the next page after, or null when there is none. */
        @AuraEnabled
        public String lastId;
        @AuraEnabled
        public Boolean done = false;
        /** True when the export stopped at the export row limit with rows still to read. */
        @AuraEnabled
        public Boolean stoppedAtLimit = false;
        @AuraEnabled
        public Integer exportLimit;
    }

    /** The records a compiled query returns, in user mode. */
    @NamespaceAccessible
    public static List<SObject> records(QueryCompiler.Query query) {
        return Database.queryWithBinds(query.soql, query.binds, AccessLevel.USER_MODE);
    }

    /** The grid's rows, flattened by column path. */
    @NamespaceAccessible
    public static List<Map<String, Object>> rows(QueryCompiler.Compiled compiled) {
        return flatten(compiled, records(compiled.rows(GRID_MAX_ROWS)));
    }

    /**
     * How many records match, reading at most `cap` of them and never more than the rows the
     * transaction has left, so a count cannot hit the query row limit (R-Q4). The caller
     * compares the answer with `cap` to tell "exactly this many" from "at least this many".
     */
    @NamespaceAccessible
    public static Integer count(QueryCompiler.Compiled compiled, Integer cap) {
        QueryCompiler.Query query = compiled.count(Math.min(cap, countHeadroom()));
        return Database.countQueryWithBinds(query.soql, query.binds, AccessLevel.USER_MODE);
    }

    /** The most records one count in this transaction may read. */
    @NamespaceAccessible
    public static Integer countHeadroom() {
        return Math.max(Limits.getLimitQueryRows() - Limits.getQueryRows() - QUERY_ROW_MARGIN, 1);
    }

    /**
     * One page of an export (R-Q5): after `afterId`, in record identifier order, never past the
     * document's own row limit or the export row limit, counting the rows already exported.
     */
    @NamespaceAccessible
    public static ExportPage exportPage(
        QueryCompiler.Compiled compiled,
        Id afterId,
        Integer alreadyExported
    ) {
        ExportPage page = new ExportPage();
        page.exportLimit = DataManagementSettings.exportRowLimit();
        Integer cap = compiled.rowLimit == null
            ? page.exportLimit
            : Math.min(compiled.rowLimit, page.exportLimit);
        Integer done = alreadyExported == null || alreadyExported < 0 ? 0 : alreadyExported;
        if (afterId == null) {
            page.columns = compiled.columns();
        }
        Integer remaining = cap - done;
        if (remaining <= 0) {
            page.done = true;
            return page;
        }
        Integer size = Math.min(exportPageSize, remaining);
        List<SObject> found = records(compiled.exportPage(afterId, size));
        page.rows = flatten(compiled, found);
        page.lastId = found.isEmpty() ? null : String.valueOf(found[found.size() - 1].Id);
        Boolean naturalEnd = found.size() < size;
        Boolean reachedCap = done + found.size() >= cap;
        page.done = naturalEnd || reachedCap;
        // Stopping at the document's own row limit is what was asked for; stopping at the
        // export row limit with more to read is what the person must be told.
        page.stoppedAtLimit =
            !naturalEnd &&
            reachedCap &&
            (compiled.rowLimit == null ||
            compiled.rowLimit > page.exportLimit);
        return page;
    }

    /** Each record as one map from column path to value. */
    @NamespaceAccessible
    public static List<Map<String, Object>> flatten(
        QueryCompiler.Compiled compiled,
        List<SObject> records
    ) {
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (SObject record : records) {
            Map<String, Object> row = new Map<String, Object>();
            for (QueryCompiler.ResolvedField field : compiled.fields) {
                row.put(field.path, field.valueOn(record));
            }
            result.add(row);
        }
        return result;
    }
}

/**
 * The seam a dependent package implements to resolve the row entities Core cannot (R-IR6).
 *
 * A row can describe a gift, its allocations and a soft credit, and those objects live in the
 * Giving package, which depends on Core: Core may not reference them (ADR-0014). Rather than
 * leave those columns unloadable forever, or move the importer out of Core, the processor
 * looks for an implementation of this interface by name with `Type.forName`, which is the
 * cross-package mechanism ADR-0017 settled on. Where none is installed the columns stay on
 * the staged row and the run log says so; no row is ever rejected for carrying one.
 *
 * An implementation is called once per chunk, after Core has resolved the organization, the
 * household and the people, and is handed those results so it can point a gift at them. It
 * must be bulk safe, must honor `dryRun` by writing nothing, and must not throw: a failure
 * belongs on the row it came from.
 */
@NamespaceAccessible
public interface ImportEntityProcessor {
    /**
     * Resolves the entities this implementation owns for one chunk.
     *
     * @param batch the import being run, for the batch tag and the chunk size
     * @param mapping the template's mapping document
     * @param rows the staged rows of this chunk, already carrying Core's resolved lookups
     * @param valuesByRowId each row's column values keyed by column name, already trimmed
     * @param dryRun true when nothing may be written
     * @return the message to add to the run log, or null when there is nothing to say
     */
    String resolve(
        Import_Batch__c batch,
        ImportMapping mapping,
        List<Import_Row__c> rows,
        Map<Id, Map<String, String>> valuesByRowId,
        Boolean dryRun
    );
}

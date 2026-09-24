/**
 * What an entity processor did with one chunk (R-IR6): a sentence for the run log, and the
 * total of the gift amounts it read, which the control totals are checked against (R-IB10).
 *
 * The amount is the total of every row that carries a readable amount, rejected or not,
 * because the question a control total asks is whether this is the file on paper. It is null
 * when the processor read no amounts at all, which is different from a file totalling zero.
 */
@NamespaceAccessible
public with sharing class ImportEntityResult {
    /** One sentence for the run log, or null when there is nothing to say. */
    @NamespaceAccessible
    public String note;

    /** The total of the amounts read in this chunk, or null when none was read. */
    @NamespaceAccessible
    public Decimal fileAmount;

    @NamespaceAccessible
    public ImportEntityResult() {
        this.note = null;
        this.fileAmount = null;
    }

    @NamespaceAccessible
    public ImportEntityResult(String note, Decimal fileAmount) {
        this.note = note;
        this.fileAmount = fileAmount;
    }
}

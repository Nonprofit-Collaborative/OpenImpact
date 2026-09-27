/**
 * The mapping document of an import template (canonical model R-IT1): which source column
 * describes which attribute of which row entity, and the values applied to every row that
 * does not carry its own.
 *
 * The document is held as one JSON value per template for the same reason the rollup filter
 * is: it is built and saved as one unit in the two-column picker, and shared as a single
 * file in `data/import-templates/`. Targets are written `Entity.Attribute` using the row
 * entity names in R-IR1, so a template can be read without knowing the object model.
 *
 * Parsing is deliberately forgiving. A template edited by hand, or written by a contributor,
 * must not make an import fail with a stack trace: an unreadable document reads as an empty
 * mapping, which the caller reports as "no column was matched".
 */
@NamespaceAccessible
public with sharing class ImportMapping {
    /** The row entities Core itself resolves (R-IR1, R-IR6). */
    @NamespaceAccessible
    public static final String ENTITY_HOUSEHOLD = 'Household';
    @NamespaceAccessible
    public static final String ENTITY_CONTACT_1 = 'Contact1';
    @NamespaceAccessible
    public static final String ENTITY_CONTACT_2 = 'Contact2';
    @NamespaceAccessible
    public static final String ENTITY_ORGANIZATION = 'Organization';
    /** The row's first person's connection to its organization, resolved by Core (R-IR8). */
    @NamespaceAccessible
    public static final String ENTITY_AFFILIATION = 'Affiliation';
    /** The one record a row of a template that loads one object describes (R-IT10). */
    @NamespaceAccessible
    public static final String ENTITY_RECORD = 'Record';

    /** The most values one file may be given for all its rows (R-IB14). */
    @NamespaceAccessible
    public static final Integer MAX_FILE_VALUES = 50;

    /** The row entities Core stages but does not write (R-IR6). */
    @NamespaceAccessible
    public static final Set<String> DEFERRED_ENTITIES = new Set<String>{
        'Gift',
        'Allocation',
        'SoftCredit',
        'Tribute'
    };

    /** The target that means "keep this column with the row and write it nowhere". */
    @NamespaceAccessible
    public static final String TARGET_IGNORE = 'Ignore';

    /**
     * The virtual attribute that holds a whole name in one column. The processor splits it
     * into a first and a last name, because a great many donor lists have only this.
     */
    @NamespaceAccessible
    public static final String ATTRIBUTE_FULL_NAME = 'FullName';

    /** One source column and what it describes. */
    @NamespaceAccessible
    public class Column {
        @AuraEnabled
        public String source;
        @AuraEnabled
        public String target;
        /**
         * For a lookup column of a template that loads one object, the parent field the value
         * names its parent by; empty or Id means the record Id (R-IT11).
         */
        @AuraEnabled
        public String lookupField;

        // JSON.deserialize requires a no-arg constructor to build this class from the stored
        // mapping document (see parse below); the fields it fills in are set afterward by the
        // deserializer, so this constructor only states that starting point explicitly.
        @NamespaceAccessible
        public Column() {
            this.source = null;
            this.target = null;
            this.lookupField = null;
        }

        @NamespaceAccessible
        public Column(String source, String target) {
            this.source = source;
            this.target = target;
        }
    }

    /**
     * One target the column picker offers: the value stored in the mapping document and the
     * label an administrator reads. An entity processor names its own (R-IR6).
     */
    @NamespaceAccessible
    public class Target {
        @AuraEnabled
        public String value;
        @AuraEnabled
        public String label;

        @NamespaceAccessible
        public Target(String value, String label) {
            this.value = value;
            this.label = label;
        }
    }

    /** One value applied to every row that does not carry its own. */
    @NamespaceAccessible
    public class Assignment {
        @AuraEnabled
        public String target;
        @AuraEnabled
        public String value;

        // JSON.deserialize requires a no-arg constructor to build this class from the stored
        // mapping document (see parse below); the fields it fills in are set afterward by the
        // deserializer, so this constructor only states that starting point explicitly.
        @NamespaceAccessible
        public Assignment() {
            this.target = null;
            this.value = null;
        }

        @NamespaceAccessible
        public Assignment(String target, String value) {
            this.target = target;
            this.value = value;
        }
    }

    @AuraEnabled
    public Integer version;
    @AuraEnabled
    public List<Column> columns;
    @AuraEnabled
    public List<Assignment> defaults;

    /**
     * The values given for every row of one file (R-IB14), which belong to the batch and not
     * the template: transient, so they are never saved into the template's document. A row's
     * own value wins over these, and these win over `defaults`. Null until the batch's values
     * are read.
     */
    @NamespaceAccessible
    public transient List<Assignment> fileValues;

    @NamespaceAccessible
    public ImportMapping() {
        this.version = 1;
        this.columns = new List<Column>();
        this.defaults = new List<Assignment>();
    }

    /**
     * Reads a mapping document. A blank or unreadable document reads as an empty mapping
     * rather than throwing, so one hand-edited template cannot break the wizard.
     */
    @NamespaceAccessible
    public static ImportMapping parse(String document) {
        ImportMapping result = new ImportMapping();
        if (String.isBlank(document)) {
            return result;
        }
        try {
            ImportMapping parsed = (ImportMapping) JSON.deserialize(document, ImportMapping.class);
            if (parsed == null) {
                return result;
            }
            result.version = parsed.version == null ? 1 : parsed.version;
            result.columns = parsed.columns == null ? new List<Column>() : parsed.columns;
            result.defaults = parsed.defaults == null ? new List<Assignment>() : parsed.defaults;
        } catch (Exception ignored) {
            // An unreadable document is an empty mapping. The caller reports the emptiness.
            return new ImportMapping();
        }
        return result;
    }

    /**
     * Reads the column document and the defaults document of a template, which are two
     * fields but one mapping.
     */
    @NamespaceAccessible
    public static ImportMapping parse(String columnDocument, String defaultsDocument) {
        ImportMapping result = parse(columnDocument);
        ImportMapping fromDefaults = parse(defaultsDocument);
        if (result.defaults.isEmpty() && !fromDefaults.defaults.isEmpty()) {
            result.defaults = fromDefaults.defaults;
        }
        return result;
    }

    /** The document, as it is stored on the template. */
    @NamespaceAccessible
    public String serialize() {
        return JSON.serialize(this);
    }

    /** The entity half of a target, or null when the target names no entity. */
    @NamespaceAccessible
    public static String entityOf(String target) {
        Integer dot = target == null ? -1 : target.indexOf('.');
        return dot <= 0 ? null : target.substring(0, dot).trim();
    }

    /** The attribute half of a target, or null when the target names no attribute. */
    @NamespaceAccessible
    public static String attributeOf(String target) {
        Integer dot = target == null ? -1 : target.indexOf('.');
        return dot < 0 || dot == target.length() - 1 ? null : target.substring(dot + 1).trim();
    }

    /** True when this target writes nothing, whether it says so or is simply unreadable. */
    @NamespaceAccessible
    public static Boolean isIgnored(String target) {
        return String.isBlank(target) ||
            TARGET_IGNORE.equalsIgnoreCase(target.trim()) ||
            entityOf(target) == null ||
            attributeOf(target) == null;
    }

    /**
     * The mapped target for each source column, keyed by the column name folded to lower
     * case and trimmed, which is how a header row is matched to a mapping. Ignored columns
     * are left out.
     */
    @NamespaceAccessible
    public Map<String, String> targetsBySourceKey() {
        Map<String, String> result = new Map<String, String>();
        for (Column column : columns) {
            if (column == null || String.isBlank(column.source) || isIgnored(column.target)) {
                continue;
            }
            result.put(key(column.source), column.target.trim());
        }
        return result;
    }

    /**
     * The parent field each lookup column names its parent by (R-IT11), keyed by the column's
     * target attribute in lower case; a column with none, or Id, is left out and means the
     * record Id.
     */
    @NamespaceAccessible
    public Map<String, String> lookupFieldsByAttribute() {
        Map<String, String> result = new Map<String, String>();
        for (Column column : columns) {
            if (
                column == null ||
                isIgnored(column.target) ||
                String.isBlank(column.lookupField) ||
                'id'.equalsIgnoreCase(column.lookupField.trim())
            ) {
                continue;
            }
            result.put(attributeOf(column.target).toLowerCase(), column.lookupField.trim());
        }
        return result;
    }

    /**
     * The source columns the administrator set to Do not load, keyed as `targetsBySourceKey`
     * keys them. Only the explicit ignore target counts: a blank or unreadable target is a
     * column nobody decided about. `targetsBySourceKey` leaves these out, which is right for
     * loading a row and wrong for suggesting a mapping, where a saved Do not load has to win
     * over a heading the column library recognizes, or the column is mapped again on the next
     * upload.
     */
    @NamespaceAccessible
    public Set<String> ignoredSourceKeys() {
        Set<String> result = new Set<String>();
        for (Column column : columns) {
            if (
                column != null &&
                String.isNotBlank(column.source) &&
                column.target != null &&
                TARGET_IGNORE.equalsIgnoreCase(column.target.trim())
            ) {
                result.add(key(column.source));
            }
        }
        return result;
    }

    /** Every entity this mapping names, in no particular order. */
    @NamespaceAccessible
    public Set<String> mappedEntities() {
        Set<String> result = new Set<String>();
        for (String target : targetsBySourceKey().values()) {
            result.add(entityOf(target));
        }
        for (Assignment assignment : assignments()) {
            result.add(entityOf(assignment.target));
        }
        return result;
    }

    /**
     * Every value applied to rows that do not carry their own, the file's (R-IB14) before the
     * template's, with blank and unreadable targets left out.
     */
    @NamespaceAccessible
    public List<Assignment> assignments() {
        List<Assignment> result = new List<Assignment>();
        List<Assignment> all = new List<Assignment>();
        if (fileValues != null) {
            all.addAll(fileValues);
        }
        all.addAll(defaults);
        for (Assignment assignment : all) {
            if (assignment != null && !isIgnored(assignment.target)) {
                result.add(assignment);
            }
        }
        return result;
    }

    /**
     * Reads the values given for every row of a file (R-IB14), held in the defaults format of
     * the mapping document. Blank targets and blank values are left out, and at most
     * MAX_FILE_VALUES are kept. An unreadable document reads as none, as a mapping does.
     */
    @NamespaceAccessible
    public static List<Assignment> parseValues(String document) {
        List<Assignment> result = new List<Assignment>();
        for (Assignment assignment : parse(document).defaults) {
            if (
                assignment != null &&
                !isIgnored(assignment.target) &&
                String.isNotBlank(assignment.value) &&
                result.size() < MAX_FILE_VALUES
            ) {
                result.add(new Assignment(assignment.target.trim(), assignment.value.trim()));
            }
        }
        return result;
    }

    /** The values given for every row of a file, as the batch stores them (R-IB14). */
    @NamespaceAccessible
    public static String valuesDocument(List<Assignment> values) {
        ImportMapping document = new ImportMapping();
        document.defaults = values == null ? new List<Assignment>() : values;
        return JSON.serialize(
            new Map<String, Object>{ 'version' => 1, 'defaults' => document.defaults }
        );
    }

    /** The entities this mapping names that Core stages but cannot write (R-IR6). */
    @NamespaceAccessible
    public Set<String> deferredEntities() {
        Set<String> result = new Set<String>();
        for (String entity : mappedEntities()) {
            if (DEFERRED_ENTITIES.contains(entity)) {
                result.add(entity);
            }
        }
        return result;
    }

    /**
     * True when this mapping can identify somebody: a person needs a name or an email, an
     * organization needs a name. A mapping that identifies nobody is refused before a dry
     * run rather than producing a file of rejected rows.
     */
    @NamespaceAccessible
    public Boolean identifiesSomebody() {
        for (String target : targetsBySourceKey().values()) {
            String entity = entityOf(target);
            String attribute = attributeOf(target);
            Boolean isPerson =
                ENTITY_CONTACT_1.equalsIgnoreCase(entity) ||
                ENTITY_CONTACT_2.equalsIgnoreCase(entity);
            if (
                isPerson &&
                (ATTRIBUTE_FULL_NAME.equalsIgnoreCase(attribute) ||
                'LastName'.equalsIgnoreCase(attribute) ||
                'Email'.equalsIgnoreCase(attribute))
            ) {
                return true;
            }
            if (
                ENTITY_ORGANIZATION.equalsIgnoreCase(entity) && 'Name'.equalsIgnoreCase(attribute)
            ) {
                return true;
            }
        }
        return false;
    }

    /** The lookup key of a column name: trimmed and folded to lower case. */
    @NamespaceAccessible
    public static String key(String columnName) {
        return columnName == null ? '' : columnName.trim().toLowerCase();
    }
}

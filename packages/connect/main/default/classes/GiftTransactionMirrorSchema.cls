/**
 * What the Gift Transaction mirror knows about this org's Nonprofit Cloud gift object (feature
 * X-07, canonical model Section 29D, R-GT1): whether the running person's describe has it, whether
 * its fields are the shape the mirror relies on, and which of them this person may read and write.
 *
 * The object and every field are names held as strings and resolved through describe, never
 * compile-time references, so Connect compiles and installs on an org without Nonprofit Cloud
 * (plan Section 4.2, ADR-0009, ADR-0013). The names are those of
 * `docs/architecture/reference/nonprofit-cloud-data-model.md` Section 3.1, where they are
 * corroborated but their types are inferred; so the types are checked here, and an org whose fields
 * differ is treated as one without the object: the mirror is unavailable and nothing queries it.
 *
 * The describe is read once per transaction (dynamic-apex.md Section 5). Only the global describe
 * is touched until the object is found, so an org without it pays one map lookup.
 */
public with sharing class GiftTransactionMirrorSchema {
    /** Nonprofit Cloud's gift object, resolved through describe so Connect installs without it. */
    private static final String OBJECT_NAME = 'GiftTransaction'; // detection-only: describe key, never a type
    /** The donor: a reference to Account (a person account or a business account). */
    public static final String DONOR_FIELD = 'DonorId';
    public static final String DATE_FIELD = 'TransactionDate';
    public static final String AMOUNT_FIELD = 'OriginalAmount';
    /** Optional: the amount after refunds, written only when a Gift Transaction is created. */
    public static final String CURRENT_AMOUNT_FIELD = 'CurrentAmount';
    public static final String STATUS_FIELD = 'Status';
    /** Optional: written only when a Gift Transaction is created, and only when it is not numbered. */
    public static final String NAME_FIELD = 'Name';

    /** The fields a later run compares and updates (R-GT4). */
    public static final List<String> COMPARED = new List<String>{
        DONOR_FIELD,
        DATE_FIELD,
        AMOUNT_FIELD
    };
    /** Every field a new Gift Transaction may be given (R-GT4). */
    public static final List<String> CREATED = new List<String>{
        DONOR_FIELD,
        DATE_FIELD,
        AMOUNT_FIELD,
        CURRENT_AMOUNT_FIELD,
        STATUS_FIELD,
        NAME_FIELD
    };
    /** What a Gift Transaction must let a run write for Gifts to Gift Transactions to work. */
    public static final List<String> REQUIRED_TO_CREATE = new List<String>{
        DONOR_FIELD,
        DATE_FIELD,
        AMOUNT_FIELD,
        STATUS_FIELD
    };
    /** What a run reads from a Gift Transaction, in either direction, and the page compares. */
    public static final List<String> READ = new List<String>{
        NAME_FIELD,
        DONOR_FIELD,
        DATE_FIELD,
        AMOUNT_FIELD,
        STATUS_FIELD
    };

    /** Test seam: the org as if it had no Gift Transactions, whatever it has. */
    @TestVisible
    private static Boolean absentForTest = false;

    private static Boolean resolved = false;
    private static Schema.SObjectType resolvedType;
    private static Schema.DescribeSObjectResult resolvedDescribe;
    private static Map<String, Schema.SObjectField> fieldMap;
    private static Map<String, Schema.DescribeFieldResult> fieldDescribes = new Map<String, Schema.DescribeFieldResult>();

    /**
     * The Gift Transaction object, or null where the running person's describe does not have it,
     * or has it in a shape the mirror does not know.
     */
    public static Schema.SObjectType objectType() {
        if (absentForTest) {
            return null;
        }
        if (!resolved) {
            resolved = true;
            Schema.SObjectType found = Schema.getGlobalDescribe().get(OBJECT_NAME);
            if (found != null) {
                Schema.DescribeSObjectResult describe = found.getDescribe(
                    SObjectDescribeOptions.DEFERRED
                );
                fieldMap = describe.fields.getMap();
                if (hasExpectedShape()) {
                    resolvedType = found;
                    resolvedDescribe = describe;
                }
            }
        }
        return resolvedType;
    }

    public static Boolean isAvailable() {
        return objectType() != null;
    }

    /** The object's API name as the org's describe gives it, or null when unavailable. */
    public static String objectName() {
        return isAvailable() ? resolvedDescribe.getName() : null;
    }

    /** Whether the running person may read Gift Transactions and each of these fields. */
    public static Boolean canRead(List<String> names) {
        if (!isAvailable() || !resolvedDescribe.isAccessible()) {
            return false;
        }
        for (String name : names) {
            Schema.DescribeFieldResult described = field(name);
            if (described == null || !described.isAccessible()) {
                return false;
            }
        }
        return true;
    }

    /** Whether the running person may create Gift Transactions with each of these fields. */
    public static Boolean canCreate(List<String> names) {
        if (!isAvailable() || !resolvedDescribe.isCreateable()) {
            return false;
        }
        return writable(names, true).size() == new Set<String>(names).size();
    }

    /** Whether the running person may edit Gift Transactions and each of these fields. */
    public static Boolean canUpdate(List<String> names) {
        if (!isAvailable() || !resolvedDescribe.isUpdateable()) {
            return false;
        }
        return writable(names, false).size() == new Set<String>(names).size();
    }

    /**
     * The fields among these that exist and the running person may write on a new record
     * (`creating`) or an existing one. A numbered Name is never writable.
     */
    public static Set<String> writable(List<String> names, Boolean creating) {
        Set<String> found = new Set<String>();
        if (!isAvailable()) {
            return found;
        }
        for (String name : names) {
            Schema.DescribeFieldResult described = field(name);
            if (described == null || described.isAutoNumber() || described.isCalculated()) {
                continue;
            }
            if (creating ? described.isCreateable() : described.isUpdateable()) {
                found.add(name);
            }
        }
        return found;
    }

    /** Whether this is an active value of the org's Gift Transaction Status list (R-GT2). */
    public static Boolean isActiveStatus(String value) {
        if (String.isBlank(value) || !isAvailable()) {
            return false;
        }
        for (Schema.PicklistEntry entry : field(STATUS_FIELD).getPicklistValues()) {
            if (entry.isActive() && entry.getValue() == value) {
                return true;
            }
        }
        return false;
    }

    /** The field's describe, read once, or null where the object or the field is absent. */
    public static Schema.DescribeFieldResult field(String name) {
        if (fieldMap == null || String.isBlank(name)) {
            return null;
        }
        String key = name.toLowerCase();
        if (!fieldDescribes.containsKey(key)) {
            Schema.SObjectField token = fieldMap.get(key);
            fieldDescribes.put(key, token == null ? null : token.getDescribe());
        }
        return fieldDescribes.get(key);
    }

    /**
     * R-GT1: the four fields the mirror cannot do without, with the types it relies on. The
     * optional fields are checked where they are used: a Current Amount that is not an amount, or a
     * Name that is not text, is left out.
     */
    private static Boolean hasExpectedShape() {
        Schema.DescribeFieldResult donor = field(DONOR_FIELD);
        Schema.DescribeFieldResult transactionDate = field(DATE_FIELD);
        Schema.DescribeFieldResult status = field(STATUS_FIELD);
        return donor != null &&
            donor.getType() == Schema.DisplayType.REFERENCE &&
            donor.getReferenceTo().contains(Account.SObjectType) &&
            transactionDate != null &&
            transactionDate.getType() == Schema.DisplayType.DATE &&
            isAmount(field(AMOUNT_FIELD)) &&
            status != null &&
            status.getType() == Schema.DisplayType.PICKLIST;
    }

    /** Whether the optional field is there and of the type the mirror writes into it. */
    public static Boolean hasOptional(String name) {
        Schema.DescribeFieldResult described = field(name);
        if (described == null) {
            return false;
        }
        if (name == CURRENT_AMOUNT_FIELD) {
            return isAmount(described);
        }
        if (name == NAME_FIELD) {
            return described.getType() == Schema.DisplayType.STRING;
        }
        return true;
    }

    /**
     * An amount as a Decimal, whichever number type the org's field returns, so a comparison with
     * a gift's amount is by value.
     */
    public static Decimal decimalOf(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        return Decimal.valueOf(String.valueOf(value));
    }

    private static Boolean isAmount(Schema.DescribeFieldResult described) {
        return described != null &&
            (described.getType() == Schema.DisplayType.CURRENCY ||
            described.getType() == Schema.DisplayType.DOUBLE);
    }
}

/**
 * The work of undoing one import, in passes (canonical model R-IB8, R-IB9): **people**
 * stored as contacts, then **people stored as accounts**, then **households and
 * organizations**. People go first so a household is judged after its
 * imported members are gone; deleting an account would otherwise take its contacts with it.
 *
 * Every delete query is filtered by one bound batch identifier and nothing else, and the tag
 * is checked again on each record before it is deleted. A tagged record that has gained
 * something since the import is kept, and journaled with the reason.
 */
@NamespaceAccessible
public with sharing class ImportUndoBatch implements Database.Batchable<SObject>, Database.Stateful {
    @TestVisible
    private static final String PASS_CONTACTS = 'Contacts';
    @TestVisible
    private static final String PASS_PERSON_ACCOUNTS = 'PersonAccounts';
    @TestVisible
    private static final String PASS_ACCOUNTS = 'Accounts';
    private static final List<String> PASSES = new List<String>{
        PASS_CONTACTS,
        PASS_PERSON_ACCOUNTS,
        PASS_ACCOUNTS
    };

    /** Children never counted as something a record gained: the import's own bookkeeping. */
    private static final Set<String> NOT_GAINED = new Set<String>{
        'import_row__c',
        'import_journal__c',
        'rollupcalcitem__c'
    };

    private static final Integer MAX_CHUNK = 200;

    /** Headroom left for the queries after the guard, so a busy chunk keeps rather than fails. */
    private static final Integer QUERY_HEADROOM = 10;

    private final Id batchId;
    private final Integer countedAtStart;
    private final String pass;
    private Integer restored;
    private Boolean failed;
    private Datetime completedAt;

    /**
     * Starts the first pass of the undo of one batch. `countedAtStart` is the total the person
     * confirmed, kept so the run log can say how many of those were deleted and how many kept.
     */
    @NamespaceAccessible
    public static Id run(Id batchId, Integer countedAtStart) {
        return Database.executeBatch(
            new ImportUndoBatch(batchId, countedAtStart, PASSES[0], 0, false),
            scopeFor(PASSES[0], batchId)
        );
    }

    @TestVisible
    private ImportUndoBatch(
        Id batchId,
        Integer countedAtStart,
        String pass,
        Integer restored,
        Boolean failed
    ) {
        this.batchId = batchId;
        this.countedAtStart = countedAtStart;
        this.pass = pass;
        this.restored = restored;
        this.failed = failed;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        Id owner = batchId;
        completedAt = [
            SELECT Completed_At__c
            FROM Import_Batch__c
            WHERE Id = :owner
            WITH SYSTEM_MODE
            LIMIT 1
        ]
        .Completed_At__c;
        if (PASS_CONTACTS.equals(pass)) {
            return Database.getQueryLocator(
                [
                    SELECT Id, Name, Created_By_Import_Batch__c
                    FROM Contact
                    WHERE Created_By_Import_Batch__c = :owner
                ]
            );
        }
        Set<Id> personTypes = OrgShapeDetector.detect().personAccountRecordTypeIds;
        if (PASS_PERSON_ACCOUNTS.equals(pass)) {
            return Database.getQueryLocator(
                [
                    SELECT Id, Name, Created_By_Import_Batch__c
                    FROM Account
                    WHERE Created_By_Import_Batch__c = :owner AND RecordTypeId IN :personTypes
                ]
            );
        }
        return Database.getQueryLocator(
            [
                SELECT Id, Name, Created_By_Import_Batch__c
                FROM Account
                WHERE
                    Created_By_Import_Batch__c = :owner
                    AND (RecordTypeId = NULL
                    OR RecordTypeId NOT IN :personTypes)
            ]
        );
    }

    public void execute(Database.BatchableContext context, List<SObject> records) {
        List<Map<String, Object>> journal = new List<Map<String, Object>>();
        try {
            deleteTagged(records, journal);
        } catch (Exception e) {
            failed = true;
            ErrorLogger.log(e, 'ImportUndoBatch.execute', batchId);
        }
        ImportJournalService.write(batchId, ImportJournalService.PHASE_UNDO, journal);
    }

    public void finish(Database.BatchableContext context) {
        Integer next = PASSES.indexOf(pass) + 1;
        try {
            if (next < PASSES.size()) {
                Database.executeBatch(
                    new ImportUndoBatch(batchId, countedAtStart, PASSES[next], restored, failed),
                    scopeFor(PASSES[next], batchId)
                );
                return;
            }
        } catch (Exception e) {
            ErrorLogger.log(e, 'ImportUndoBatch.finish', batchId);
            failed = true;
        }
        ImportUndoService.finish(batchId, countedAtStart, restored, failed);
    }

    // -------------------------------------------------------------------------------------
    // Delete
    // -------------------------------------------------------------------------------------

    /**
     * Deletes this chunk's tagged records, keeping the ones that have gained something since
     * the import. Deleted in the running user's own mode, to the recycle bin (R-IB8). A record
     * the platform refuses is kept and journaled, never retried in a wider form.
     */
    private void deleteTagged(List<SObject> records, List<Map<String, Object>> journal) {
        Map<Id, SObject> tagged = new Map<Id, SObject>();
        for (SObject record : records) {
            if (record.get('Created_By_Import_Batch__c') == batchId) {
                tagged.put(record.Id, record);
            }
        }
        if (tagged.isEmpty()) {
            return;
        }
        Map<Id, String> keep = reasonsToKeep(tagged.keySet(), records[0].getSObjectType());
        List<SObject> toDelete = new List<SObject>();
        for (SObject record : tagged.values()) {
            if (keep.containsKey(record.Id)) {
                journal.add(kept(record, keep.get(record.Id)));
            } else {
                toDelete.add(record);
            }
        }
        if (toDelete.isEmpty()) {
            return;
        }
        List<Database.DeleteResult> results = Database.delete(
            toDelete,
            false,
            AccessLevel.USER_MODE
        );
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                journal.add(kept(toDelete[i], message(results[i].getErrors())));
            }
        }
    }

    /**
     * Why each of these records is not the import's to delete. Kept when anything created
     * after the import points at it through a custom reference, and, for a household or an
     * organization, when a person is still on it or something outside Open Impact depends on
     * it (ADR-0036). A person stored as an account is not judged by its own contact.
     */
    private Map<Id, String> reasonsToKeep(Set<Id> ids, Schema.SObjectType type) {
        Map<Id, String> keep = new Map<Id, String>();
        Map<String, Object> gainedBinds = new Map<String, Object>{
            'ids' => ids,
            'since' => completedAt
        };
        for (Schema.ChildRelationship relationship : type.getDescribe().getChildRelationships()) {
            String reference = gainedReference(relationship);
            if (reference == null) {
                continue;
            }
            List<String> guard = gainedQuery(type, relationship, reference);
            if (guard != null) {
                markKept(keep, guard[0], guard[1], gainedBinds, Label.Core_Import_UndoKeptGained);
            }
        }
        if (PASS_ACCOUNTS.equals(pass)) {
            Map<String, Object> binds = new Map<String, Object>{ 'ids' => ids };
            markKept(
                keep,
                'SELECT Id FROM Account WHERE Id IN :ids AND Id IN (SELECT AccountId FROM Contact)',
                'Id',
                binds,
                Label.Core_Import_UndoKeptHasPeople
            );
            markKept(
                keep,
                'SELECT Id FROM Account WHERE Id IN :ids AND Id IN ' +
                '(SELECT Household__c FROM Household_Member__c WHERE Contact__c != NULL OR Account__c != NULL)',
                'Id',
                binds,
                Label.Core_Import_UndoKeptHasPeople
            );
            for (Id dependent : HouseholdSelector.getAccountsWithNativeDependents(ids)) {
                keep.put(dependent, Label.Core_Import_UndoKeptNativeDependents);
            }
        }
        return keep;
    }

    /**
     * The reference field of a child relationship that counts as something gained: a custom
     * reference from a custom object, a contact or an account, which the org can filter on.
     * The import's own bookkeeping and the vendored rollup engine's work items do not count.
     */
    private static String gainedReference(Schema.ChildRelationship relationship) {
        Schema.DescribeFieldResult field = relationship.getField().getDescribe();
        Schema.DescribeSObjectResult child = relationship.getChildSObject()
            .getDescribe(SObjectDescribeOptions.DEFERRED);
        String childName = child.getName();
        String localName = childName.countMatches('__') > 1
            ? childName.substringAfter('__')
            : childName;
        Boolean ownKind =
            childName.endsWith('__c') ||
            childName == 'Account' ||
            childName == 'Contact';
        if (
            !field.isCustom() ||
            !field.isFilterable() ||
            !child.isQueryable() ||
            !ownKind ||
            NOT_GAINED.contains(localName.toLowerCase())
        ) {
            return null;
        }
        return field.getName();
    }

    /**
     * The guard query for one gained reference, and the field of its rows that names the kept
     * record; null when the reference cannot point at these records. Three shapes, because
     * SOQL refuses a semi-join whose inner and outer objects are the same, and on an org with
     * Person Accounts an account's child relationships include references to its contact:
     *
     * - a reference to the same object (an account's employer): the later rows themselves;
     * - a reference to this object: a semi-join, so a donor with thousands of later gifts
     *   costs one row;
     * - a reference to a contact, for a person stored as an account: a semi-join on the
     *   account's own contact.
     */
    private List<String> gainedQuery(
        Schema.SObjectType type,
        Schema.ChildRelationship relationship,
        String reference
    ) {
        String parent = type.getDescribe(SObjectDescribeOptions.DEFERRED).getName();
        String child = relationship.getChildSObject()
            .getDescribe(SObjectDescribeOptions.DEFERRED)
            .getName();
        List<Schema.SObjectType> targets = relationship.getField().getDescribe().getReferenceTo();
        String laterRows =
            ' IN (SELECT ' +
            reference +
            ' FROM ' +
            child +
            ' WHERE CreatedDate > :since)';
        if (targets.contains(type) && parent == child) {
            return new List<String>{
                'SELECT ' +
                reference +
                ' FROM ' +
                child +
                ' WHERE ' +
                reference +
                ' IN :ids AND CreatedDate > :since',
                reference
            };
        }
        if (targets.contains(type)) {
            return new List<String>{
                'SELECT Id FROM ' +
                parent +
                ' WHERE Id IN :ids AND Id' +
                laterRows,
                'Id'
            };
        }
        if (PASS_PERSON_ACCOUNTS.equals(pass) && targets.contains(Contact.SObjectType)) {
            return new List<String>{
                'SELECT Id FROM Account WHERE Id IN :ids AND PersonContactId' + laterRows,
                'Id'
            };
        }
        return null;
    }

    /**
     * Marks the ids a guard query returns as kept. Read in system mode (ADR-0021): a guard
     * that cannot see a gift would answer "nothing depends on this" for exactly the record it
     * must keep. A guard that cannot run, or would leave too few queries for the delete,
     * keeps every record it was asked about: not knowing is not the same as knowing nothing
     * depends on it.
     */
    private void markKept(
        Map<Id, String> keep,
        String query,
        String keptField,
        Map<String, Object> binds,
        String reason
    ) {
        Set<Id> ids = (Set<Id>) binds.get('ids');
        if (Limits.getQueries() >= Limits.getLimitQueries() - QUERY_HEADROOM) {
            for (Id recordId : ids) {
                keep.put(recordId, Label.Core_Import_UndoKeptNotChecked);
            }
            return;
        }
        try {
            for (SObject record : Database.queryWithBinds(query, binds, AccessLevel.SYSTEM_MODE)) {
                Id keptId = (Id) record.get(keptField);
                if (!keep.containsKey(keptId)) {
                    keep.put(keptId, reason);
                }
            }
        } catch (Exception e) {
            ErrorLogger.log(e, 'ImportUndoBatch.markKept', batchId);
            for (Id recordId : ids) {
                keep.put(recordId, Label.Core_Import_UndoKeptNotChecked);
            }
        }
    }

    // -------------------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------------------

    private static Map<String, Object> kept(SObject record, String reason) {
        return ImportJournalService.kept(
            record.getSObjectType().getDescribe(SObjectDescribeOptions.DEFERRED).getName(),
            record.Id,
            String.valueOf(record.get('Name')),
            reason
        );
    }

    private static String message(List<Database.Error> errors) {
        List<String> parts = new List<String>();
        for (Database.Error error : errors) {
            parts.add(error.getMessage());
        }
        return String.join(parts, ' ');
    }

    /** The batch's own chunk size, held at the 200 records a delete is normally made in. */
    private static Integer scopeFor(String pass, Id batchId) {
        Decimal chunkSize = [
            SELECT Chunk_Size__c
            FROM Import_Batch__c
            WHERE Id = :batchId
            WITH SYSTEM_MODE
            LIMIT 1
        ]
        .Chunk_Size__c;
        return chunkSize == null ||
            chunkSize < 1
            ? MAX_CHUNK
            : Math.min(chunkSize.intValue(), MAX_CHUNK);
    }
}

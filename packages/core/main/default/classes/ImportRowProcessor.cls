/**
 * Resolves one chunk of staged rows in dependency order, and is the only class that decides
 * what a row means (R-IR1): the organization, then the household, then the two people.
 *
 * Three rules shape everything here.
 *
 * **Bulk safe.** Every query and every save is over a whole chunk. There is no SOQL and no
 * DML inside a loop over rows, so the chunk size can be raised as far as an org's automation
 * allows without the processor being the thing that breaks.
 *
 * **A dry run makes the same decisions the commit will make** (R-IB1). The matching, the
 * validation and the status of every row are computed by the same code on both passes; the
 * only difference is that the dry run does not save. That is what makes the preview worth
 * trusting.
 *
 * **A failed row does not take the chunk with it** (R-IB5). Saves are partial-success, and a
 * row that fails carries the reason on itself, in words an administrator can act on. Nothing
 * fails silently: a row is Rejected with a message, or it is not Rejected.
 *
 * Membership is never reimplemented. A new person is inserted with no household and the
 * household trigger gives them one, which is the same path a person saved by hand takes.
 * Where a row's two people belong together, the second is joined to the first person's
 * household through `HouseholdService`, which is the only class that knows whether this org
 * writes membership as the person's account reference or as a membership row (R-M5).
 */
@NamespaceAccessible
public with sharing class ImportRowProcessor {
    @NamespaceAccessible
    public static final String STATUS_PENDING = 'Pending';
    @NamespaceAccessible
    public static final String STATUS_MATCHED = 'Matched';
    @NamespaceAccessible
    public static final String STATUS_CREATED = 'Created';
    @NamespaceAccessible
    public static final String STATUS_UPDATED = 'Updated';
    @NamespaceAccessible
    public static final String STATUS_REJECTED = 'Rejected';
    @NamespaceAccessible
    public static final String STATUS_SKIPPED = 'Skipped';

    /** The class name a dependent package registers to resolve the rest of a row (R-IR6). */
    @NamespaceAccessible
    public static final String ENTITY_PROCESSOR_CLASS = 'GiftImportProcessor';

    private static final String ORGANIZATION_RECORD_TYPE = 'Organization';

    /**
     * The attributes that can name or find a person. A full name column is not listed because
     * `splitFullNames` has already turned one into a first and last name by the time anything
     * asks this question.
     */
    private static final List<String> IDENTIFYING_ATTRIBUTES = new List<String>{
        'LastName',
        'FirstName',
        'Email'
    };

    /** What one chunk did, added up by the batch. */
    @NamespaceAccessible
    public class Outcome {
        @NamespaceAccessible
        public Integer created = 0;
        @NamespaceAccessible
        public Integer updated = 0;
        @NamespaceAccessible
        public Integer matched = 0;
        @NamespaceAccessible
        public Integer rejected = 0;
        @NamespaceAccessible
        public Integer skipped = 0;
        /** Anything the run log should say once, not once per row. */
        @NamespaceAccessible
        public Set<String> notes = new Set<String>();
    }

    /** One row's working state while the chunk is resolved. */
    private class Working {
        Import_Row__c row;
        Map<String, String> values;
        Map<String, Map<String, String>> byEntity;
        String organizationKey;
        String personKey1;
        String personKey2;
        Id organizationId;
        Id person1Id;
        Id person2Id;
        Boolean createdAnything = false;
        Boolean updatedAnything = false;
        /** True when this run created the row's second person, who is joined to a household. */
        Boolean createdPerson2 = false;
        String error;
    }

    /**
     * Resolves a chunk. Writes nothing when dryRun is true. The rows are updated in place
     * with their status, their resolved lookups and any error, and are saved here.
     */
    @NamespaceAccessible
    public static Outcome process(
        Import_Batch__c batch,
        Import_Template__c template,
        ImportMapping mapping,
        List<Import_Row__c> rows,
        Boolean dryRun
    ) {
        Outcome outcome = new Outcome();
        if (rows == null || rows.isEmpty()) {
            return outcome;
        }
        Boolean personAccounts = ImportTemplateService.isPersonAccountMode(template);
        String rule = ImportTemplateService.normalizedRule(template.Matching_Rule__c);

        List<Working> working = read(rows, mapping, outcome);
        resolveOrganizations(working, rule, batch, dryRun, outcome);
        resolvePeople(working, rule, batch, personAccounts, dryRun, outcome);
        applyHouseholdValues(working, dryRun);
        offerToEntityProcessor(batch, mapping, rows, working, dryRun, outcome);
        writeBack(working, outcome);
        return outcome;
    }

    // -------------------------------------------------------------------------------------
    // Reading
    // -------------------------------------------------------------------------------------

    /** Parses every row's raw values into the entities they describe, and validates them. */
    private static List<Working> read(
        List<Import_Row__c> rows,
        ImportMapping mapping,
        Outcome outcome
    ) {
        Map<String, String> targets = mapping.targetsBySourceKey();
        List<Working> working = new List<Working>();
        for (Import_Row__c row : rows) {
            Working item = new Working();
            item.row = row;
            item.values = rawValues(row);
            item.byEntity = groupByEntity(item.values, targets, mapping.defaults);
            splitFullNames(item.byEntity);
            item.organizationKey = ImportMatcher.nameKey(
                attribute(item.byEntity, ImportMapping.ENTITY_ORGANIZATION, 'Name')
            );
            working.add(item);
        }
        Set<String> deferred = mapping.deferredEntities();
        if (!deferred.isEmpty()) {
            outcome.notes.add(
                String.format(
                    Label.Core_Import_LogEntitiesNotLoaded,
                    new List<String>{ String.join(new List<String>(deferred), ', ') }
                )
            );
        }
        return working;
    }

    /** The row's uploaded values, keyed the way a mapping's source columns are keyed. */
    private static Map<String, String> rawValues(Import_Row__c row) {
        Map<String, String> result = new Map<String, String>();
        if (String.isBlank(row.Raw_Values_JSON__c)) {
            return result;
        }
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
                row.Raw_Values_JSON__c
            );
            for (String column : parsed.keySet()) {
                Object value = parsed.get(column);
                result.put(
                    ImportMapping.key(column),
                    value == null ? null : String.valueOf(value).trim()
                );
            }
        } catch (Exception ignored) {
            // A row whose staged values cannot be read is rejected below, not thrown from.
            return new Map<String, String>();
        }
        return result;
    }

    /** entity to attribute to value, with the template's defaults filled in where empty. */
    private static Map<String, Map<String, String>> groupByEntity(
        Map<String, String> values,
        Map<String, String> targets,
        List<ImportMapping.Assignment> defaults
    ) {
        Map<String, Map<String, String>> result = new Map<String, Map<String, String>>();
        for (String sourceKey : targets.keySet()) {
            String value = values.get(sourceKey);
            if (String.isBlank(value)) {
                continue;
            }
            put(result, targets.get(sourceKey), value);
        }
        for (ImportMapping.Assignment assignment : defaults) {
            if (assignment == null || ImportMapping.isIgnored(assignment.target)) {
                continue;
            }
            String entity = ImportMapping.entityOf(assignment.target);
            String attribute = ImportMapping.attributeOf(assignment.target);
            Map<String, String> held = result.get(entity);
            if (held == null || String.isBlank(held.get(attribute))) {
                put(result, assignment.target, assignment.value);
            }
        }
        return result;
    }

    private static void put(Map<String, Map<String, String>> target, String path, String value) {
        String entity = ImportMapping.entityOf(path);
        String attribute = ImportMapping.attributeOf(path);
        if (entity == null || attribute == null) {
            return;
        }
        if (!target.containsKey(entity)) {
            target.put(entity, new Map<String, String>());
        }
        target.get(entity).put(attribute, value);
    }

    private static String attribute(
        Map<String, Map<String, String>> byEntity,
        String entity,
        String name
    ) {
        Map<String, String> held = byEntity.get(entity);
        return held == null ? null : held.get(name);
    }

    /**
     * Turns a single whole-name column into a first and a last name, because a great many
     * donor lists have only one. "Ramirez, Ana" and "Ana Ramirez" both read the same way.
     */
    private static void splitFullNames(Map<String, Map<String, String>> byEntity) {
        for (
            String entity : new List<String>{
                ImportMapping.ENTITY_CONTACT_1,
                ImportMapping.ENTITY_CONTACT_2
            }
        ) {
            Map<String, String> held = byEntity.get(entity);
            if (held == null) {
                continue;
            }
            String full = held.remove(ImportMapping.ATTRIBUTE_FULL_NAME);
            if (String.isBlank(full)) {
                continue;
            }
            full = full.trim().replaceAll('\\s+', ' ');
            String first;
            String last;
            if (full.contains(',')) {
                last = full.substringBefore(',').trim();
                first = full.substringAfter(',').trim();
            } else if (full.contains(' ')) {
                last = full.substringAfterLast(' ').trim();
                first = full.substringBeforeLast(' ').trim();
            } else {
                last = full;
                first = null;
            }
            if (String.isBlank(held.get('LastName')) && String.isNotBlank(last)) {
                held.put('LastName', last);
            }
            if (String.isBlank(held.get('FirstName')) && String.isNotBlank(first)) {
                held.put('FirstName', first);
            }
        }
    }

    // -------------------------------------------------------------------------------------
    // Organizations
    // -------------------------------------------------------------------------------------

    private static void resolveOrganizations(
        List<Working> working,
        String rule,
        Import_Batch__c batch,
        Boolean dryRun,
        Outcome outcome
    ) {
        Set<String> names = new Set<String>();
        for (Working item : working) {
            if (item.organizationKey != null) {
                names.add(item.organizationKey);
            }
        }
        if (names.isEmpty()) {
            return;
        }
        Id recordTypeId = recordTypeId(ORGANIZATION_RECORD_TYPE);
        if (recordTypeId == null) {
            outcome.notes.add(Label.Core_Import_LogOrganizationRecordTypeMissing);
            return;
        }
        Map<String, Id> existing = ImportMatcher.accountsByName(names, recordTypeId);

        Map<String, Working> firstRowByName = new Map<String, Working>();
        List<Account> toCreate = new List<Account>();
        List<String> createdNames = new List<String>();
        for (Working item : working) {
            if (item.organizationKey == null) {
                continue;
            }
            Id found = existing.get(item.organizationKey);
            if (found != null) {
                item.organizationId = found;
                continue;
            }
            if (firstRowByName.containsKey(item.organizationKey)) {
                // A second row naming the same new organization waits for the first one's
                // record, so one file never creates the same organization twice (R-IB4).
                continue;
            }
            firstRowByName.put(item.organizationKey, item);
            Account organization = new Account(
                Name = attribute(item.byEntity, ImportMapping.ENTITY_ORGANIZATION, 'Name'),
                RecordTypeId = recordTypeId,
                Created_By_Import_Batch__c = batch.Id
            );
            applyValues(
                organization,
                Account.SObjectType,
                item.byEntity.get(ImportMapping.ENTITY_ORGANIZATION),
                new Set<String>{ 'Name' },
                outcome
            );
            toCreate.add(organization);
            createdNames.add(item.organizationKey);
        }
        if (toCreate.isEmpty()) {
            return;
        }
        if (dryRun) {
            for (Working item : working) {
                if (item.organizationId == null && item.organizationKey != null) {
                    item.createdAnything = true;
                }
            }
            return;
        }
        Map<String, Id> newIds = new Map<String, Id>();
        List<Database.SaveResult> results = Database.insert(toCreate, false, AccessLevel.USER_MODE);
        for (Integer i = 0; i < results.size(); i++) {
            Working owner = firstRowByName.get(createdNames[i]);
            if (results[i].isSuccess()) {
                newIds.put(createdNames[i], results[i].getId());
                owner.createdAnything = true;
            } else {
                owner.error = message(results[i]);
            }
        }
        for (Working item : working) {
            if (item.organizationId != null || item.organizationKey == null) {
                continue;
            }
            Id created = newIds.get(item.organizationKey);
            if (created != null) {
                item.organizationId = created;
                item.createdAnything = true;
            } else if (item.error == null) {
                item.error = Label.Core_Import_ErrorOrganizationNotSaved;
            }
        }
    }

    // -------------------------------------------------------------------------------------
    // People
    // -------------------------------------------------------------------------------------

    private static void resolvePeople(
        List<Working> working,
        String rule,
        Import_Batch__c batch,
        Boolean personAccounts,
        Boolean dryRun,
        Outcome outcome
    ) {
        // Both people on a row are matched from the same key sets, in one pass each.
        Set<String> emailKeys = new Set<String>();
        Set<String> namePostalKeys = new Set<String>();
        Set<String> externalIds = new Set<String>();
        // The External ID rule matches on whatever field this org marked as its external
        // identifier, so no field has to be invented for it and an org without one is told.
        String externalIdField = ImportTemplateService.RULE_EXTERNAL_ID.equals(rule)
            ? ImportMatcher.externalIdField(
                  personAccounts ? Account.SObjectType : Contact.SObjectType
              )
            : null;
        for (Working item : working) {
            item.personKey1 = personKey(
                item,
                ImportMapping.ENTITY_CONTACT_1,
                rule,
                externalIdField
            );
            item.personKey2 = personKey(
                item,
                ImportMapping.ENTITY_CONTACT_2,
                rule,
                externalIdField
            );
            collect(item.personKey1, rule, emailKeys, namePostalKeys, externalIds);
            collect(item.personKey2, rule, emailKeys, namePostalKeys, externalIds);
        }

        Map<String, Id> matches = matchPeople(
            rule,
            personAccounts,
            emailKeys,
            namePostalKeys,
            externalIds,
            outcome
        );

        assignPerson(working, matches, ImportMapping.ENTITY_CONTACT_1, true);
        assignPerson(working, matches, ImportMapping.ENTITY_CONTACT_2, false);
        validate(working);

        if (dryRun) {
            countUpdatesInPreview(working, personAccounts);
            return;
        }
        savePeople(working, batch, personAccounts, outcome);
    }

    private static void collect(
        String key,
        String rule,
        Set<String> emailKeys,
        Set<String> namePostalKeys,
        Set<String> externalIds
    ) {
        if (key == null) {
            return;
        }
        if (ImportTemplateService.RULE_EMAIL.equals(rule)) {
            emailKeys.add(key);
        } else if (ImportTemplateService.RULE_NAME_POSTAL.equals(rule)) {
            namePostalKeys.add(key);
        } else {
            externalIds.add(key);
        }
    }

    /** The value this row is matched on for one person, or null when it cannot be matched. */
    private static String personKey(
        Working item,
        String entity,
        String rule,
        String externalIdField
    ) {
        Map<String, String> held = item.byEntity.get(entity);
        if (held == null || held.isEmpty()) {
            return null;
        }
        if (ImportTemplateService.RULE_EMAIL.equals(rule)) {
            return ImportMatcher.emailKey(held.get('Email'));
        }
        if (ImportTemplateService.RULE_NAME_POSTAL.equals(rule)) {
            String postal = held.get('MailingPostalCode');
            if (String.isBlank(postal)) {
                postal = attribute(
                    item.byEntity,
                    ImportMapping.ENTITY_HOUSEHOLD,
                    'BillingPostalCode'
                );
            }
            return ImportMatcher.nameAndPostalKey(held.get('LastName'), postal);
        }
        return externalIdField == null ? null : ImportMatcher.nameKey(held.get(externalIdField));
    }

    private static Map<String, Id> matchPeople(
        String rule,
        Boolean personAccounts,
        Set<String> emailKeys,
        Set<String> namePostalKeys,
        Set<String> externalIds,
        Outcome outcome
    ) {
        if (ImportTemplateService.RULE_EMAIL.equals(rule)) {
            return personAccounts
                ? ImportMatcher.personAccountsByEmail(emailKeys, personRecordTypeIds())
                : ImportMatcher.contactsByEmail(emailKeys);
        }
        if (ImportTemplateService.RULE_NAME_POSTAL.equals(rule)) {
            return personAccounts
                ? ImportMatcher.personAccountsByNameAndPostalCode(
                      namePostalKeys,
                      personRecordTypeIds()
                  )
                : ImportMatcher.contactsByNameAndPostalCode(namePostalKeys);
        }
        Schema.SObjectType type = personAccounts ? Account.SObjectType : Contact.SObjectType;
        if (ImportMatcher.externalIdField(type) == null) {
            outcome.notes.add(Label.Core_Import_LogNoExternalIdField);
            return new Map<String, Id>();
        }
        return ImportMatcher.byExternalId(type, externalIds);
    }

    private static void assignPerson(
        List<Working> working,
        Map<String, Id> matches,
        String entity,
        Boolean isFirst
    ) {
        for (Working item : working) {
            String key = isFirst ? item.personKey1 : item.personKey2;
            if (key == null) {
                continue;
            }
            Id found = matches.get(key);
            if (found == null) {
                continue;
            }
            if (isFirst) {
                item.person1Id = found;
            } else {
                item.person2Id = found;
            }
        }
    }

    /** A row has to describe somebody. One that does not is rejected before anything is saved. */
    private static void validate(List<Working> working) {
        for (Working item : working) {
            if (item.error != null) {
                continue;
            }
            if (item.values.isEmpty()) {
                item.error = Label.Core_Import_ErrorRowUnreadable;
                continue;
            }
            Boolean hasOrganization = item.organizationKey != null;
            Boolean hasPerson1 = describesPerson(item, ImportMapping.ENTITY_CONTACT_1);
            Boolean hasPerson2 = describesPerson(item, ImportMapping.ENTITY_CONTACT_2);
            Boolean identifiesSomebody =
                hasOrganization ||
                identifiesPerson(item, ImportMapping.ENTITY_CONTACT_1) ||
                identifiesPerson(item, ImportMapping.ENTITY_CONTACT_2);
            if (!identifiesSomebody) {
                item.error = Label.Core_Import_ErrorRowIdentifiesNobody;
                continue;
            }
            if (
                hasPerson1 &&
                item.person1Id == null &&
                !hasLastName(item, ImportMapping.ENTITY_CONTACT_1)
            ) {
                item.error = Label.Core_Import_ErrorLastNameMissing;
            } else if (
                hasPerson2 &&
                item.person2Id == null &&
                !hasLastName(item, ImportMapping.ENTITY_CONTACT_2)
            ) {
                item.error = Label.Core_Import_ErrorLastNameMissing;
            }
        }
    }

    /**
     * Whether the row carries a value that could name or find this person: a name part or an
     * email. This is a narrower question than `describesPerson`, and deliberately so. A row that
     * maps only an address puts a value on the entity, so `describesPerson` says yes, but an
     * address on its own cannot create a person and cannot match one either, which is exactly what
     * `Core_Import_ErrorRowIdentifiesNobody` tells the administrator: no name, no email and no
     * organization means there is nothing to create or match. The organization side of that
     * sentence is `item.organizationKey`, which is already built from the organization name alone.
     */
    private static Boolean identifiesPerson(Working item, String entity) {
        Map<String, String> held = item.byEntity.get(entity);
        if (held == null) {
            return false;
        }
        for (String attribute : IDENTIFYING_ATTRIBUTES) {
            if (String.isNotBlank(held.get(attribute))) {
                return true;
            }
        }
        return false;
    }

    private static Boolean describesPerson(Working item, String entity) {
        Map<String, String> held = item.byEntity.get(entity);
        if (held == null) {
            return false;
        }
        for (String value : held.values()) {
            if (String.isNotBlank(value)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean hasLastName(Working item, String entity) {
        return String.isNotBlank(attribute(item.byEntity, entity, 'LastName'));
    }

    /**
     * On a dry run there is nothing to compare a matched person's stored values against
     * without reading them, so the preview reads them: the counts an administrator sees are
     * the counts the commit will produce.
     */
    private static void countUpdatesInPreview(List<Working> working, Boolean personAccounts) {
        Set<Id> matchedIds = new Set<Id>();
        for (Working item : working) {
            if (item.person1Id != null) {
                matchedIds.add(item.person1Id);
            }
            if (item.person2Id != null) {
                matchedIds.add(item.person2Id);
            }
        }
        Map<Id, SObject> stored = readStored(matchedIds, personAccounts, working);
        for (Working item : working) {
            if (item.error != null) {
                continue;
            }
            if (item.person1Id == null && describesPerson(item, ImportMapping.ENTITY_CONTACT_1)) {
                item.createdAnything = true;
            } else if (
                changes(
                    stored.get(item.person1Id),
                    item.byEntity.get(ImportMapping.ENTITY_CONTACT_1)
                )
            ) {
                item.updatedAnything = true;
            }
            if (item.person2Id == null && describesPerson(item, ImportMapping.ENTITY_CONTACT_2)) {
                item.createdAnything = true;
            } else if (
                changes(
                    stored.get(item.person2Id),
                    item.byEntity.get(ImportMapping.ENTITY_CONTACT_2)
                )
            ) {
                item.updatedAnything = true;
            }
        }
    }

    /**
     * Inserts the new people and updates the matched ones.
     *
     * The order is load bearing. The first person is saved first, because the household
     * trigger gives them a household on that save and the second person's household is the
     * one the first person ended up in: `resolveHouseholds` reads it back before the second
     * person is saved at all.
     *
     * The second person is then saved in two passes over the chunk, which is two saves and
     * not one per row. The people who are joining a household their row already knows are
     * saved with automatic creation suspended, so that nobody is given a household of their
     * own and then taken out of it again, and `joinSecondPeople` joins them afterwards.
     * Everybody else (a row whose first person is missing, or failed) is saved normally and
     * gets a household of their own, which is what a row describing one person means.
     */
    private static void savePeople(
        List<Working> working,
        Import_Batch__c batch,
        Boolean personAccounts,
        Outcome outcome
    ) {
        insertPeople(
            working,
            batch,
            personAccounts,
            ImportMapping.ENTITY_CONTACT_1,
            true,
            null,
            outcome
        );
        resolveHouseholds(working, personAccounts);
        HouseholdService.suspendAutomaticCreation();
        try {
            insertPeople(
                working,
                batch,
                personAccounts,
                ImportMapping.ENTITY_CONTACT_2,
                false,
                true,
                outcome
            );
        } finally {
            HouseholdService.resumeAutomaticCreation();
        }
        joinSecondPeople(working, outcome);
        insertPeople(
            working,
            batch,
            personAccounts,
            ImportMapping.ENTITY_CONTACT_2,
            false,
            false,
            outcome
        );
        resolveHouseholds(working, personAccounts);
        updateMatchedPeople(working, personAccounts, outcome);
    }

    /**
     * Joins each row's second person to the household its first person is in.
     *
     * Membership is never reimplemented here (R-M5). `HouseholdService.addMembers` is what
     * joining an existing household means, and it is the only thing that knows how this org
     * writes membership down: the person's own account reference in contact mode, a
     * `Household_Member__c` row in junction mode, for a person stored as a contact and for a
     * person stored as an account alike. The whole chunk is joined in one call, and the
     * write fires the trigger that recounts and renames the households it touched, exactly
     * as a join made by hand does.
     *
     * Only a person this run created is joined. A second person who matched somebody the org
     * already has keeps the household they already belong to: an import that names two
     * existing people on one line is not a licence to move one of them.
     */
    private static void joinSecondPeople(List<Working> working, Outcome outcome) {
        Map<Id, Set<Id>> peopleByHousehold = new Map<Id, Set<Id>>();
        for (Working item : working) {
            if (item.error != null || !item.createdPerson2 || item.person2Id == null) {
                continue;
            }
            if (item.row.Household__c == null) {
                continue;
            }
            if (!peopleByHousehold.containsKey(item.row.Household__c)) {
                peopleByHousehold.put(item.row.Household__c, new Set<Id>());
            }
            peopleByHousehold.get(item.row.Household__c).add(item.person2Id);
        }
        if (peopleByHousehold.isEmpty()) {
            return;
        }
        try {
            HouseholdService.addMembers(peopleByHousehold);
        } catch (Exception e) {
            // The people are saved and the rows say so. A household that could not be joined
            // is reported in the run log and in the Error Log rather than thrown, so one bad
            // household does not take the chunk with it (R-IB5).
            ErrorLogger.log(e, 'ImportRowProcessor.joinSecondPeople');
            outcome.notes.add(e.getMessage());
        }
    }

    /**
     * Inserts the people this chunk has to create for one entity.
     *
     * `joiningAHousehold` selects which of them: true is the people whose row already knows
     * the household they belong to, false is the people whose row does not, and null is
     * everybody, which is what the first person of a row always is.
     */
    private static void insertPeople(
        List<Working> working,
        Import_Batch__c batch,
        Boolean personAccounts,
        String entity,
        Boolean isFirst,
        Boolean joiningAHousehold,
        Outcome outcome
    ) {
        List<SObject> toCreate = new List<SObject>();
        List<Working> owners = new List<Working>();
        Id personRecordTypeId = personAccounts ? anyPersonRecordTypeId() : null;
        if (personAccounts && personRecordTypeId == null) {
            outcome.notes.add(Label.Core_Import_LogPersonRecordTypeMissing);
            return;
        }
        for (Working item : working) {
            if (item.error != null) {
                continue;
            }
            Id already = isFirst ? item.person1Id : item.person2Id;
            if (already != null || !describesPerson(item, entity)) {
                continue;
            }
            if (joiningAHousehold != null && joiningAHousehold != (item.row.Household__c != null)) {
                continue;
            }
            SObject person = personAccounts
                ? (SObject) new Account(RecordTypeId = personRecordTypeId)
                : (SObject) new Contact();
            Schema.SObjectType type = personAccounts ? Account.SObjectType : Contact.SObjectType;
            applyValues(person, type, item.byEntity.get(entity), new Set<String>(), outcome);
            person.put('Created_By_Import_Batch__c', batch.Id);
            // Nobody is saved into a household here. A person saved straight into a household
            // account is saying "contact mode", which is one of two ways an org can hold
            // membership, and the importer does not get to pick. The household itself is made
            // by the household trigger, and the second person is joined to the first person's
            // household by joinSecondPeople, through the service that knows which way this org
            // writes membership down.
            toCreate.add(person);
            owners.add(item);
        }
        if (toCreate.isEmpty()) {
            return;
        }
        List<Database.SaveResult> results = Database.insert(toCreate, false, AccessLevel.USER_MODE);
        for (Integer i = 0; i < results.size(); i++) {
            Working owner = owners[i];
            if (results[i].isSuccess()) {
                if (isFirst) {
                    owner.person1Id = results[i].getId();
                } else {
                    owner.person2Id = results[i].getId();
                    owner.createdPerson2 = true;
                }
                owner.createdAnything = true;
            } else {
                owner.error = message(results[i]);
            }
        }
    }

    /** Asks the household service which household each new person ended up in. */
    private static void resolveHouseholds(List<Working> working, Boolean personAccounts) {
        Set<Id> personIds = new Set<Id>();
        for (Working item : working) {
            if (item.row.Household__c == null && item.person1Id != null) {
                personIds.add(item.person1Id);
            }
        }
        if (personIds.isEmpty()) {
            return;
        }
        Map<Id, Id> households = HouseholdService.getHouseholdIdsFor(personIds);
        for (Working item : working) {
            if (item.row.Household__c == null && item.person1Id != null) {
                item.row.Household__c = households.get(item.person1Id);
            }
        }
    }

    private static void updateMatchedPeople(
        List<Working> working,
        Boolean personAccounts,
        Outcome outcome
    ) {
        Set<Id> matchedIds = new Set<Id>();
        for (Working item : working) {
            if (item.error != null) {
                continue;
            }
            if (item.person1Id != null && item.personKey1 != null) {
                matchedIds.add(item.person1Id);
            }
            if (item.person2Id != null && item.personKey2 != null) {
                matchedIds.add(item.person2Id);
            }
        }
        Map<Id, SObject> stored = readStored(matchedIds, personAccounts, working);
        Map<Id, SObject> toUpdate = new Map<Id, SObject>();
        Map<Id, List<Working>> ownersByRecord = new Map<Id, List<Working>>();
        Schema.SObjectType type = personAccounts ? Account.SObjectType : Contact.SObjectType;
        for (Working item : working) {
            if (item.error != null) {
                continue;
            }
            for (Integer which = 1; which <= 2; which++) {
                Id personId = which == 1 ? item.person1Id : item.person2Id;
                String entity = which == 1
                    ? ImportMapping.ENTITY_CONTACT_1
                    : ImportMapping.ENTITY_CONTACT_2;
                Map<String, String> held = item.byEntity.get(entity);
                SObject existing = stored.get(personId);
                if (personId == null || existing == null || !changes(existing, held)) {
                    continue;
                }
                SObject change = toUpdate.get(personId);
                if (change == null) {
                    change = type.newSObject(personId);
                    toUpdate.put(personId, change);
                }
                applyChanges(change, existing, type, held, outcome);
                if (!ownersByRecord.containsKey(personId)) {
                    ownersByRecord.put(personId, new List<Working>());
                }
                ownersByRecord.get(personId).add(item);
            }
        }
        if (toUpdate.isEmpty()) {
            return;
        }
        List<SObject> records = toUpdate.values();
        List<Database.SaveResult> results = Database.update(records, false, AccessLevel.USER_MODE);
        for (Integer i = 0; i < results.size(); i++) {
            for (Working owner : ownersByRecord.get(records[i].Id)) {
                if (results[i].isSuccess()) {
                    owner.updatedAnything = true;
                } else if (owner.error == null) {
                    owner.error = message(results[i]);
                }
            }
        }
    }

    /**
     * The mapped attributes as they currently stand on the matched records. Only the
     * attributes this mapping names are selected, and only those the object actually has, so
     * a template written for another org cannot produce an invalid query.
     */
    private static Map<Id, SObject> readStored(
        Set<Id> ids,
        Boolean personAccounts,
        List<Working> working
    ) {
        Map<Id, SObject> result = new Map<Id, SObject>();
        if (ids == null || ids.isEmpty()) {
            return result;
        }
        Schema.SObjectType type = personAccounts ? Account.SObjectType : Contact.SObjectType;
        Map<String, Schema.SObjectField> fields = type.getDescribe(SObjectDescribeOptions.DEFERRED)
            .fields.getMap();
        Set<String> selected = new Set<String>{ 'Id' };
        for (Working item : working) {
            for (
                String entity : new List<String>{
                    ImportMapping.ENTITY_CONTACT_1,
                    ImportMapping.ENTITY_CONTACT_2
                }
            ) {
                Map<String, String> held = item.byEntity.get(entity);
                if (held == null) {
                    continue;
                }
                for (String attributeName : held.keySet()) {
                    Schema.SObjectField field = fields.get(attributeName.toLowerCase());
                    if (field != null && field.getDescribe().isAccessible()) {
                        selected.add(field.getDescribe().getName());
                    }
                }
            }
        }
        String objectName = type.getDescribe(SObjectDescribeOptions.DEFERRED).getName();
        String query =
            'SELECT ' +
            String.join(new List<String>(selected), ', ') +
            ' FROM ' +
            objectName +
            ' WHERE Id IN :ids LIMIT 2000';
        for (
            SObject record : Database.queryWithBinds(
                query,
                new Map<String, Object>{ 'ids' => ids },
                AccessLevel.USER_MODE
            )
        ) {
            result.put((Id) record.get('Id'), record);
        }
        return result;
    }

    /** True when any mapped attribute would change the stored record. */
    private static Boolean changes(SObject stored, Map<String, String> held) {
        return !differences(stored, held).isEmpty();
    }

    /**
     * The mapped attributes whose incoming value differs from what is stored. A blank
     * incoming value never clears a stored one: an import adds what the file knows and does
     * not erase what it is silent about.
     */
    private static Map<String, String> differences(SObject stored, Map<String, String> held) {
        Map<String, String> result = new Map<String, String>();
        if (stored == null || held == null || held.isEmpty()) {
            return result;
        }
        Map<String, Object> populated = new Map<String, Object>();
        for (String name : stored.getPopulatedFieldsAsMap().keySet()) {
            populated.put(name.toLowerCase(), stored.getPopulatedFieldsAsMap().get(name));
        }
        for (String attributeName : held.keySet()) {
            String incoming = held.get(attributeName);
            String lookupKey = attributeName.toLowerCase();
            // A field that was not selected cannot be compared, so it is not claimed as a
            // change: saying "would update" about something unread would be a lie.
            if (String.isBlank(incoming) || !populated.containsKey(lookupKey)) {
                continue;
            }
            Object current = populated.get(lookupKey);
            String currentText = current == null ? '' : String.valueOf(current);
            if (!currentText.equalsIgnoreCase(incoming)) {
                result.put(attributeName, incoming);
            }
        }
        return result;
    }

    private static void applyChanges(
        SObject change,
        SObject stored,
        Schema.SObjectType type,
        Map<String, String> held,
        Outcome outcome
    ) {
        applyValues(change, type, differences(stored, held), new Set<String>(), outcome);
    }

    // -------------------------------------------------------------------------------------
    // Households
    // -------------------------------------------------------------------------------------

    /** Applies the row's household attributes to the household its first person is in. */
    private static void applyHouseholdValues(List<Working> working, Boolean dryRun) {
        if (dryRun) {
            return;
        }
        Map<Id, Account> byHousehold = new Map<Id, Account>();
        for (Working item : working) {
            Map<String, String> held = item.byEntity.get(ImportMapping.ENTITY_HOUSEHOLD);
            if (
                item.error != null ||
                item.row.Household__c == null ||
                held == null ||
                held.isEmpty()
            ) {
                continue;
            }
            String name = held.get('Name');
            if (String.isBlank(name)) {
                continue;
            }
            // Naming the household by hand is exactly what the custom name flag means, so the
            // naming service leaves it alone from here on.
            byHousehold.put(
                item.row.Household__c,
                new Account(Id = item.row.Household__c, Name = name, Custom_Name__c = true)
            );
        }
        if (byHousehold.isEmpty()) {
            return;
        }
        List<Account> records = byHousehold.values();
        List<Database.SaveResult> results = Database.update(records, false, AccessLevel.USER_MODE);
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                continue;
            }
            for (Working item : working) {
                if (item.row.Household__c == records[i].Id && item.error == null) {
                    item.error = message(results[i]);
                }
            }
        }
    }

    // -------------------------------------------------------------------------------------
    // The rest of the row
    // -------------------------------------------------------------------------------------

    /**
     * Offers the chunk to the entity processor a dependent package may have registered
     * (R-IR6). Nothing here fails an import: an absent processor is the normal case, and a
     * processor that throws is logged and reported in the run log, not raised.
     */
    private static void offerToEntityProcessor(
        Import_Batch__c batch,
        ImportMapping mapping,
        List<Import_Row__c> rows,
        List<Working> working,
        Boolean dryRun,
        Outcome outcome
    ) {
        if (mapping.deferredEntities().isEmpty()) {
            return;
        }
        Type handler = Type.forName(NamespaceUtil.qualify(ENTITY_PROCESSOR_CLASS));
        if (handler == null) {
            return;
        }
        try {
            ImportEntityProcessor processor = (ImportEntityProcessor) handler.newInstance();
            Map<Id, Map<String, String>> valuesByRowId = new Map<Id, Map<String, String>>();
            for (Working item : working) {
                valuesByRowId.put(item.row.Id, item.values);
            }
            String note = processor.resolve(batch, mapping, rows, valuesByRowId, dryRun);
            if (String.isNotBlank(note)) {
                outcome.notes.add(note);
            }
        } catch (Exception e) {
            ErrorLogger.log(e, 'ImportRowProcessor.offerToEntityProcessor');
            outcome.notes.add(e.getMessage());
        }
    }

    // -------------------------------------------------------------------------------------
    // Writing the rows back
    // -------------------------------------------------------------------------------------

    private static void writeBack(List<Working> working, Outcome outcome) {
        List<Import_Row__c> rows = new List<Import_Row__c>();
        for (Working item : working) {
            Import_Row__c row = item.row;
            Boolean personAccountRow =
                item.person1Id != null &&
                item.person1Id.getSObjectType() == Account.SObjectType;
            if (item.error != null) {
                row.Status__c = STATUS_REJECTED;
                row.Error_Message__c = item.error.abbreviate(4000);
                outcome.rejected++;
            } else {
                row.Error_Message__c = null;
                if (personAccountRow) {
                    row.Person_1_Account__c = item.person1Id;
                    row.Person_2_Account__c = item.person2Id;
                } else {
                    row.Contact_1__c = item.person1Id;
                    row.Contact_2__c = item.person2Id;
                }
                row.Organization__c = item.organizationId;
                if (item.createdAnything) {
                    row.Status__c = STATUS_CREATED;
                    outcome.created++;
                } else if (item.updatedAnything) {
                    row.Status__c = STATUS_UPDATED;
                    outcome.updated++;
                } else {
                    row.Status__c = STATUS_MATCHED;
                    outcome.matched++;
                }
            }
            rows.add(row);
        }
        if (rows.isEmpty()) {
            return;
        }
        // The staged rows are the package's own bookkeeping and must record what happened even
        // where the running user cannot edit them, for the reason ADR-0021 gives.
        Database.update(rows, false, AccessLevel.SYSTEM_MODE);
    }

    // -------------------------------------------------------------------------------------
    // Shared helpers
    // -------------------------------------------------------------------------------------

    /**
     * Copies the mapped attributes onto a record, skipping any the object does not have or
     * the user may not write. An unknown attribute is reported once in the run log rather
     * than failing the row: a template written for another org should not stop this one.
     */
    private static void applyValues(
        SObject record,
        Schema.SObjectType type,
        Map<String, String> held,
        Set<String> alreadySet,
        Outcome outcome
    ) {
        if (held == null || held.isEmpty()) {
            return;
        }
        Map<String, Schema.SObjectField> fields = type.getDescribe(SObjectDescribeOptions.DEFERRED)
            .fields.getMap();
        for (String attributeName : held.keySet()) {
            if (alreadySet.contains(attributeName)) {
                continue;
            }
            String value = held.get(attributeName);
            if (String.isBlank(value)) {
                continue;
            }
            Schema.SObjectField field = fields.get(attributeName.toLowerCase());
            if (field == null) {
                outcome.notes.add(
                    String.format(
                        Label.Core_Import_LogAttributeUnknown,
                        new List<String>{ attributeName }
                    )
                );
                continue;
            }
            Schema.DescribeFieldResult describe = field.getDescribe();
            if (!describe.isCreateable() && !describe.isUpdateable()) {
                continue;
            }
            try {
                record.put(describe.getSObjectField(), convert(value, describe));
            } catch (Exception ignored) {
                outcome.notes.add(
                    String.format(
                        Label.Core_Import_LogValueNotAccepted,
                        new List<String>{ attributeName, value }
                    )
                );
            }
        }
    }

    /** A column value as the field's type, for the few types a spreadsheet carries. */
    private static Object convert(String value, Schema.DescribeFieldResult describe) {
        Schema.DisplayType kind = describe.getType();
        if (kind == Schema.DisplayType.BOOLEAN) {
            return 'true'.equalsIgnoreCase(value) ||
                'yes'.equalsIgnoreCase(value) ||
                '1'.equals(value);
        }
        if (
            kind == Schema.DisplayType.CURRENCY ||
            kind == Schema.DisplayType.DOUBLE ||
            kind == Schema.DisplayType.PERCENT
        ) {
            return Decimal.valueOf(value.replaceAll('[^0-9\\.\\-]', ''));
        }
        if (kind == Schema.DisplayType.INTEGER) {
            return Integer.valueOf(value.replaceAll('[^0-9\\-]', ''));
        }
        if (kind == Schema.DisplayType.DATE) {
            return Date.valueOf(value);
        }
        if (kind == Schema.DisplayType.DATETIME) {
            return Datetime.valueOf(value);
        }
        Integer length = describe.getLength();
        return length > 0 ? value.abbreviate(Math.max(length, 4)) : value;
    }

    /** The failure of a save, in the words the platform used, so nothing is lost in paraphrase. */
    private static String message(Database.SaveResult result) {
        List<String> parts = new List<String>();
        for (Database.Error error : result.getErrors()) {
            parts.add(error.getMessage());
        }
        return parts.isEmpty() ? Label.Core_Import_ErrorSaveFailed : String.join(parts, ' ');
    }

    private static Id recordTypeId(String developerName) {
        Schema.RecordTypeInfo info = Account.SObjectType.getDescribe(
                SObjectDescribeOptions.DEFERRED
            )
            .getRecordTypeInfosByDeveloperName()
            .get(developerName);
        return info == null || !info.isAvailable() ? null : info.getRecordTypeId();
    }

    private static Set<Id> personRecordTypeIds() {
        return OrgShapeDetector.detect().personAccountRecordTypeIds;
    }

    private static Id anyPersonRecordTypeId() {
        for (Id recordTypeId : personRecordTypeIds()) {
            return recordTypeId;
        }
        return null;
    }
}

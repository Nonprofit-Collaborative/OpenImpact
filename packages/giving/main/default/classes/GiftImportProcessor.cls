/**
 * Giving's part of Core's importer (features G-23 and G-24, canonical model Section 25N): the
 * `ImportEntityProcessor` Core finds by this class name (R-IR6, ADR-0017) and offers each
 * chunk after it has resolved the people, households and organizations.
 *
 * A row's gift is created only through Giving's own path, the one gift batch entry uses:
 * a user-mode insert with Status Received, then the chosen fund applied with
 * `GiftService.applyChosenFunds`, or a split saved with the default allocation suppressed
 * (R-GI4). A row's gift is saved whole or not at all (R-GI7), and every gift carries the
 * import's tag so an undo can remove it (R-IB3).
 */
@NamespaceAccessible
public with sharing class GiftImportProcessor implements ImportEntityProcessor {
    private static final String STATUS_RECEIVED = 'Received';

    @NamespaceAccessible
    public GiftImportProcessor() {
        // Built by name through Type.forName, which needs a constructor it can reach.
    }

    // -------------------------------------------------------------------------------------
    // The column picker
    // -------------------------------------------------------------------------------------

    /** The columns this processor loads, in the order the picker offers them. */
    public List<ImportMapping.Target> targets() {
        List<ImportMapping.Target> result = new List<ImportMapping.Target>{
            target('Gift.Amount__c', Label.Giving_Import_TargetAmount),
            target('Gift.Gift_Date__c', Label.Giving_Import_TargetDate),
            target('Gift.Type__c', Label.Giving_Import_TargetType),
            target('Gift.Payment_Reference__c', Label.Giving_Import_TargetPaymentReference),
            target('Gift.External_Id__c', Label.Giving_Import_TargetExternalId),
            target('Gift.Appeal', Label.Giving_Import_TargetAppeal),
            target('Gift.Donor', Label.Giving_Import_TargetDonor),
            target('Gift.In_Kind_Description__c', Label.Giving_Import_TargetInKindDescription),
            target('Gift.Fair_Market_Value__c', Label.Giving_Import_TargetFairMarketValue),
            target('Gift.Benefit_Description__c', Label.Giving_Import_TargetBenefitDescription),
            target('Allocation.Fund', Label.Giving_Import_TargetFund)
        };
        for (Integer index = 1; index <= GiftImportRow.MAX_PARTS; index++) {
            List<String> partNumber = new List<String>{ String.valueOf(index) };
            result.add(
                target(
                    'Allocation.Fund' + index,
                    String.format(Label.Giving_Import_TargetFundPart, partNumber)
                )
            );
            result.add(
                target(
                    'Allocation.Amount' + index,
                    String.format(Label.Giving_Import_TargetAmountPart, partNumber)
                )
            );
            result.add(
                target(
                    'Allocation.Percent' + index,
                    String.format(Label.Giving_Import_TargetPercentPart, partNumber)
                )
            );
        }
        return result;
    }

    private static ImportMapping.Target target(String value, String label) {
        return new ImportMapping.Target(value, label);
    }

    // -------------------------------------------------------------------------------------
    // One chunk
    // -------------------------------------------------------------------------------------

    /**
     * Reads, checks and (unless a dry run) saves each row's gift, and reports on each row
     * (R-IR7). Nothing is thrown: a failure belongs on the row it came from.
     */
    public ImportEntityResult resolve(
        Import_Batch__c batch,
        Import_Template__c template,
        List<Import_Row__c> rows,
        Map<Id, Map<String, Map<String, String>>> entitiesByRowId,
        Boolean dryRun
    ) {
        Decimal fileAmount;
        Set<String> notLoaded = new Set<String>();
        List<GiftImportRow> gifts = new List<GiftImportRow>();
        for (Import_Row__c row : rows) {
            GiftImportRow read = new GiftImportRow(row, entitiesByRowId.get(row.Id));
            if (read.readableAmount != null) {
                // Every readable amount counts, rejected rows too: the control total asks
                // whether this is the file on paper (R-GI8, R-IB10).
                fileAmount = (fileAmount == null ? 0 : fileAmount) + read.readableAmount;
            }
            if (!read.carriesGift || ImportRowProcessor.STATUS_REJECTED.equals(row.Status__c)) {
                continue;
            }
            notLoaded.addAll(read.notLoaded);
            gifts.add(read);
        }
        List<String> notes = new List<String>();
        if (!gifts.isEmpty() && !Schema.SObjectType.Gift__c.isDeletable()) {
            // A row is saved whole or not at all, which means deleting a gift whose credit or
            // tribute was refused. Without that right a half-saved gift would stay behind, so
            // the import is refused before anything is written, in the dry run too.
            refuseAll(gifts, Label.Giving_Import_ErrorCannotDeleteGifts);
            notes.add(Label.Giving_Import_ErrorCannotDeleteGifts);
        }
        if (!gifts.isEmpty()) {
            matchExternalIds(pending(gifts));
            resolveDonors(pending(gifts), dryRun);
            GiftImportReferences.resolve(pending(gifts));
            if (!dryRun) {
                save(batch, pending(gifts));
            }
            // A repeat of an earlier row shares its outcome, in the dry run as in the commit.
            shareWithEarlierRows(gifts);
            report(gifts);
        }
        if (!notLoaded.isEmpty()) {
            notes.add(
                String.format(
                    Label.Giving_Import_LogAttributesNotLoaded,
                    new List<String>{ String.join(new List<String>(notLoaded), ', ') }
                )
            );
        }
        return new ImportEntityResult(notes.isEmpty() ? null : String.join(notes, ' '), fileAmount);
    }

    private static void refuseAll(List<GiftImportRow> gifts, String reason) {
        for (GiftImportRow item : gifts) {
            if (item.error == null) {
                item.error = reason;
            }
        }
    }

    /** The rows still on their way to a gift: not refused, and not matched to one. */
    private static List<GiftImportRow> pending(List<GiftImportRow> gifts) {
        List<GiftImportRow> result = new List<GiftImportRow>();
        for (GiftImportRow item : gifts) {
            if (item.error == null && !item.matchedExisting) {
                result.add(item);
            }
        }
        return result;
    }

    /** Writes each row's outcome where Core reads it (R-IR7). */
    private static void report(List<GiftImportRow> gifts) {
        for (GiftImportRow item : gifts) {
            if (item.error != null) {
                item.row.Status__c = ImportRowProcessor.STATUS_REJECTED;
                item.row.Error_Message__c = item.error.abbreviate(4000);
            } else {
                item.row.Status__c = item.matchedExisting
                    ? ImportRowProcessor.STATUS_MATCHED
                    : ImportRowProcessor.STATUS_CREATED;
                item.row.Gift_Id__c = item.giftId;
            }
        }
    }

    // -------------------------------------------------------------------------------------
    // The donor (R-GI2)
    // -------------------------------------------------------------------------------------

    /**
     * The row's first person gives the gift, or else its organization, unless `Gift.Donor`
     * says otherwise. In a dry run a donor Core would create has no identifier yet; the row
     * still counts as a gift that would be created.
     */
    private static void resolveDonors(List<GiftImportRow> gifts, Boolean dryRun) {
        for (GiftImportRow item : gifts) {
            if (item.error != null) {
                continue;
            }
            Import_Row__c row = item.row;
            Id person = row.Contact_1__c != null ? row.Contact_1__c : row.Person_1_Account__c;
            Boolean personComing =
                dryRun &&
                person == null &&
                item.names(ImportMapping.ENTITY_CONTACT_1);
            Boolean organizationComing =
                dryRun &&
                row.Organization__c == null &&
                item.names(ImportMapping.ENTITY_ORGANIZATION);
            String choice = item.donorChoice;
            if (choice == null) {
                choice = person != null || personComing
                    ? GiftImportRow.DONOR_CONTACT_1
                    : row.Organization__c != null || organizationComing
                          ? GiftImportRow.DONOR_ORGANIZATION
                          : null;
            }
            if (choice == null) {
                item.error = Label.Giving_Import_ErrorNoDonor;
            } else if (choice == GiftImportRow.DONOR_CONTACT_1) {
                if (row.Contact_1__c != null) {
                    item.donorContactId = row.Contact_1__c;
                } else if (row.Person_1_Account__c != null) {
                    item.donorAccountId = row.Person_1_Account__c;
                } else if (!personComing) {
                    item.error = Label.Giving_Import_ErrorDonorPersonMissing;
                }
            } else if (choice == GiftImportRow.DONOR_ORGANIZATION) {
                item.donorAccountId = row.Organization__c;
                if (row.Organization__c == null && !organizationComing) {
                    item.error = Label.Giving_Import_ErrorDonorOrganizationMissing;
                }
            } else {
                item.donorAccountId = row.Household__c;
                if (row.Household__c == null && !personComing) {
                    item.error = Label.Giving_Import_ErrorDonorHouseholdMissing;
                }
            }
        }
    }

    // -------------------------------------------------------------------------------------
    // Gifts already loaded (R-DM1)
    // -------------------------------------------------------------------------------------

    /**
     * A row whose external ID names a gift already in the org, or one an earlier row of this
     * chunk makes, is that gift: the row is Matched and the gift is not changed.
     */
    private static void matchExternalIds(List<GiftImportRow> gifts) {
        Set<String> externalIds = new Set<String>();
        for (GiftImportRow item : gifts) {
            if (item.externalId != null) {
                externalIds.add(item.externalId);
            }
        }
        if (externalIds.isEmpty()) {
            return;
        }
        Map<String, Id> existing = new Map<String, Id>();
        for (Gift__c gift : GiftImportIntegritySelector.selectByExternalIds(externalIds)) {
            existing.put(gift.External_Id__c.toLowerCase(), gift.Id);
        }
        Map<String, GiftImportRow> firstInChunk = new Map<String, GiftImportRow>();
        for (GiftImportRow item : gifts) {
            if (item.externalId == null) {
                continue;
            }
            String key = item.externalId.toLowerCase();
            if (existing.containsKey(key)) {
                item.matchedExisting = true;
                item.giftId = existing.get(key);
            } else if (firstInChunk.containsKey(key)) {
                item.matchedExisting = true;
                item.sameAs = firstInChunk.get(key);
            } else {
                firstInChunk.put(key, item);
            }
        }
    }

    // -------------------------------------------------------------------------------------
    // Saving (R-GI4, R-GI7)
    // -------------------------------------------------------------------------------------

    /**
     * Creates the gifts: those with a split with the default allocation suppressed, the
     * others with it, then the chosen fund or the split's parts. A row whose gift was saved but
     * whose allocations were not has its gift deleted, so it never leaves half a gift.
     */
    private static void save(Import_Batch__c batch, List<GiftImportRow> gifts) {
        List<GiftImportRow> whole = new List<GiftImportRow>();
        List<GiftImportRow> split = new List<GiftImportRow>();
        for (GiftImportRow item : gifts) {
            if (item.isSplit()) {
                split.add(item);
            } else {
                whole.add(item);
            }
        }
        insertGifts(batch, whole, false);
        insertGifts(batch, split, true);
        applyFunds(saved(whole));
        insertParts(saved(split));
        undoTheUnfinished(gifts);
    }

    /** A row repeating an earlier row's external ID shares that row's gift, or its refusal. */
    private static void shareWithEarlierRows(List<GiftImportRow> gifts) {
        for (GiftImportRow item : gifts) {
            if (item.sameAs != null && item.error == null) {
                item.giftId = item.sameAs.giftId;
                item.error = item.sameAs.error;
            }
        }
    }

    private static List<GiftImportRow> saved(List<GiftImportRow> gifts) {
        List<GiftImportRow> result = new List<GiftImportRow>();
        for (GiftImportRow item : gifts) {
            if (item.error == null && item.giftId != null) {
                result.add(item);
            }
        }
        return result;
    }

    private static void insertGifts(
        Import_Batch__c batch,
        List<GiftImportRow> gifts,
        Boolean split
    ) {
        if (gifts.isEmpty()) {
            return;
        }
        List<Gift__c> records = new List<Gift__c>();
        for (GiftImportRow item : gifts) {
            records.add(build(batch, item));
        }
        Boolean callerSuppression = GiftService.suppressDefaultAllocations;
        List<Database.SaveResult> results;
        try {
            GiftService.suppressDefaultAllocations = split || callerSuppression;
            results = Database.insert(records, false, AccessLevel.USER_MODE);
        } finally {
            GiftService.suppressDefaultAllocations = callerSuppression;
        }
        for (Integer index = 0; index < results.size(); index++) {
            if (results[index].isSuccess()) {
                gifts[index].giftId = records[index].Id;
            } else {
                gifts[index].error = failure(results[index].getErrors());
            }
        }
    }

    private static Gift__c build(Import_Batch__c batch, GiftImportRow item) {
        Gift__c gift = new Gift__c(
            Donor_Contact__c = item.donorContactId,
            Donor_Account__c = item.donorAccountId,
            Amount__c = item.amount,
            Gift_Date__c = item.giftDate,
            Status__c = STATUS_RECEIVED,
            Appeal__c = item.appealId,
            Created_By_Import_Batch__c = batch.Id
        );
        for (Schema.SObjectField field : item.values.keySet()) {
            gift.put(field, item.values.get(field));
        }
        return gift;
    }

    /** The single chosen fund, applied the way every entry screen applies it. */
    private static void applyFunds(List<GiftImportRow> gifts) {
        List<Gift__c> records = new List<Gift__c>();
        Map<Id, Id> fundIdByGiftId = new Map<Id, Id>();
        Map<Id, GiftImportRow> byGiftId = new Map<Id, GiftImportRow>();
        for (GiftImportRow item : gifts) {
            if (item.singleFund == null) {
                continue;
            }
            records.add(new Gift__c(Id = item.giftId, Amount__c = item.amount));
            fundIdByGiftId.put(item.giftId, item.singleFund.fundId);
            byGiftId.put(item.giftId, item);
        }
        if (records.isEmpty()) {
            return;
        }
        Savepoint beforeFunds = Database.setSavepoint();
        try {
            refuseNotApplied(applyChosenFunds(records, fundIdByGiftId), byGiftId);
        } catch (Exception refused) {
            // The designation is all or nothing across the chunk, so one refused gift would
            // take every other with it. Undo the attempt and apply each gift on its own, so
            // only the gift the platform refuses loses its row. The rollback matters: a
            // designation can fail after part of it was written.
            Database.rollback(beforeFunds);
            applyOneByOne(records, fundIdByGiftId, byGiftId);
        }
    }

    /**
     * Each gift's fund on its own, each attempt undone if it fails, while the transaction has
     * room: a gift the chunk has no room left for is not attempted and says so, rather than
     * risking a limit that would fail every row.
     */
    private static void applyOneByOne(
        List<Gift__c> records,
        Map<Id, Id> fundIdByGiftId,
        Map<Id, GiftImportRow> byGiftId
    ) {
        for (Gift__c record : records) {
            GiftImportRow item = byGiftId.get(record.Id);
            if (!hasRoomForOneMore()) {
                item.error = Label.Giving_Import_ErrorNotAttempted;
                continue;
            }
            Savepoint beforeThisGift = Database.setSavepoint();
            try {
                refuseNotApplied(
                    applyChosenFunds(
                        new List<Gift__c>{ record },
                        new Map<Id, Id>{ record.Id => fundIdByGiftId.get(record.Id) }
                    ),
                    byGiftId
                );
            } catch (Exception rowRefused) {
                Database.rollback(beforeThisGift);
                item.error = String.format(
                    Label.Giving_Import_ErrorFailed,
                    new List<String>{ rowRefused.getMessage() }
                );
            }
        }
    }

    /** Kept free for the rest of the chunk's work; a test raises it to run out of room. */
    @TestVisible
    private static Integer queriesKeptFree = 30;
    @TestVisible
    private static Integer statementsKeptFree = 20;

    /** Room for one more gift's designation and for the rest of the chunk's work after it. */
    private static Boolean hasRoomForOneMore() {
        return Limits.getLimitQueries() - Limits.getQueries() > queriesKeptFree &&
            Limits.getLimitDmlStatements() - Limits.getDmlStatements() > statementsKeptFree &&
            Limits.getCpuTime() < Limits.getLimitCpuTime() * 0.7;
    }

    /**
     * Funds a test makes the platform refuse. The refusal comes after the designation and
     * after a record of its own is written, so a test can see that a failed attempt leaves
     * nothing behind.
     */
    @TestVisible
    private static Set<Id> fundsRefusedForTest = new Set<Id>();
    @TestVisible
    private static final String WRITTEN_BEFORE_REFUSAL = 'Written before the refusal';

    private static Set<Id> applyChosenFunds(List<Gift__c> records, Map<Id, Id> fundIdByGiftId) {
        Set<Id> notApplied = GiftService.applyChosenFunds(records, fundIdByGiftId);
        for (Id fundId : fundIdByGiftId.values()) {
            if (fundsRefusedForTest.contains(fundId)) {
                Database.insert(
                    new Fund__c(Name = WRITTEN_BEFORE_REFUSAL, Active__c = false),
                    true,
                    AccessLevel.USER_MODE
                );
                throw new DmlException('Refused for the test.');
            }
        }
        return notApplied;
    }

    private static void refuseNotApplied(Set<Id> notApplied, Map<Id, GiftImportRow> byGiftId) {
        for (Id giftId : notApplied) {
            byGiftId.get(giftId).error = Label.Giving_GiftBatch_ErrorPostFailed;
        }
    }

    /** A split's parts, all saved together so the allocation total rule sees them whole. */
    private static void insertParts(List<GiftImportRow> gifts) {
        List<Gift_Allocation__c> records = new List<Gift_Allocation__c>();
        List<GiftImportRow> owners = new List<GiftImportRow>();
        for (GiftImportRow item : gifts) {
            for (GiftImportRow.Part part : item.parts) {
                records.add(
                    new Gift_Allocation__c(
                        Gift__c = item.giftId,
                        Fund__c = part.fundId,
                        Amount__c = part.amount,
                        Percent__c = part.percent
                    )
                );
                owners.add(item);
            }
        }
        if (records.isEmpty()) {
            return;
        }
        List<Database.SaveResult> results = Database.insert(records, false, AccessLevel.USER_MODE);
        for (Integer index = 0; index < results.size(); index++) {
            if (!results[index].isSuccess() && owners[index].error == null) {
                owners[index].error = failure(results[index].getErrors());
            }
        }
    }

    /** Deletes each gift whose row failed after it was saved (R-GI7). */
    private static void undoTheUnfinished(List<GiftImportRow> gifts) {
        List<Gift__c> unfinished = new List<Gift__c>();
        for (GiftImportRow item : gifts) {
            if (item.error != null && item.giftId != null) {
                unfinished.add(new Gift__c(Id = item.giftId));
                item.giftId = null;
            }
        }
        if (!unfinished.isEmpty()) {
            List<Database.DeleteResult> results = Database.delete(
                unfinished,
                false,
                AccessLevel.USER_MODE
            );
            for (Database.DeleteResult result : results) {
                if (!result.isSuccess()) {
                    ErrorLogger.log(
                        new DmlException(failure(result.getErrors())),
                        'GiftImportProcessor.undoTheUnfinished',
                        result.getId()
                    );
                }
            }
        }
    }

    private static String failure(List<Database.Error> errors) {
        List<String> messages = new List<String>();
        for (Database.Error error : errors) {
            messages.add(error.getMessage());
        }
        return String.format(
            Label.Giving_Import_ErrorFailed,
            new List<String>{ String.join(messages, ' ') }
        );
    }

    // -------------------------------------------------------------------------------------
    // Undo (R-GI9)
    // -------------------------------------------------------------------------------------

    /** The objects this processor tags: gifts, whose allocations and credits go with them. */
    public List<Schema.SObjectType> taggedObjects() {
        return new List<Schema.SObjectType>{ Gift__c.SObjectType };
    }

    /** Why records must survive an undo: nothing yet beyond Core's own checks. */
    public Map<Id, String> reasonsToKeep(Id batchId, Schema.SObjectType type, Set<Id> recordIds) {
        return new Map<Id, String>();
    }
}

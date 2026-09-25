/**
 * The Opportunity mirror, Gifts to Opportunities (feature X-01, canonical model Section 29C,
 * ADR-NEXT on the Opportunity mirror): a one-way copy of each gift in the totals to a standard
 * Salesforce Opportunity with its primary contact role.
 *
 * Two callers share one copy, as in Campaign sync. The `Opportunity_Mirror` automation calls
 * `syncBeforeSave` while a gift is being saved, so a new Opportunity's identifier is stored with
 * the gift in the same save (R-OM4). `OpportunityMirrorBatch` calls `syncSaved` for a run, and
 * stores the new links itself (R-OM8).
 *
 * Opportunity and its contact roles are reached only through describe and SObject generics, so
 * Connect installs and this class compiles where they do not exist; there the mirror does
 * nothing (plan Section 4.2, R-OM1).
 *
 * Every write is in user mode with partial success (R-OM5, R-OM6): Opportunity is a standard
 * object the package does not own, and an Opportunity the platform refuses must never refuse the
 * gift. Refusals are grouped by the platform's message and written in one statement at the end
 * of the call, or handed to the run to write when it ends.
 */
public with sharing class OpportunityMirrorService {
    /** The registry name of the automation, used to bypass it while a run stores links. */
    public static final String AUTOMATION_NAME = 'Opportunity_Mirror';
    public static final String OFF = 'Off';
    public static final String GIFTS_TO_OPPORTUNITIES = 'GiftsToOpportunities';
    public static final String OPPORTUNITIES_TO_GIFTS = 'OpportunitiesToGifts';
    public static final String CONTEXT = 'Opportunity mirror';

    /** The statuses that count in the giving totals (ADR-0022), which are the ones copied. */
    public static final Set<String> IN_TOTALS = new Set<String>{
        'Received',
        'Refunded',
        'Written off'
    };

    // detection-only: Opportunity is resolved through describe so Connect installs without it
    private static final String OPPORTUNITY_OBJECT = 'Opportunity';
    // detection-only: its contact roles are resolved the same way
    private static final String ROLE_OBJECT = 'OpportunityContactRole';
    private static final String CAMPAIGN_FIELD = 'CampaignId';
    private static final String DONATION_RECORD_TYPE = 'Donation';
    private static final String DONOR_ROLE = 'Donor';
    private static final String WON_STAGE = 'Closed Won';
    private static final String LOST_STAGE = 'Closed Lost';

    /** What one copy costs at most: six reads, and two Opportunity and two role writes. */
    private static final Integer QUERIES_NEEDED = 6;
    private static final Integer DML_STATEMENTS_NEEDED = 4;
    /** The org's own Opportunity automation runs inside the gift's save (ADR-NEXT). */
    private static final Decimal CPU_SHARE_NEEDED = 0.4;

    /** The Opportunity field each copied gift attribute is compared on (R-OM3). */
    private static final List<String> COMPARED = new List<String>{
        'Amount',
        'CloseDate',
        'StageName',
        'AccountId'
    };
    /** The gift attributes whose change starts a copy. */
    private static final List<Schema.SObjectField> WATCHED = new List<Schema.SObjectField>{
        Gift__c.Amount__c,
        Gift__c.Gift_Date__c,
        Gift__c.Status__c,
        Gift__c.Donor_Contact__c,
        Gift__c.Donor_Account__c,
        Gift__c.Household__c,
        Gift__c.Appeal__c,
        Gift__c.Opportunity_Id__c
    };

    private static Schema.SObjectType resolvedOpportunity;
    private static Schema.SObjectType resolvedRole;
    private static Boolean typesResolved = false;
    private static Map<Boolean, String> stageByWon;

    /** Each once-per-transaction Warning, so a large save does not write it per chunk. */
    private static Boolean noAccessLogged = false;
    private static Boolean noHeadroomLogged = false;

    /** What one call did, for the run summary and the tests. */
    public class Result {
        public Integer created = 0;
        public Integer updated = 0;
        public Integer unchanged = 0;
        public Integer failed = 0;
        public Integer skipped = 0;
        /** The refusals, grouped by message; written by the caller (R-OM6). */
        public ConnectSync.Warnings refusals = new ConnectSync.Warnings();

        public void add(Result other) {
            created += other.created;
            updated += other.updated;
            unchanged += other.unchanged;
            failed += other.failed;
            skipped += other.skipped;
            refusals.addAll(other.refusals);
        }

        /** Writes the grouped refusals as Warnings, in one statement. */
        public void writeRefusals() {
            refusals.write(
                CONTEXT,
                Label.Connect_OpportunityMirror_LogOne,
                Label.Connect_OpportunityMirror_LogMany
            );
        }
    }

    // ------------------------------------------------------------------ what the org allows

    /** The Opportunity object, or null in an org without it (a Platform-only org). */
    public static Schema.SObjectType opportunityType() {
        resolveTypes();
        return resolvedOpportunity;
    }

    private static Schema.SObjectType roleType() {
        resolveTypes();
        return resolvedRole;
    }

    private static void resolveTypes() {
        if (!typesResolved) {
            Map<String, Schema.SObjectType> globals = Schema.getGlobalDescribe();
            resolvedOpportunity = globals.get(OPPORTUNITY_OBJECT);
            resolvedRole = globals.get(ROLE_OBJECT);
            typesResolved = true;
        }
    }

    public static Boolean isAvailable() {
        return opportunityType() != null && roleType() != null;
    }

    /** The chosen direction: Off, GiftsToOpportunities or OpportunitiesToGifts (R-OM1). */
    public static String direction() {
        Connect_Settings__c settings = Connect_Settings__c.getOrgDefaults();
        String chosen = settings == null ? null : settings.Opportunity_Mirror_Direction__c;
        return String.isBlank(chosen) ? OFF : chosen;
    }

    /** Whether gifts are copied to Opportunities in this org. */
    public static Boolean copiesGifts() {
        return isAvailable() && direction() == GIFTS_TO_OPPORTUNITIES;
    }

    /**
     * Whether the running user can make the copy at all: create and edit Opportunities, and read
     * and edit the gift's Opportunity ID, which the Opportunity Mirror permission set grants.
     */
    public static Boolean canCopy() {
        if (!isAvailable()) {
            return false;
        }
        Schema.DescribeSObjectResult opportunity = opportunityType().getDescribe();
        Schema.DescribeFieldResult link = Gift__c.Opportunity_Id__c.getDescribe();
        return opportunity.isCreateable() &&
            opportunity.isUpdateable() &&
            link.isAccessible() &&
            link.isUpdateable();
    }

    // ------------------------------------------------------------------------- the two callers

    /**
     * The automation's path: gifts in a before-insert or before-update context. New links are
     * written onto the records being saved. Never throws: whatever goes wrong is logged and the
     * gift saves (R-OM6).
     *
     * @param gifts the gifts being saved
     * @param oldById their previous values, or null on insert
     */
    public static Result syncBeforeSave(List<Gift__c> gifts, Map<Id, Gift__c> oldById) {
        Result result = new Result();
        if (gifts == null || gifts.isEmpty() || !copiesGifts()) {
            return result;
        }
        List<Gift__c> scope = new List<Gift__c>();
        for (Gift__c gift : gifts) {
            if (gift.hasErrors() || !normalizeLink(gift)) {
                continue;
            }
            Gift__c old = oldById == null ? null : oldById.get(gift.Id);
            if (inScope(gift, old)) {
                scope.add(gift);
            }
        }
        if (scope.isEmpty()) {
            return result;
        }
        if (!canCopy()) {
            result.skipped = scope.size();
            logNoAccess(scope.size(), oldById == null);
            return result;
        }
        if (!hasHeadroom(scope.size())) {
            // A save too large to copy is left to the next run rather than failed (R-OM6).
            result.skipped = scope.size();
            if (!noHeadroomLogged) {
                noHeadroomLogged = true;
                ErrorLogger.logMessage(
                    Label.Connect_OpportunityMirror_LogNoHeadroom,
                    CONTEXT,
                    ErrorLogger.SEVERITY_WARNING
                );
            }
            return result;
        }
        try {
            result = copy(scope);
        } catch (Exception unexpected) {
            ErrorLogger.log(unexpected, CONTEXT);
            result = new Result();
            result.failed = scope.size();
        }
        result.writeRefusals();
        return result;
    }

    /**
     * A run's path (R-OM8): gifts already saved. Copies them, then stores any new link on the gift
     * with this automation bypassed, since the copy has just been made. The refusals stay on the
     * result, for the run to write once when it ends.
     *
     * The links are stored with partial success, so one gift that cannot be saved never costs the
     * rest of the chunk their links. An Opportunity made here for such a gift is deleted again at
     * once, so the next run does not make a second one (R-OM9). Only a failure that throws rolls
     * the whole chunk back, Opportunities included.
     */
    public static Result syncSaved(List<Gift__c> gifts) {
        Result result = new Result();
        if (gifts == null || gifts.isEmpty() || !isAvailable()) {
            return result;
        }
        Map<Id, String> linkBefore = new Map<Id, String>();
        List<Gift__c> valid = new List<Gift__c>();
        for (Gift__c gift : gifts) {
            linkBefore.put(gift.Id, gift.Opportunity_Id__c);
            if (String.isBlank(gift.Opportunity_Id__c) || idOf(gift) != null) {
                gift.Opportunity_Id__c = String.isBlank(gift.Opportunity_Id__c)
                    ? null
                    : String.valueOf(idOf(gift));
                valid.add(gift);
            } else {
                result.failed++;
                result.refusals.add(
                    Label.Connect_OpportunityMirror_InvalidOpportunityId,
                    gift.Name,
                    gift.Id
                );
            }
        }
        if (valid.isEmpty()) {
            return result;
        }
        Savepoint beforeChunk = Database.setSavepoint();
        try {
            Result copied = copy(valid);
            storeLinks(valid, linkBefore, copied);
            result.add(copied);
        } catch (Exception unexpected) {
            Database.rollback(beforeChunk);
            ErrorLogger.log(unexpected, CONTEXT);
            Result undone = new Result();
            undone.failed = gifts.size();
            undone.refusals = result.refusals;
            result = undone;
        }
        return result;
    }

    // ------------------------------------------------------------------------ which gifts

    /** R-OM2 and R-OM4: whether this save of the gift needs a copy. */
    private static Boolean inScope(Gift__c gift, Gift__c old) {
        if (gift.Opportunity_Id__c == null) {
            return IN_TOTALS.contains(gift.Status__c);
        }
        if (old == null) {
            return true;
        }
        for (Schema.SObjectField field : WATCHED) {
            if (!ConnectSync.same(gift.get(field), old.get(field))) {
                return true;
            }
        }
        return false;
    }

    /**
     * Written when someone who cannot create Opportunities creates gifts in a save of their own,
     * once per transaction; never from a background job, where an import of many chunks would
     * repeat it for every chunk (R-OM5).
     */
    private static void logNoAccess(Integer howMany, Boolean creating) {
        if (!creating || noAccessLogged || System.isBatch() || System.isQueueable()) {
            return;
        }
        noAccessLogged = true;
        ErrorLogger.logMessage(
            String.format(Label.Connect_OpportunityMirror_LogNoAccess, new List<Object>{ howMany }),
            CONTEXT,
            ErrorLogger.SEVERITY_WARNING
        );
    }

    /**
     * Whether this transaction still has room for one copy of this many gifts: a gift can cost an
     * Opportunity insert or update and a contact role write, with a margin for the other
     * automation on Gift and Opportunity.
     */
    @TestVisible
    private static Boolean hasHeadroom(Integer giftCount) {
        return ConnectSync.hasHeadroom(
            QUERIES_NEEDED,
            DML_STATEMENTS_NEEDED,
            3 * giftCount,
            CPU_SHARE_NEEDED
        );
    }

    // ------------------------------------------------------------------------------ the copy

    /**
     * Creates or updates the Opportunity of each gift and its primary contact role, and writes a
     * new Opportunity's identifier onto the gift in memory. Four DML statements at most, whatever
     * the number of gifts.
     */
    private static Result copy(List<Gift__c> gifts) {
        Result result = new Result();
        Context context = new Context(gifts);

        List<SObject> inserts = new List<SObject>();
        List<Gift__c> insertedFor = new List<Gift__c>();
        List<SObject> updates = new List<SObject>();
        List<Gift__c> updatedFor = new List<Gift__c>();
        List<Gift__c> linked = new List<Gift__c>();

        for (Gift__c gift : gifts) {
            String stage = context.stageFor(IN_TOTALS.contains(gift.Status__c));
            if (stage == null) {
                result.failed++;
                result.refusals.add(Label.Connect_OpportunityMirror_NoStage, nameOf(gift), gift.Id);
                continue;
            }
            SObject desired = context.desiredOpportunity(gift, stage);
            if (gift.Opportunity_Id__c == null) {
                context.prepareNew(desired, gift);
                inserts.add(desired);
                insertedFor.add(gift);
                continue;
            }
            SObject existing = context.current.get(Id.valueOf(gift.Opportunity_Id__c));
            if (existing == null) {
                result.failed++;
                result.refusals.add(Label.Connect_OpportunityMirror_Missing, nameOf(gift), gift.Id);
                continue;
            }
            desired.Id = existing.Id;
            linked.add(gift);
            if (context.differs(desired, existing)) {
                updates.add(desired);
                updatedFor.add(gift);
            } else {
                result.unchanged++;
            }
        }

        if (!inserts.isEmpty()) {
            List<Database.SaveResult> saved = Database.insert(
                inserts,
                false,
                AccessLevel.USER_MODE
            );
            for (Integer i = 0; i < saved.size(); i++) {
                if (saved[i].isSuccess()) {
                    insertedFor[i].Opportunity_Id__c = saved[i].getId();
                    linked.add(insertedFor[i]);
                    result.created++;
                } else {
                    result.failed++;
                    refuse(result, insertedFor[i], saved[i].getErrors());
                }
            }
        }
        if (!updates.isEmpty()) {
            List<Database.SaveResult> saved = Database.update(
                updates,
                false,
                AccessLevel.USER_MODE
            );
            for (Integer i = 0; i < saved.size(); i++) {
                if (saved[i].isSuccess()) {
                    result.updated++;
                } else {
                    result.failed++;
                    refuse(result, updatedFor[i], saved[i].getErrors());
                }
            }
        }
        writeContactRoles(linked, context, result);
        return result;
    }

    /**
     * Gives each linked Opportunity its donor as primary contact role (R-OM3): a new role where it
     * has none, the donor put on the existing one where it names someone else. A role the platform
     * refuses is logged; the Opportunity stays.
     */
    private static void writeContactRoles(List<Gift__c> gifts, Context context, Result result) {
        Map<Id, Gift__c> giftByOpportunity = new Map<Id, Gift__c>();
        for (Gift__c gift : gifts) {
            if (context.personOf(gift) != null) {
                giftByOpportunity.put(Id.valueOf(gift.Opportunity_Id__c), gift);
            }
        }
        if (giftByOpportunity.isEmpty()) {
            return;
        }
        String roleObject = roleType().getDescribe().getName();
        Map<Id, SObject> primaries = OpportunityMirrorSelector.primaryRolesByOpportunity(
            roleObject,
            giftByOpportunity.keySet()
        );
        List<SObject> inserts = new List<SObject>();
        List<SObject> updates = new List<SObject>();
        List<Gift__c> insertedFor = new List<Gift__c>();
        List<Gift__c> updatedFor = new List<Gift__c>();
        for (Id opportunityId : giftByOpportunity.keySet()) {
            Gift__c gift = giftByOpportunity.get(opportunityId);
            Id person = context.personOf(gift);
            SObject primary = primaries.get(opportunityId);
            if (primary == null) {
                SObject role = roleType().newSObject();
                role.put('OpportunityId', opportunityId);
                role.put('ContactId', person);
                role.put('IsPrimary', true);
                if (context.donorRoleExists) {
                    role.put('Role', DONOR_ROLE);
                }
                inserts.add(role);
                insertedFor.add(gift);
            } else if (primary.get('ContactId') != person) {
                SObject role = roleType().newSObject((Id) primary.get('Id'));
                role.put('ContactId', person);
                updates.add(role);
                updatedFor.add(gift);
            }
        }
        if (!inserts.isEmpty()) {
            refuseRoles(
                Database.insert(inserts, false, AccessLevel.USER_MODE),
                insertedFor,
                result
            );
        }
        if (!updates.isEmpty()) {
            refuseRoles(Database.update(updates, false, AccessLevel.USER_MODE), updatedFor, result);
        }
    }

    private static void refuseRoles(
        List<Database.SaveResult> saved,
        List<Gift__c> savedFor,
        Result result
    ) {
        for (Integer i = 0; i < saved.size(); i++) {
            if (!saved[i].isSuccess()) {
                result.refusals.add(
                    String.format(
                        Label.Connect_OpportunityMirror_ContactRole,
                        new List<Object>{ messageOf(saved[i].getErrors()) }
                    ),
                    nameOf(savedFor[i]),
                    savedFor[i].Id
                );
            }
        }
    }

    /**
     * Saves each gift whose link changed, with partial success. A gift that is refused is counted
     * as failed, and an Opportunity created for it in this call is deleted again (R-OM9).
     */
    private static void storeLinks(List<Gift__c> gifts, Map<Id, String> linkBefore, Result result) {
        List<Gift__c> links = new List<Gift__c>();
        List<Gift__c> linkedFor = new List<Gift__c>();
        for (Gift__c gift : gifts) {
            if (!ConnectSync.same(gift.Opportunity_Id__c, linkBefore.get(gift.Id))) {
                links.add(new Gift__c(Id = gift.Id, Opportunity_Id__c = gift.Opportunity_Id__c));
                linkedFor.add(gift);
            }
        }
        if (links.isEmpty()) {
            return;
        }
        List<Database.SaveResult> saved;
        AutomationControl.bypass(AUTOMATION_NAME);
        try {
            saved = Database.update(links, false, AccessLevel.USER_MODE);
        } finally {
            AutomationControl.clearBypass(AUTOMATION_NAME);
        }
        List<SObject> orphans = new List<SObject>();
        List<Gift__c> orphanedFor = new List<Gift__c>();
        for (Integer i = 0; i < saved.size(); i++) {
            if (saved[i].isSuccess()) {
                continue;
            }
            Gift__c gift = linkedFor[i];
            result.failed++;
            refuse(result, gift, saved[i].getErrors());
            if (linkBefore.get(gift.Id) == null) {
                result.created--;
                orphans.add(opportunityType().newSObject(Id.valueOf(gift.Opportunity_Id__c)));
                orphanedFor.add(gift);
            }
        }
        if (orphans.isEmpty()) {
            return;
        }
        List<Database.DeleteResult> deleted = Database.delete(
            orphans,
            false,
            AccessLevel.USER_MODE
        );
        for (Integer i = 0; i < deleted.size(); i++) {
            if (!deleted[i].isSuccess()) {
                result.refusals.add(
                    String.format(
                        Label.Connect_OpportunityMirror_LogOrphan,
                        new List<Object>{
                            String.valueOf(orphans[i].Id),
                            messageOf(deleted[i].getErrors())
                        }
                    ),
                    orphanedFor[i].Name,
                    orphanedFor[i].Id
                );
            }
        }
    }

    // ------------------------------------------------------------------------------- helpers

    /**
     * Tidies a typed Opportunity ID and refuses one that is not an Opportunity's (R-OM10). A 15
     * character identifier is stored as its 18 character form, so uniqueness holds.
     *
     * @return false when the value was refused, with the error on the field
     */
    private static Boolean normalizeLink(Gift__c gift) {
        if (String.isBlank(gift.Opportunity_Id__c)) {
            gift.Opportunity_Id__c = null;
            return true;
        }
        Id typed = idOf(gift);
        if (typed == null) {
            gift.Opportunity_Id__c.addError(Label.Connect_OpportunityMirror_InvalidOpportunityId);
            return false;
        }
        gift.Opportunity_Id__c = String.valueOf(typed);
        return true;
    }

    private static Id idOf(Gift__c gift) {
        return ConnectSync.idOf(gift.Opportunity_Id__c, opportunityType());
    }

    /** The gift's name, or words for a gift not yet saved, whose number is not assigned yet. */
    private static String nameOf(Gift__c gift) {
        if (String.isNotBlank(gift.Name)) {
            return gift.Name;
        }
        return String.format(
            Label.Connect_OpportunityMirror_NewGift,
            new List<Object>{ String.valueOf(gift.Amount__c), String.valueOf(gift.Gift_Date__c) }
        );
    }

    private static void refuse(Result result, Gift__c gift, List<Database.Error> errors) {
        result.refusals.add(messageOf(errors), nameOf(gift), gift.Id);
    }

    private static String messageOf(List<Database.Error> errors) {
        List<String> messages = new List<String>();
        for (Database.Error error : errors) {
            messages.add(error.getMessage());
        }
        return String.join(messages, ' ');
    }

    /** The won or lost stage (R-OM3), read once per transaction. */
    private static String stage(Boolean won) {
        if (stageByWon == null) {
            stageByWon = new Map<Boolean, String>();
            for (SObject stage : OpportunityMirrorSelector.activeStages()) {
                if (stage.get('IsClosed') != true) {
                    continue;
                }
                Boolean isWon = stage.get('IsWon') == true;
                String name = (String) stage.get('ApiName');
                // The stage with the usual name wins; otherwise the first in the org's order.
                if (name == (isWon ? WON_STAGE : LOST_STAGE) || !stageByWon.containsKey(isWon)) {
                    stageByWon.put(isWon, name);
                }
            }
        }
        return stageByWon.get(won);
    }

    /**
     * What one copy reads, read once for all the gifts in it: the Opportunities already linked,
     * the appeals' Campaigns, the donors' names and person contacts, and what the org's schema
     * offers (record type, the Donor role, the Campaign field).
     */
    private class Context {
        final Map<Id, SObject> current;
        final Map<Id, String> campaignByAppeal = new Map<Id, String>();
        final Map<Id, String> names;
        final Map<Id, Id> personContactByAccount;
        final Boolean hasCampaign;
        final Boolean donorRoleExists;
        final Id donationRecordTypeId;
        final Schema.SObjectType campaignType;

        Context(List<Gift__c> gifts) {
            Schema.DescribeSObjectResult describe = opportunityType().getDescribe();
            Map<String, Schema.SObjectField> fields = describe.fields.getMap();
            hasCampaign = fields.containsKey(CAMPAIGN_FIELD.toLowerCase());
            campaignType = CampaignSyncService.campaignType();
            Schema.RecordTypeInfo donation = describe.getRecordTypeInfosByDeveloperName()
                .get(DONATION_RECORD_TYPE);
            donationRecordTypeId = donation != null &&
                donation.isActive() &&
                donation.isAvailable()
                ? donation.getRecordTypeId()
                : null;
            donorRoleExists = hasActiveValue(
                roleType().getDescribe().fields.getMap().get('role'),
                DONOR_ROLE
            );

            Set<Id> linkedIds = new Set<Id>();
            Set<Id> appealIds = new Set<Id>();
            // Names are needed only for a new Opportunity, person contacts for every role.
            Set<Id> namedContactIds = new Set<Id>();
            Set<Id> namedAccountIds = new Set<Id>();
            Set<Id> donorAccountIds = new Set<Id>();
            for (Gift__c gift : gifts) {
                if (gift.Opportunity_Id__c != null) {
                    linkedIds.add(Id.valueOf(gift.Opportunity_Id__c));
                } else {
                    addIfSet(namedContactIds, gift.Donor_Contact__c);
                    addIfSet(namedAccountIds, gift.Donor_Account__c);
                }
                addIfSet(appealIds, gift.Appeal__c);
                if (gift.Donor_Contact__c == null) {
                    addIfSet(donorAccountIds, gift.Donor_Account__c);
                }
            }
            List<String> read = new List<String>{ 'Id' };
            read.addAll(COMPARED);
            if (hasCampaign) {
                read.add(CAMPAIGN_FIELD);
            }
            current = OpportunityMirrorSelector.opportunitiesById(
                describe.getName(),
                read,
                linkedIds
            );
            if (
                hasCampaign &&
                campaignType != null &&
                !appealIds.isEmpty() &&
                Appeal__c.Campaign_Id__c.getDescribe().isAccessible()
            ) {
                campaignByAppeal.putAll(CampaignSyncSelector.campaignIdsByAppealId(appealIds));
            }
            names = OpportunityMirrorSelector.namesById(namedContactIds, namedAccountIds);
            personContactByAccount = OpportunityMirrorSelector.personContactIds(donorAccountIds);
        }

        String stageFor(Boolean won) {
            return stage(won);
        }

        /** The person on the primary contact role: the donor contact, or a person account's. */
        Id personOf(Gift__c gift) {
            if (gift.Donor_Contact__c != null) {
                return gift.Donor_Contact__c;
            }
            return gift.Donor_Account__c == null
                ? null
                : personContactByAccount.get(gift.Donor_Account__c);
        }

        SObject desiredOpportunity(Gift__c gift, String stageName) {
            SObject opportunity = opportunityType().newSObject();
            opportunity.put('Amount', gift.Amount__c);
            opportunity.put('CloseDate', gift.Gift_Date__c);
            opportunity.put('StageName', stageName);
            opportunity.put(
                'AccountId',
                gift.Donor_Account__c != null ? gift.Donor_Account__c : gift.Household__c
            );
            if (hasCampaign) {
                Id campaignId = gift.Appeal__c == null
                    ? null
                    : ConnectSync.idOf(campaignByAppeal.get(gift.Appeal__c), campaignType);
                opportunity.put(CAMPAIGN_FIELD, campaignId);
            }
            return opportunity;
        }

        /** What only a new Opportunity gets: its name and the Donation record type. */
        void prepareNew(SObject opportunity, Gift__c gift) {
            Id donor = gift.Donor_Contact__c != null
                ? gift.Donor_Contact__c
                : gift.Donor_Account__c;
            String donorName = names.containsKey(donor)
                ? names.get(donor)
                : Label.Connect_OpportunityMirror_UnknownDonor;
            opportunity.put(
                'Name',
                String.format(
                        Label.Connect_OpportunityMirror_OpportunityName,
                        new List<Object>{ donorName, String.valueOf(gift.Gift_Date__c) }
                    )
                    .left(120)
            );
            if (donationRecordTypeId != null) {
                opportunity.put('RecordTypeId', donationRecordTypeId);
            }
        }

        Boolean differs(SObject desired, SObject existing) {
            List<String> fields = new List<String>(COMPARED);
            if (hasCampaign) {
                fields.add(CAMPAIGN_FIELD);
            }
            for (String field : fields) {
                if (!ConnectSync.same(desired.get(field), existing.get(field))) {
                    return true;
                }
            }
            return false;
        }
    }

    private static void addIfSet(Set<Id> ids, Id value) {
        if (value != null) {
            ids.add(value);
        }
    }

    private static Boolean hasActiveValue(Schema.SObjectField field, String value) {
        if (field == null) {
            return false;
        }
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue() == value) {
                return true;
            }
        }
        return false;
    }
}

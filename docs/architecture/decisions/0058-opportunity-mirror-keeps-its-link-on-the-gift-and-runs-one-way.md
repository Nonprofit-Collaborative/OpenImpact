# ADR-0058: The Opportunity and Gift Transaction mirrors keep their link on the gift, run one way at a time, and reconcile on a page

**Status:** Accepted (builder decision)
**Date:** 2026-09-25
**Amended:** 2026-09-27, feature X-07, the Gift Transaction mirror (see "Amendment for X-07: the
Gift Transaction mirror" below; canonical model Section 29D). Decisions 1 to 10 are unchanged.
**Source:** builder decision under plan Section 9.3, feature X-01 (plan Section 4.12, "Opportunity
mirror"; Section 4.5, coexistence modes); follows ADR-0056 (Campaign sync) and refines ADR-0004,
ADR-0013 and ADR-0021 for Connect; amends ADR-0057 (Connect's Health Check extension); canonical
model Section 29C

## Context

Plan Section 4.12 asks for a one-way copy of each gift to an Opportunity (record type
`Donation`, Stage Closed Won, Close Date, Amount, Account, primary Contact Role, Campaign from
the appeal link), an "Opportunity is source" option that makes gifts from Opportunities written
by an online giving tool, exactly one direction per org chosen in Settings, and a reconciliation
report. It leaves open where the link lives, when the copy runs and with whose access, which
gifts are copied, what happens to refunds and deletions, how an Opportunity becomes a gift when
Connect cannot have a trigger on Opportunity, and what the reconciliation report is.

ADR-0056 settled the same questions for Campaign sync, and five constraints carry over or are
new here.

1. **Opportunity may be named only in Connect, and only dynamically** (plan Section 4.2,
   ADR-0013). That rules out a lookup to Opportunity, a trigger or record-triggered Flow on
   Opportunity, a field on Opportunity, and a packaged report or report type over Opportunity:
   each is a compile-time or deploy-time reference, and one of them refuses the whole package on
   a Platform-only org.
2. **Every DML that user input can reach runs in user mode** (plan Section 9.3).
3. **Volume.** Gifts arrive by the thousand through import, gift batches and the inbound API, and
   an NPSP org's own Opportunity automation is heavy. Campaign sync copies appeals, which are
   few; this copies up to a million gifts.
4. **Gifts are facts.** A receipted or posted gift does not change (R-G4, R-G14), and the inbound
   API already refuses to edit a gift it recorded (ADR-0051).
5. **The X-02 review's lessons:** no per-record log writes, partial-success writes with clean-up
   of what the package itself made, a limit check before DML in a trigger, "deleted or not
   visible to you" for what a user-mode read cannot find, and no Warning floods.

## Decision

1. **The link is one attribute on Gift, shipped by Connect.** `Gift__c.Opportunity_Id__c`,
   Text(18), unique, external ID, in `packages/connect/main/default/objects/Gift__c`, exactly as
   ADR-0056 put `Campaign_Id__c` on Appeal. Both directions use it, so a gift made from an
   Opportunity and an Opportunity made from a gift are the same link, and switching direction
   never duplicates either side. There is still no generic link object: Campaign sync and the
   Opportunity mirror each need one link per record, and X-07 can decide its own.
2. **One setting holds the direction.** `Connect_Settings__c.Opportunity_Mirror_Direction__c`,
   stored as `Off`, `GiftsToOpportunities` or `OpportunitiesToGifts` and shown as a choice in the
   Giving section of Nonprofit Settings; empty reads as Off. A single value makes "exactly one
   direction per org" true by construction rather than by a check. It is off at install in every
   coexistence mode, including NPSP coexistence (see the owner question in Consequences).
3. **Gifts to Opportunities copies before the gift is saved, in the saver's user mode, like
   Campaign sync.** The `Opportunity_Mirror` automation (Gift, order 50, after `Gift_Core_Rules`
   derives the household) creates or updates the Opportunity and its primary Contact Role in the
   before-save context and writes the identifier onto the gift in the same save. Writes use
   partial success; a refusal is logged and never refuses the gift. Before any DML it requires
   half of the transaction's queries and DML statements, and 40 percent of its CPU time, still
   unspent, besides what one copy costs (seven queries, four DML statements). A fixed margin is
   not enough: NPSP's own Opportunity triggers can spend twenty queries or more per chunk inside
   the same save, and a limit reached there cannot be caught, so the gift's save would fail. When
   the platform retries a partial-success save, it rolls back the Opportunities the first attempt
   made, but not the static state: a link that this save wrote, and that the gift did not have
   before, is cleared and the Opportunity made again. The once-per-transaction Warnings (no
   access, no headroom) are flags of the same kind, so if the retry rolled back the first
   attempt's Warning the retry writes none; accepted, because the next run copies those gifts
   either way and says so in its summary. A
   save without room is left uncopied with one Warning. The copy needs Opportunity create and
   edit and nothing more: the link is written onto the record being saved, which is not checked
   against the saver's field access, so a gift-entry user without the Opportunity Mirror
   permission set still has a linked gift's changes copied. A person without Opportunity access
   is logged once per transaction when creating or changing gifts, and never from a batch or
   queueable, which is where imports run.
4. **Which gifts, and what is copied** (R-OM2, R-OM3). Gifts in the totals (Received, Refunded,
   Written off, ADR-0022), including negative refund and write-off gifts as negative
   Opportunities, so an NPSP total nets as ours does. Pending and Cancelled gifts get none. A
   copied gift that is Cancelled has its Opportunity moved to the lost stage; one moved back to
   Pending, or a Pending pledge linked by hand to an open Opportunity, leaves that Opportunity's
   stage alone, so a pledge never closes someone's open pipeline as lost. Stages are found
   from the org's own `OpportunityStage` records (the won stage named `Closed Won`, else the
   first active won stage), because stage names are the org's to change. The Opportunity's
   Account is the Donor Account or the Household; the record type `Donation` is used when present
   and available to the saver; the name is written only at creation, so NPSP's own naming is not
   fought. Campaign is written only when the saver may read Campaigns and the appeal's Campaign
   ID; otherwise it is left out of the copy entirely, so the Opportunity's Campaign is never
   cleared and a saver who cannot see either still has gifts with an appeal copied. The appeal's
   link is read in the saver's user mode, not in system mode as package-owned data would allow
   (ADR-0021): a copy never writes a value its saver could not read.
5. **Opportunities to Gifts is a run, not a trigger.** Connect cannot hold a trigger on
   Opportunity (constraint 1), so the mirror page schedules a nightly run and offers Run now,
   the shape of ADR-0038, and each run turns every won Opportunity closed on or after
   `Opportunity_Mirror_Start__c` that no gift names into a gift, in the runner's user mode. The
   link is set in the insert itself, so the unique index stops a duplicate even between two
   overlapping runs, and nothing needs cleaning up. An empty start date turns no Opportunity into
   a gift: an NPSP org choosing this direction would otherwise get a gift, and a thank you, for
   every donation it has ever recorded. The start date is read as a date in the org's default
   time zone, so it does not move with the time zone of whoever scheduled the run. An optional
   list of record type API names narrows the Opportunities that become gifts; empty means all,
   and a name the org does not have matches nothing and is named in one Warning per run. The
   gift is never edited afterwards (constraint 4); a later change on the Opportunity is shown by
   the reconciliation page.
6. **The same run catches up Gifts to Opportunities.** In that direction a run copies every gift
   in the totals that has no Opportunity yet, and every linked gift changed since the last
   completed run started, so a change whose copy was skipped (no Opportunity access, no headroom)
   is put right by the next run rather than never. That catch-up is one query with an OR across
   the unlinked gifts and the recently changed linked ones, which no single index serves, so at
   hundreds of thousands of gifts the run's start is slower; a nightly run tolerates that, and it
   is not repeated per chunk. It stores new links with partial success and
   deletes, in user mode, an Opportunity it created for a gift it could not save, naming in a
   Warning any it cannot delete (ADR-0056 decision 7).
6a. **Runs respect the pause and the switch, and say when they last completed.** While
   automation is paused (ADR-0055) or the `Opportunity_Mirror` switch is off, a run does nothing
   and writes one Info entry, checked when it starts and before each chunk: during a pause
   `Gift_Core_Rules` is skipped, so a gift inserted then would never get its household or
   allocation. A completed run records its start time and summary on `Connect_Settings__c`
   through `ConnectSettingsWriter`, which writes only those two keys; the page shows them, and a
   Health Check finding warns when the nightly run is scheduled and nothing has completed for
   two days (ADR-0038 point 4, ADR-0055 point 7). The finding reaches Health Check through the
   ADR-0057 seam, which this amends minimally: `HealthCheckExtensions` looks up
   `ConnectHealthCheckExtension` as well as `GivingHealthCheckExtension`, the list ADR-0057's
   consequences anticipated. The finding reads only Connect's own protected setting and the
   platform's CronTrigger, so it needs no sharing exception.
6b. **A deleted linked gift is reported.** Its Opportunity is left alone (decision 8), and one
   Warning per delete names the gifts and their Opportunities; in Opportunities to Gifts it also
   says the next run makes a new gift from an Opportunity still won.
7. **Warnings are grouped by message.** A refusal is recorded against its platform message, and
   one Warning per distinct message is written per transaction, or per run, with the count and up
   to ten gift names. A rule on Opportunity that refuses every gift of a 250,000-row import
   therefore writes one Warning per import chunk rather than 250,000, and a nightly run writes one
   per distinct reason. At most 50 distinct messages are kept; any further ones are counted under
   one "other refusals" entry, because a platform message can carry a record identifier and so be
   distinct for every record. An insert refused only because another run already made the gift
   (a duplicate Opportunity ID) is counted as unchanged, not refused.
8. **Nothing the org had is deleted.** A deleted gift leaves its Opportunity; the reconciliation
   page lists it as a won Opportunity without a gift. A linked Opportunity the saver cannot find
   is "deleted or not visible to you" and is not replaced.
9. **The reconciliation report is a page, not a report.** A packaged report type over Opportunity
   would stop Connect installing on a Platform-only org (constraint 1). The page reads a date range
   in user mode, refuses a range over 10,000 gifts or 10,000 won Opportunities rather than showing
   part of it (ADR-0051), and shows each side's count and total and the differences. Each side's
   read stops at 10,001 records, and the query rows it can need (twice that per side, for the
   linked lookups, so 10,000 a side holds in a fresh transaction) are checked before it starts, so
   a range too large is refused in words instead of failing on a limit; gifts are read in a SOQL
   for loop to keep the heap small. A viewer without read access to Opportunity, its Name, Amount
   and Close Date, or the Opportunity ID is refused in words, and a won Opportunity is reported as
   having "no gift visible to you", which is all a user mode read can say. The page's reads require
   the custom permission `Use_Opportunity_Mirror`, carried by the Opportunity Mirror permission
   set, rather than relying on class access alone; the console shows the page's row only to someone
   who has it, through a new optional Setting Definition attribute, `Required_Permission__c`, since
   a console user without the set could not open the page anyway (ADR-0038 point 3 read for a
   module page gated by its own permission set). The attribute holds the permission's name without
   a namespace prefix; the console tries the name as given, then with the package namespace, so no
   prefix is ever written into metadata. In Gifts to Opportunities the page offers a run over the
   range to put the differences right.
10. **Shared seams with Campaign sync.** The value comparison, the limit headroom check and the
    identifier check move from Campaign sync into one Connect class, `ConnectSync`, which both
    copies use, so they cannot drift apart. The grouped Warnings live there too. Campaign sync
    keeps its one Warning per appeal, which ADR-0056 settled and appeal volumes allow.

## Alternatives considered

- **A lookup from Gift to Opportunity.** Rejected: a compile-time reference (ADR-0056).
- **Asynchronous copy (queueable per save).** It would isolate the gift's transaction from the
  org's Opportunity automation, but imports and gift batches already run in batch Apex, where
  a second queueable per chunk collides with the enqueue limit, and a failed job leaves no trace
  on the gift. The headroom check plus the nightly catch-up gives the isolation where it matters
  without a second failure path.
- **System mode Opportunity writes.** Rejected for the reason ADR-0056 gives for Campaign: an
  elevated write onto a standard object the package does not own.
- **A trigger, Flow or Change Data Capture on Opportunity for Opportunities to Gifts.** Rejected:
  each names Opportunity at deploy time. A Flow action an org calls from its own Opportunity
  flow, for gifts made at once, can be added later without a model change.
- **Update the gift when its Opportunity changes.** Rejected: it would edit receipted and posted
  gifts, which ADR-0051 already refuses for the inbound API.
- **Delete, or mark lost, the Opportunity of a deleted gift.** Not chosen: the page shows it and
  the administrator decides. Asked as an owner question below.
- **Stage names fixed at `Closed Won` and `Closed Lost`.** Rejected: an org may rename or remove
  them, and an insert with an unknown stage fails every gift.
- **Only Opportunities of record type `Donation` become gifts.** Not chosen: NPSP ships several
  donation record types (Grant, Major Gift, Membership, In-Kind). The start date is the guard,
  and the admin guide says not to choose this direction in an org that sells with Opportunities.
- **A fixed safety margin for the headroom check, as Campaign sync has.** Rejected for the
  mirror: appeals are few and Campaign automation is light, so ten spare queries serve Campaign
  sync, which is unchanged; Opportunity automation in an NPSP org is neither.
- **A Date data type for the start setting.** The console has no date control yet; the
  Date/Time control it has is used, and the date part is what counts.

## Consequences

- Connect ships its second field on a Giving object, two more settings keys, a second registry
  row, a scheduled job and a page. `ConnectPostInstall` creates the `Opportunity_Mirror` switch
  with the rest.
- NPSP rollups, soft credits and Campaign totals see gifts only while Gifts to Opportunities is
  chosen and the saver, or the scheduled runner, can create Opportunities.
- Gifts made from Opportunities are ordinary gifts: Giving's rules allocate them, acknowledge them
  and count them, exactly as a gift from the inbound API.
- Plan Section 4.5 says the mirror is on in NPSP coexistence mode. It ships off in every mode,
  and the setting's description and the admin guide tell an NPSP org to choose Gifts to
  Opportunities. Whether choosing NPSP coexistence should switch it on is an owner question.
- Plan Section 4.12 calls for "a reconciliation report"; it is a page, for the reason in
  decision 9.
- NPSP rollups count every Opportunity the mirror makes: a refund's negative Opportunity counts
  as a gift in NPSP's number of gifts though it lowers the total, and an in-kind gift's
  Opportunity has a zero Amount and counts too. Accepted: the totals net exactly, and the counts
  are NPSP's to define.
- For a donor stored as a contact, the Opportunity's Account is the Open Impact household. In an
  org running NPSP alongside, that is not the NPSP household account until household adoption
  (plan Section 4.5) ships, so NPSP household rollups do not see these Opportunities.
- A Donation record type whose sales process does not include the chosen won or lost stage makes
  every insert fail; each failure is logged (R-OM6), and the fix is the org's sales process.
- Core changes twice, minimally: `HealthCheckExtensions` returns a list of extensions, and
  Setting Definition gains `Required_Permission__c`. Campaign sync and the accounting export
  pages could adopt the latter; not done here.

## Amendment for X-07: the Gift Transaction mirror

Added 2026-09-27. Plan Section 4.12 asks for a one-way copy of gifts to Nonprofit Cloud's
`GiftTransaction` "plus designation", so native donor summaries and Agentforce actions still see
gifts, in dynamic Apex only and hidden where the objects are absent; Section 4.5 has it off by
default in Agentforce Nonprofit coexistence; Section 6.3 moves X-07 to v0.6. It shares its design
with X-01, so it is recorded here rather than in a new record. Canonical model Section 29D holds
the rules (R-GT1 to R-GT10).

### Context for X-07

Six constraints differ from the Opportunity mirror's.

1. **Every Nonprofit Cloud object is optional and license gated.** `GiftTransaction` appears in
   the describe only with the Fundraising Access license and, per user, the Fundraising User
   permission (`docs/architecture/reference/nonprofit-cloud-data-model.md` Section 2). The CI
   gate `check-standard-objects.sh` refuses the name outside a `// detection-only:` constant.
2. **The field list is corroborated, not verified.** The reference has the field API names from
   two channels but marks their types as inferred, and verifies no Status value, no required flag
   and no `referenceTo`. No Nonprofit Cloud org is available to the build.
3. **What the mirror is for is calculated in batch.** Donor Gift Summary and the Gift Designation
   totals are Data Processing Engine outputs, produced by a schedule the administrator builds
   (reference Section 8, items 1 and 2), and must never be written by us.
4. **Refunds are modelled differently.** BarnCRM records a refund as a negative gift (R-G3);
   Nonprofit Cloud records it on the transaction (`RefundedAmount` and refund records), so a
   negative Gift Transaction would count as one more gift (reference Section 8 item 5).
5. **The first customers migrate from Nonprofit Cloud in the same org.** The Nonprofit Cloud
   import templates (C-14) load Gift Transactions as gifts; every such gift already has its Gift
   Transaction.
6. **Designations need a mapping the model does not have.** `GiftTransactionDesignation` names a
   `GiftDesignation`, and nothing in BarnCRM says which designation a fund is.

### Decisions for X-07

11. **The link is its own attribute on Gift.** `Gift__c.Gift_Transaction_Id__c`, Text(18), unique,
    external ID, case sensitive, shipped by Connect, used by both directions, for the reasons of
    decision 1. It is separate from `Opportunity_Id__c`: an org running NPSP alongside Nonprofit
    Cloud during a move could mirror a gift to both, and one field holding either would make
    a gift's link mean two things.
12. **One direction setting, and it is independent of the Opportunity mirror's.**
    `Connect_Settings__c.Gift_Transaction_Mirror_Direction__c`, stored as `Off`,
    `GiftsToGiftTransactions` or `GiftTransactionsToGifts`, empty read as Off, shown in the Giving
    section of Nonprofit Settings. Off at install in every coexistence mode, as plan Section 4.5
    says. The two mirrors write different objects and different links, so no combination of the
    two settings can loop; an org choosing both inbound directions is told in the admin guide that
    a tool writing both an Opportunity and a Gift Transaction for one donation makes two gifts.
13. **Both directions are runs; saving a gift copies nothing.** Run now and a nightly run at 01:35,
    in the shape of decision 5 and ADR-0038, in the runner's user mode, respecting the pause and
    the `Gift_Transaction_Mirror` switch as decision 6a says. A copy on save, as Gifts to
    Opportunities has, is not chosen: what it is for is calculated in Nonprofit Cloud's own
    scheduled runs (constraint 3), so it would be seen no sooner; a saver without the Fundraising
    User permission (constraint 1) could not make it, so it would skip and warn on those saves; and
    it would put Nonprofit Cloud's fundraising automation inside every gift save. The
    `Gift_Transaction_Mirror` automation on Gift does only two things: it checks a typed or
    changed link (decision 17), and after a delete it reports the Gift Transactions left behind
    (decision 6b). An org without Nonprofit Cloud pays one describe lookup when someone types a
    link, and nothing otherwise.
14. **The mirror checks the shape it relies on, and names a paid status rather than guessing
    one** (constraint 2). The mirror is available only when the running person's describe has
    `GiftTransaction` with `DonorId` a reference to Account, `TransactionDate` a date,
    `OriginalAmount` an amount and `Status` a picklist; otherwise the page says it is unavailable
    and nothing queries the object. `CurrentAmount` and `Name` are optional and written only where
    they exist and are writable. The Status value that means paid is an administrator setting,
    `Gift_Transaction_Mirror_Status__c`, checked against the org's active Status values before a
    run does anything: a guessed value would either fail every insert or create transactions
    Nonprofit Cloud does not count as paid, silently defeating the feature.
15. **A start date in both directions, required** (constraint 5). `Gift_Transaction_Mirror_Start__c`,
    read as a date in the org's time zone as decision 5 reads its own. Gifts dated before it are
    not copied and Gift Transactions dated before it do not become gifts, so the gifts imported
    from Nonprofit Cloud are not copied back as a second transaction each, and the Gift
    Transactions they came from do not become a second gift each. Until it and the paid status are
    set, the mirror moves nothing. Matching an imported gift to its Gift Transaction by the gift's
    External Id was considered and not chosen: a migration from another org leaves identifiers that
    look like Gift Transactions' and name nothing here, and a match that fails for want of sharing
    would create the duplicate it exists to prevent.
16. **Which gifts, and what is copied** (constraint 4). Received gifts above zero that are not
    in-kind. A refund or write-off (a negative gift) is never copied, and an original that is later
    refunded or written off keeps its Gift Transaction unchanged, listed by the reconciliation; the
    admin guide says to record the refund in Nonprofit Cloud where its summaries must show it. The
    copy writes Donor (the Donor Account, else the Household), Transaction Date and Original Amount,
    and on creation only Current Amount, Status and Name. A later run updates the first three when
    they differ and never Status or Current Amount, which Nonprofit Cloud maintains once the
    transaction exists. Gift Transactions to Gifts makes a gift from each Gift Transaction of the
    paid status on or after the start date that no gift names: Donor Account from Donor, Amount
    from Original Amount (above zero), Gift Date from Transaction Date, Type Other, Status Received,
    the link set in the insert (decision 5), never edited afterwards (constraint 4 of the main
    decision).
17. **Everything else follows the Opportunity mirror.** Refusals are grouped by message (decision
    7) through `ConnectSync.Warnings`; a Gift Transaction made for a gift whose link could not be
    stored is deleted in the same run (decision 6); nothing the org had is deleted and a linked
    record that cannot be found is "deleted or not visible to you" (decision 8); a typed link is
    checked to be a Gift Transaction's identifier and stored in its 18 character form wherever the
    saver can see Gift Transactions (R-OM10); each chunk checks the headroom decision 3 sets
    before any write, and a chunk without it is skipped and counted with one Warning; the last
    completed run is recorded through `ConnectSettingsWriter` and a stale nightly run is a Health
    Check finding in `ConnectHealthCheckExtension` (decision 6a); the reconciliation is a page
    with the caps and refusals of decision 9, gated by the custom permission
    `Use_Gift_Transaction_Mirror` on the `Gift_Transaction_Mirror` permission set.
18. **Designations and the rest are deferred** (constraint 6). Designations, campaign and outreach
    source code, payment and tax fields, soft credits, tributes, commitments and refund records are
    not mirrored in v0.6. The donor summaries that justify X-07 (reference Section 3.12) read the
    transaction alone; designations need a Fund to Gift Designation link, which is a model change
    of its own and an owner question (below).

### Alternatives considered for X-07

- **Copy on save, as Gifts to Opportunities does.** Rejected for the reasons in decision 13.
- **One link field for both mirrors.** Rejected in decision 11.
- **Write Status as `Paid`**, inferred from the `IsPaid` flag's name. Rejected: the value is not
  verified (constraint 2), and a wrong guess fails silently in the way decision 14 describes.
- **Filter Gift Transactions to Gifts on `IsPaid`.** Not chosen: its type is inferred and whether
  it follows Status is unverified; the paid status the administrator names already says which
  transactions are paid, and the same setting serves both directions.
- **A negative Gift Transaction for a refund, or a Gift Refund record.** The first is rejected in
  constraint 4; the second needs field types and values nobody has verified and belongs with the
  deferred work.
- **Mirror designations by fund name.** Rejected: a name is not a key, and a renamed fund would
  move money between designations.

### Consequences of X-07

- Connect ships a second link attribute on Gift, five Connect Settings keys, a third registry row,
  a scheduled job, a page, a permission set and a custom permission. No Core change: the Health
  Check seam, `Required_Permission__c` and the automation switch rows are reused as they are.
- Until both the paid status and the start date are set, choosing a direction does nothing but
  make the page say what is missing.
- Nonprofit Cloud's summaries lag BarnCRM by up to a day plus however often its own Data
  Processing Engine runs are scheduled.
- A refunded gift still counts at its full amount in Nonprofit Cloud until the refund is recorded
  there. The reconciliation lists every such gift.
- Everything above is written against the reference file, not against a Nonprofit Cloud org. The
  Apex tests assert the unavailable branch everywhere and the available branch only where a test
  org has Gift Transactions; neither CI test org does. Running the tests and the admin guide's
  walkthrough in a Nonprofit Cloud org, and correcting the reference from a describe there, is
  recorded as open work in `docs/contributor-guide/ci.md`.
- Owner questions: whether designations should be mirrored, which needs a Fund to Gift
  Designation link; and whether choosing Agentforce Nonprofit coexistence should propose the
  mirror, which plan Section 4.5 leaves off by default.

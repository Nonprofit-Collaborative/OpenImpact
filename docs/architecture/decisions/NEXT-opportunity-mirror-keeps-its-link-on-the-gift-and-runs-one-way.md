# ADR-NEXT: The Opportunity mirror keeps its link on the gift, runs one way at a time, and reconciles on a page

**Status:** Accepted (builder decision)
**Date:** 2026-09-25
**Source:** builder decision under plan Section 9.3, feature X-01 (plan Section 4.12, "Opportunity
mirror"; Section 4.5, coexistence modes); follows ADR-0056 (Campaign sync) and refines ADR-0004,
ADR-0013 and ADR-0021 for Connect; canonical model Section 29C

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
   partial success; a refusal is logged and never refuses the gift. Before any DML it checks the
   remaining queries, DML statements, DML rows and CPU time, because the org's own Opportunity
   automation runs inside the gift's transaction; a save without room is left uncopied with one
   Warning. A person without Opportunity access is logged once per transaction when creating
   gifts, and never from a batch or queueable, which is where imports run.
4. **Which gifts, and what is copied** (R-OM2, R-OM3). Gifts in the totals (Received, Refunded,
   Written off, ADR-0022), including negative refund and write-off gifts as negative
   Opportunities, so an NPSP total nets as ours does. Pending and Cancelled gifts get none, and a
   copied gift that moves there has its Opportunity moved to the lost stage. Stages are found
   from the org's own `OpportunityStage` records (the won stage named `Closed Won`, else the
   first active won stage), because stage names are the org's to change. The Opportunity's
   Account is the Donor Account or the Household; the record type `Donation` is used when present
   and available to the saver; the name is written only at creation, so NPSP's own naming is not
   fought.
5. **Opportunities to Gifts is a run, not a trigger.** Connect cannot hold a trigger on
   Opportunity (constraint 1), so the mirror page schedules a nightly run and offers Run now,
   the shape of ADR-0038, and each run turns every won Opportunity closed on or after
   `Opportunity_Mirror_Start__c` that no gift names into a gift, in the runner's user mode. The
   link is set in the insert itself, so the unique index stops a duplicate even between two
   overlapping runs, and nothing needs cleaning up. An empty start date turns no Opportunity into
   a gift: an NPSP org choosing this direction would otherwise get a gift, and a thank you, for
   every donation it has ever recorded. The gift is never edited afterwards (constraint 4); a
   later change on the Opportunity is shown by the reconciliation page.
6. **The same run catches up Gifts to Opportunities.** In that direction a run copies every gift
   in the totals that has no Opportunity yet. It stores new links with partial success and
   deletes, in user mode, an Opportunity it created for a gift it could not save, naming in a
   Warning any it cannot delete (ADR-0056 decision 7).
7. **Warnings are grouped by message.** A refusal is recorded against its platform message, and
   one Warning per distinct message is written per transaction, or per run, with the count and up
   to ten gift names. A rule on Opportunity that refuses every gift of a 250,000-row import
   therefore writes one Warning per import chunk rather than 250,000, and a nightly run writes one
   per distinct reason.
8. **Nothing the org had is deleted.** A deleted gift leaves its Opportunity; the reconciliation
   page lists it as a won Opportunity without a gift. A linked Opportunity the saver cannot find
   is "deleted or not visible to you" and is not replaced.
9. **The reconciliation report is a page, not a report.** A packaged report type over
   Opportunity would stop Connect installing on a Platform-only org (constraint 1). The page reads
   a date range in user mode, refuses a range over 10,000 gifts or 10,000 won Opportunities
   rather than showing part of it (ADR-0051), and shows each side's count and total and the
   differences. In Gifts to Opportunities it offers a run over the range to put them right.
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

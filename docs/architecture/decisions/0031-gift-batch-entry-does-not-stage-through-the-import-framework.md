# ADR-0031: Gift batch entry keeps its own rows rather than staging through the import framework

**Status:** Accepted
**Date:** 2026-09-08
**Source:** plan Section 5.2 feature G-17, whose Notes column reads "Built on Import framework", and plan Section 4.11, whose Gift Batch row reads "Uses the Import framework underneath"

## Context

G-17 is the screen where Maria types twenty checks on a Tuesday morning. She has a deposit
slip that says the stack totals 4,812.50. She wants the fund, appeal, date and payment
method set once at the top, a running total as she types, and to be refused a post while
her total and the bank's disagree.

The plan says twice that this is built on the import framework (plan Sections 4.11 and
5.2). That framework is real and is finished: `Import_Batch__c` is one upload, with a
template, a file, a dry run flag, chunk size, counts and an undo deadline; `Import_Row__c`
is one staged row, holding the source columns as JSON in `Raw_Values_JSON__c` plus a fixed
set of resolved lookups; `ImportRowProcessor` resolves a chunk of rows in dependency order,
matches people and organizations against existing records, and hands the rest of the row to
a registered entity processor. `ImportProcessorBatch` runs it asynchronously.

The plan's instruction is a good instinct: do not build a second thing that already exists
(plan Section 1.3 principle 8). It was written before either piece existed, so the question
of whether the two are the same shape is a question this build has to answer honestly
rather than assume.

They are not the same shape, and the difference is not cosmetic.

- **The importer's hard problem is matching. Batch entry has no matching problem.** Every
  row of a CSV is text that might be a donor, and most of `ImportRowProcessor` and all of
  `ImportMatcher` exist to decide which record that text means. In the grid, Maria picks the
  donor from a record picker. The row already holds a real record id. Staging it as text so
  that a matcher can turn it back into the id it started as is work that adds only ways to
  be wrong.
- **A staged row is untyped. A grid row is not.** `Import_Row__c` has no amount, no gift
  date, no fund, no appeal and no payment reference: they would all live in
  `Raw_Values_JSON__c` as strings. The one number this feature exists to check, the entered
  total, would then be a sum over parsed JSON. Summing strings to decide whether to trust a
  deposit is the opposite of what R-GB2 asks for.
- **The control total has nowhere to live.** `Import_Batch__c` has no control total, no
  entered total and no posted flag, and the four batch defaults have nowhere to sit either.
  Adding them means changing a Core object for a Giving feature, which ADR-0017 already
  rules out as the way packages depend on each other.
- **The lifecycles disagree about what "done" means.** An import commits row by row with
  partial success, because one bad row in a file of eight thousand must not stop the other
  7,999 (R-IB5). A balanced batch is the opposite: all twenty rows post or none of them do
  (R-GB5), because a partial post leaves a batch whose gifts no longer total what the bank
  was given. Reusing the framework would mean using its central rule backwards.
- **Asynchronous is wrong here.** An import of hundreds of thousands of rows has to be
  chunked batch Apex with progress. Twenty checks post in one synchronous transaction and
  Maria sees the answer before she looks up. Making her wait on a queued job to find out
  whether her deposit balanced is a worse product.

## Decision

**G-17 ships `Gift_Batch__c` with its own master-detail child `Gift_Batch_Row__c`, and does
not use `Import_Batch__c`, `Import_Row__c` or `ImportRowProcessor`.** The plan's "built on
the import framework" note is recorded as superseded by this ADR for G-17 specifically. The
import framework is unchanged and is still how a file of gifts is loaded (C-14): the two
features stay separate because they solve different problems.

What is genuinely shared is shared, and it is the part that matters:

- **Posting inserts ordinary `Gift__c` records through the ordinary triggers.** Nothing is
  bypassed to make posting faster. The household is derived, the default allocation is
  created, the allocation totals are kept honest, the rollups run and the receipt lock
  applies, exactly as they do for a gift typed on the quick entry screen (R-GB6). Where a
  row named a fund, the gift's single default allocation is repointed at it afterwards,
  which is the same path `QuickGiftEntryController` already takes, so the allocations still
  total the gift (R-GA1).
- **The trigger framework and the Error Log are used as every other feature uses them.**
  The post lock is a registered automation, not a private check.

## Alternatives considered

- **Stage batch rows as `Import_Row__c` records against an `Import_Batch__c`, with a gift
  batch template.** The literal reading of the plan. Rejected for the five reasons above.
  The clearest single one: the control total, the defaults and the posted flag all have to
  be added to a Core object owned by another package, to serve a screen that never uploads
  a file.
- **Add a control total and defaults to `Import_Batch__c` and a typed amount to
  `Import_Row__c`.** Rejected as the previous alternative plus a change to Core that makes
  every import carry fields only manual entry uses, and that this feature's territory
  explicitly excludes.
- **No batch object: a grid that inserts gifts directly, with the control total checked in
  the browser.** Cheapest to build and it fails the two requirements that matter. An open
  batch would not survive the browser being closed, and a check made only in the browser is
  a check a stale tab can walk past.
- **Reuse `Import_Batch__c` only as the container, with a new child row object.** Rejected:
  it takes the half of the framework that carries the least (a status and some counts) and
  leaves a batch that reports itself in the import history as an upload with no file, so
  the "last import per source" view in the Hub starts lying.

## Consequences

- Giving owns two more objects, their metadata, and the code that posts them. That is the
  cost, and it is bounded: the row object is eleven fields, and the service is one posting
  method with its validation.
- **Two entry paths now create gifts** (quick entry and batch posting), and both repoint a
  gift's default allocation the same way. If that repointing ever needs to change, it has to
  change in both. It is written once in `GiftBatchService` and once in
  `QuickGiftEntryController`; a shared helper on `GiftService` is the obvious later cleanup
  and is not worth the churn today.
- **An imported batch and a typed batch are different records**, so "show me everything that
  came in on 14 March" is answered by the gifts, not by the batches. That is correct: the
  gift is the fact, and both containers are how it got typed.
- Undo is not inherited. The import framework's batch undo does not reach a posted gift
  batch, and G-17 deliberately ships no unpost: the gifts a posting created are reversed the
  way every other wrong gift is, by refund or write-off (R-G3). If a real org asks for
  unpost, it is a new decision and it will have to answer what happens to a receipt that was
  already issued.
- **Revisit if the plan's Section 4.11 wording is taken as binding rather than indicative.**
  This ADR is the written record that Section 4.11's Gift Batch note and Section 5.2's Notes
  column are superseded for G-17, per the rule in plan Section 0 that a settled decision is
  re-opened only through a decision record.
- **Unverified in an org.** No Apex test in this repository has been executed, so everything
  above is reasoned from the code and enforced by tests that have been written and not run.

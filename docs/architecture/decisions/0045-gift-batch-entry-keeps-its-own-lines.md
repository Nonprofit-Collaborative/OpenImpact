# ADR-0045: Gift batch entry keeps its own lines rather than staging through the import framework

**Status:** Accepted
**Date:** 2026-09-23
**Source:** plan Section 5.2 feature G-17 ("Built on Import framework") and Section 4.11, Gift batch row ("Uses the Import framework underneath")

## Context

G-17 is the screen where Maria types twenty checks from the Tuesday mail. She has a
deposit slip that says the stack totals 4,812.50. She wants the date, fund, appeal and
payment method set once, a running total as she types, and to be refused a post while her
total and the bank's disagree.

The plan says twice that this is built on the import framework. That framework exists:
`Import_Batch__c` is one uploaded file, and `Import_Row__c` is one staged row holding the
source columns as text in `Raw_Values_JSON__c` plus resolved person and household lookups.
`ImportRowProcessor` matches each row's text to existing records and commits row by row,
asynchronously, keeping the rows that succeed (R-IB5). The plan's note is a good instinct
(principle 8: do not build what exists), written before either piece was built, so whether
the two are the same shape has to be checked rather than assumed.

## Decision

G-17 ships `Gift_Batch__c` with its own master-detail child `Gift_Batch_Row__c`, and does
not use `Import_Batch__c`, `Import_Row__c` or `ImportRowProcessor`. The plan's "built on
the import framework" note is superseded for G-17. The import framework is unchanged and is
still how a file of gifts is loaded.

What both paths share is the part that matters: posting inserts ordinary `Gift__c` records
in user mode through the ordinary triggers, so households, allocations, rollups and the
receipt lock behave as they do for any gift (canonical model R-GB6).

## Alternatives considered

- **Stage lines as `Import_Row__c` against an `Import_Batch__c`.** Rejected, for four
  reasons. The importer's hard problem is matching text to records; in the grid the donor
  is chosen from a record picker, so there is nothing to match. A staged row is untyped, so
  the entered total, the one number this feature checks, would be a sum over parsed JSON.
  The control total and the batch defaults have nowhere to live without adding fields to a
  Core object for a Giving feature (ADR-0014, ADR-0017). And the lifecycles are opposite: an
  import keeps the rows that succeed, while a deposit posts all its lines or none (R-GB5),
  synchronously, so Maria sees the answer at once.
- **Reuse `Import_Batch__c` as the container, with a new child for lines.** Rejected: it
  takes the part of the framework that carries least, and a typed batch would appear in the
  import history as an upload with no file.
- **No batch record: a grid that inserts gifts directly, checking the total in the
  browser.** Rejected: an unfinished batch would not survive the browser closing, and a
  check made only in the browser is one a stale tab can walk past.

## Consequences

- Giving owns two more objects and the code that posts them: one service, one selector, one
  writer for the two package-written fields (ADR-0021), and a controller for the grid.
- Two entry paths create gifts (quick entry and batch posting), and both designate a gift to
  the chosen fund through one method, `GiftService.applyChosenFunds`: it repoints the default
  allocation, or adds one when paused automation created none.
- The import framework's undo (C-19) does not reach a posted batch. A wrong gift from a
  batch is corrected as any wrong gift is, by refund or write-off (R-G3). An unpost would be
  a new decision, and would have to say what happens to a receipt already issued.
- Plan Sections 4.11 and 5.2 still say "built on the Import framework" until the owner's
  copy of the plan is updated to cite this record.

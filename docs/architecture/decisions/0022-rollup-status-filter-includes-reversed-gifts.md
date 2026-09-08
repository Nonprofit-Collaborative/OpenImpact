# ADR-0022: Packaged giving rollups include reversed gifts, and count gifts rather than transactions

**Status:** Accepted
**Date:** 2026-09-08
**Source:** product owner decision on a defect found in feature G-02; corrects the filter
sentence in canonical model Section 26 and upholds rule R-R9

## Context

Canonical model Section 26 says that every packaged rollup sourced from Gift uses the base
filter `Status equals Received`. Rule R-G3 (Section 18) says that a refund is a new gift
with a negative Amount whose own Status is Received, and that the package sets the
**original** gift's Status to Refunded, or to Written off, once nothing is left of it.

The two do not compose. Take the gift the refunds walkthrough uses: 250, refunded in two
parts of 100 and 150.

| Record | Amount | Status after the second refund |
|---|---|---|
| Original gift | +250 | Refunded |
| First refund | -100 | Received |
| Second refund | -150 | Received |

`SUM(Amount) WHERE Status = 'Received'` over those three rows is **-250**, not 0. The
positive row is filtered out by the status the package itself just wrote, and the two
negative rows that were only ever meant to cancel it survive. A fully refunded gift
therefore subtracts its own amount a second time: from the donor's Total Giving, from all
three fiscal year totals, from the Fund and Appeal Total Raised, and from Commitment Paid
To Date and Installment Paid Amount. A write-off does the same. The same defect reaches
the Fund and Soft Credit rows, which filter through `Gift__r.Status__c`.

That contradicts R-R9, which requires every aggregate to be correct in the presence of the
negative gifts refunds and write-offs create, and it contradicts the promise in
`docs/admin-guide/refunds.md` that the totals "correct themselves automatically". Nothing
in the engine is wrong: the filter is.

Section 26's filter sentence is settled text, which is why this is an ADR and not an edit.

## Decision

The packaged giving rollups filter on a **set** of statuses, and separate the question a
sum answers from the question a count answers.

1. **Money rows** filter on `Status` **in Received, Refunded, Written off**, and nothing
   else. This covers Total Giving, the three fiscal year totals, Fund Total Raised and
   Total Raised This Year, Appeal Total Raised, Commitment Paid To Date, and Installment
   Paid Amount. A partial refund of 100 against a gift of 250 nets to 150, a full refund
   nets to 0, and a write-off nets to 0, because the positive row and the negative rows
   that reverse it are now both inside the filter. A Pending or Failed gift is still
   excluded, which is the reason to have a status filter at all.

2. **Count rows, largest gift, and first and last gift date** take the same widened status
   filter **and** `Amount greater than 0`. A donor who gave 250 and had all of it back
   shows one gift and a total of zero. Section 26 already carried the amount condition on
   the two date rows, for exactly this reason; this extends the same reasoning to the
   count rows and to largest gift, where in an all-refunded history a negative amount
   could otherwise be the maximum.

3. **Rows sourced from Gift Allocation and from Soft Credit** take the same two shapes,
   reading the status through `Gift__r.Status__c` and testing the source record's own
   `Amount__c`, because a refund mirrors its allocations and its automatic soft credits
   negatively (R-GA3, R-SC5).

Rule R-G3 is unchanged: a refund is still a negative linked gift, and the original still
carries Refunded or Written off.

## Alternatives considered

**Change R-G3 so a fully refunded gift keeps Status Received and carries its reversed
state on a separate attribute.** This also makes the arithmetic work, and it keeps the
filter a single-value comparison. Rejected because it moves the refund action, the
receipting feature and ADR-0010's territory, the gift list views and the admin guide, to
fix something the filter can fix on its own. The status a gift displays is the thing users
read; the filter is an implementation detail of eleven shipped rows.

**Exclude the negative gifts instead, with `Amount greater than 0` on the money rows
too.** Rejected because it is wrong for a partial refund: the gift of 250 with 100 back
would report 250, not 150. The negative rows are how a partial refund is expressed and
they have to be summed.

**Do nothing and document the behavior.** Rejected: the number is wrong, not merely
surprising, and it is wrong in the direction that makes a donor look like a net taker.

## Consequences

- **A count and a sum now answer different questions, on purpose.** Gift Count says how
  many gifts this donor gave; Total Giving says what the organization is left holding. A
  donor with one fully refunded gift reads "1 gift, $0". These two numbers no longer
  divide into a meaningful average gift, and the admin guide says so in those words.
- **A gift recorded at zero is not counted.** `Amount greater than 0` excludes it, which
  is already true of the first and last gift date rows today. An in-kind gift entered at
  zero shows in the related list and not in the count. If that turns out to matter for
  in-kind reporting, the condition becomes `not equals 0` on the count rows, which is a
  one-row edit an admin can make without a code change.
- **The filter document now uses the `in` operator with a list.** `RollupFilterParser`
  already supports it and the Pledge Balance rows already ship it, so nothing new is
  required of the engine.
- **The status list is a literal in 38 shipped rows.** A new gift status that represents
  money the organization holds has to be added to every money row, and the settings
  console shows admins the list they are editing. A status meaning "not money" needs no
  change.
- **The soft credit rows are widened for manual credits only.** `SoftCreditService`
  removes a refunded gift's *automatic* credits (R-SC6): the positive row is deleted, not
  hidden, so widening the filter cannot double count it and equally cannot restore it. The
  status filter on those rows was only ever deciding whether a credit an administrator
  entered by hand on a gift later refunded still counts, and now it does, which is what
  R-SC6's promise that manual credits are untouchable implies. Recorded as still open, and
  outside this decision: for *automatic* credits, R-SC6's deletion and R-SC5's negative
  credit both fire on a full refund, so a recognition total goes to -250 rather than 0.
  That is a rule collision in G-08, not a filter defect, and it needs its own decision.

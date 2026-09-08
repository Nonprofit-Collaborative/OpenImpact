# ADR-0023: A refunded gift keeps its soft credits, and the negative gift reverses them

**Status:** Accepted
**Date:** 2026-09-08
**Source:** rule collision found while fixing the rollup filter defect (ADR-0022) and left
open there; corrects rules R-SC3, R-SC5 and R-SC6 in canonical model Section 24

## Context

Two soft credit rules both fire when a gift is refunded in full, and they undo each other's
work.

**R-SC5** says a refund produces matching negative soft credits, so recognition totals
correct themselves the same way giving totals do. The refund is a new gift for a negative
amount whose own status is Received (R-G3), it carries the original's donor, and
`GiftSoftCreditHandler.afterInsert` gives it automatic household credits like any other
gift. Those credits are negative, because the amount is.

**R-SC6** says the package recomputes a gift's automatic credits whenever its donor, its
amount, or its status changes, and removes them when the gift is deleted or refunded.
`GiftSoftCreditHandler.afterUpdate` fires on the status change that R-G3 writes to the
original gift, and `SoftCreditService.createHouseholdMemberCredits` excluded a Refunded or
Written off gift from the set of credits it wants, so the reconcile step deleted the
credit that gift already had.

Both happen. Take the gift the refunds walkthrough uses: Ana gives 250, Luis is credited
250 as her household member, and the whole 250 is refunded.

| Record | Amount | Status | Luis's automatic credit |
|---|---|---|---|
| Original gift | +250 | Refunded | deleted by R-SC6 |
| Refund gift | -250 | Received | -250, created by R-SC5 |

Luis's Total Soft Credits reads **-250**, not 0. The reversal is applied twice: once by
deleting the positive credit and once by creating the negative one. A write-off does the
same, because `GiftService.writeOff` is the same shape as a refund with a different status
on the original. A partial refund is unaffected: the original keeps the status Received,
so nothing is deleted, and 250 plus -100 is the 150 it should be.

This was noticed while fixing ADR-0022 and deliberately not fixed there, because it is a
rule collision rather than a filter defect: the two rules cannot both be right, and which
one gives way is a decision about what a recognition total means.

## Decision

**A gift keeps the automatic soft credits it earned, however its status later changes.
The only reversal is R-SC5's negative credit on the negative gift.** R-SC6 still removes a
gift's automatic credits when the gift is deleted, and still recomputes them when the
donor or the amount changes; it no longer removes them on refund.

In `SoftCreditService`, the check that excluded a Refunded or Written off gift from the
wanted set is gone. A status change still triggers a recompute, which is now a no-op
because the outcome no longer depends on status: idempotent by construction, so leaving
the trigger in place costs nothing and keeps recognition self-healing.

**The reading of a recognition total this chooses:** a fully refunded gift leaves a
visible pair that nets to zero, not an absence. Luis's soft credit list shows the 250 he
was recognized for and the -250 that took it back, and his total is 0. The history of what
was recognized stays legible on the record, and the total answers "what is he recognized
for now".

This is exactly how the gifts themselves behave under R-G3: the original gift is not
deleted or hidden when it is refunded, it keeps its row and its amount and gains a status,
and a second row cancels it. Recognition now mirrors money instead of contradicting it,
which is the promise R-SC5 makes in its own words.

Nothing else has to change. ADR-0022 already widened the two soft credit rollup rows to
read gift status in the set Received, Refunded, Written off, so the positive credit on the
now Refunded gift is inside the filter and the pair nets correctly. The count row's
`Amount__c` greater than 0 condition means the same donor is recognized on one gift, which
matches how the gift count rows read the same history.

## Alternatives considered

**Do not create negative credits for automatic credits at all, and let R-SC6's deletion be
the reversal.** R-SC5's negative credit would then apply only to manual credits, which
nothing deletes. This is the smaller change, one condition in the build step rather than
one in the wanted set, and it also produces 0 for a full refund.

Rejected, and not narrowly: **it gets a partial refund wrong.** A gift of 250 with 100
returned leaves the original at status Received, so nothing is deleted and the +250 credit
stands, while the -100 refund gift would now produce no credit at all. Recognition would
read 250 against giving of 150. The deletion path only fires on a full refund, so it
cannot be the general reversal mechanism, and pairing it with a suppressed negative credit
leaves partial refunds with no reversal at all. It also loses the record: a donor whose
gift was returned would show no trace of ever having been recognized, and a fundraiser
looking at last year's recognition would find a gift missing rather than reversed.

**Keep both rules and net the result somewhere else, for example by having the rollup skip
the negative credits of a refunded gift's reversal.** Rejected: it makes the stored data
wrong and asks every reader of the data, packaged rollup or admin's own report, to know
the compensating rule. ADR-0022 chose the filter over the rule for a filter defect; this
is the reverse case, where the rules genuinely disagree.

**Delete the negative gift's credits too, so a refunded gift leaves nothing.** This is the
"no trace" reading of a recognition total and it also nets to zero. Rejected for the same
reason R-G3 does not delete a refunded gift: an audit needs to see that recognition was
given and taken back, a receipt may already have been sent against it (ADR-0010), and a
year end recognition list produced before the refund has to be explicable afterwards.

## Consequences

- **A refunded gift shows two soft credit rows.** The Soft credits panel on the original
  gift still lists the household member at the full amount; the negative gift alongside it
  lists the same person at the negative amount. Both carry the Automatic badge. The soft
  credits admin guide says so, because a fundraiser seeing a negative credit for the first
  time will otherwise report it.
- **Recognition totals and giving totals now reverse the same way**, which is what makes
  the two numbers comparable on a donor record. Neither is a count of anything: a household
  member recognized on one fully refunded gift reads one credit and a total of zero, the
  same shape ADR-0022 gave to Gift Count and Total Giving.
- **`SoftCreditService` no longer reads gift status at all.** The constants
  `STATUS_REFUNDED` and `STATUS_WRITTEN_OFF` stay on the class because
  `MatchingGiftService` uses them for R-G11, which is a different question: whether a
  refunded gift may be half of a matching pair.
- **Still open, and outside this decision: matched donor credits do not reverse.** The
  Matched Donor credits R-G11 creates are removed only when the link between the two gifts
  is undone, and the negative gift recording a refund is not itself linked to a matching
  pair, so it produces no negative matched donor credit. A refunded employer gift therefore
  leaves its matched donor credit standing at the full amount. That behavior is unchanged
  by this decision, in either direction, and fixing it means deciding whether a refund
  should propagate along the match link, which belongs with G-10 (matching gift
  linkage, plan Section 5). An earlier draft of this ADR said G-09, which is Tributes.
- **Unverified in an org.** No Salesforce org is available to this change, so the Apex test
  added with it has not been executed and the behavior above is reasoned from the code
  rather than observed.

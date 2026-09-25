# ADR-0054: A Pending gift that will never be paid is cancelled, not written off

**Status:** Accepted
**Date:** 2026-09-24
**Source:** product owner decision of 2026-09-24 on the G-20 builder's recommendation; amends
plan Section 5.2 feature G-04 ("Refund and write-off as linked negative gifts"), ADR-0022,
ADR-0023 and ADR-0031.

## Context

G-04 gave a gift that is never going to be collected one path: a write-off, which is a linked
negative gift for what is left, with the original moved to Written off (R-G3, ADR-0010). That
shape is right for money the organization received and gave up. For a Pending gift, a pledge
payment or a check that never came, it is wrong in three ways:

- **It puts money that never arrived into the books.** Written off is one of the statuses every
  total, the accounting export (ADR-0051) and receipts read, and so is the negative gift's
  Received. The totals net to zero, but the export now holds two rows for a gift that was never
  money, and the month the Pending gift is dated in changes after it was exported.
- **It collides with a closed period (G-20).** A Pending gift dated in a closed month cannot move
  into the books, so the write-off had to be refused, and the only advice left was to delete the
  gift, which loses the record that it was expected.
- **Deleting instead loses history** and releases the installment silently.

## Decision

**Cancelled is a new Gift Status value: a Pending gift that will never be paid.** It is a status,
not a money event.

- No negative gift is created, and the gift is not edited in any other way.
- Every packaged total, the accounting export, receipts and statements, acknowledgments and the
  retention reports count only Received, Refunded and Written off, so Cancelled is outside all of
  them by construction. No rollup definition changes. The packaged In-kind Gifts This Year
  report had no status filter and summed Pending fair market value too; it gains the same
  Received, Refunded and Written off filter.
- Cancelled is not in the books (R-G14), so the posting lock and a closed period do not refuse
  cancelling a Pending gift dated in a closed month.

**Status moves around Cancelled only these ways:** Pending to Cancelled, and Cancelled back to
Pending when the gift turns out to be coming after all. Nothing else moves to or from Cancelled.
A Cancelled gift that is then paid goes back to Pending and then to Received, two edits, so
there is one way into the money statuses and the posting lock's rules for it stay as they are. A
gift may be created Cancelled, which an import of history needs.

**Written off is kept only for Received gifts, and so is Refunded.** Pending does not move to
Refunded or Written off, and `GiftService.refund` and `writeOff` refuse a gift that is not
Received, saying to cancel it instead. Refused rather than redirected: a caller of `writeOff`
expects a negative gift and gets its id back; quietly cancelling would change what the call
means for the Connect API and any flow that uses it.

**Cancelling releases the installment, as a delete does (R-CM4).** The gift's Installment link is
cleared in the same save, and the commitment handler recalculates the installment it left, so it
is open for the next gift. The Commitment link stays, as history. Moving the gift back to Pending
does not link it again: a person picks the installment, as for any new gift. A gift created
Cancelled holds no installment either; any Installment link on it is cleared in the save.

**Every move into or out of Cancelled is logged** as an Error Log entry at Info naming the gift
and the user, since Gift has no field history. These rules run from the Gift core rules
automation (ADR-0017), not an Always Runs one: a data load with automation paused may set any
status, which a migration of history needs, and the posting lock still runs.

### What this amends

- **G-04 and R-G3:** a write-off is for received money only; a Pending gift is cancelled.
- **ADR-0022:** the status filter is unchanged, and Cancelled is named among the statuses outside
  it, with Pending.
- **ADR-0023:** a Cancelled gift keeps its soft credits, as a refunded one does. They count
  nowhere, because the soft credit totals read the gift's status.
- **ADR-0031:** a Cancelled employer gift needs no negative Matched Donor credit: there is no
  negative gift to carry one, and its credits already drop out of every total with its status. A
  Cancelled gift is not half of a new matching gift pair, like a Refunded or Written off one
  (R-G11).
- **G-20 ADR-0053:** a write-off never moves a Pending gift into the books any more, so the
  refusal `GiftPostingLock.refusalForStatusChange` gave a write-off into a closed period is
  removed with its label; the lock's own refusal on save is unchanged.

## Consequences

- The admin guides stop advising to delete an unpaid Pending gift; they say to cancel it.
- A Pending gift already written off before this change keeps its negative gift. No released
  org holds one, so nothing is migrated.
- A report or list view an organization built on "Status not equal to Pending" now includes
  Cancelled gifts; the packaged ones filter on the money statuses and are unaffected.

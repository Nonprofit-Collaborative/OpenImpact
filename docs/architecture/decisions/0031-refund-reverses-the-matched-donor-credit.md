# ADR-0031: A refund of the employer's gift reverses the matched donor credit, along the link

**Status:** Accepted
**Date:** 2026-09-09
**Source:** the question ADR-0023 recorded as still open and sent to G-10; restates rules
R-G11 (Section 18) and R-SC5 (Section 24) of the canonical model

## Context

ADR-0023 settled what a refund does to a gift's *household* credits: the gift keeps the
credit it earned and the negative gift carries a negative credit that cancels it. It left
one credit out, on purpose, because it belongs to a different feature.

R-G11 credits an employee on their employer's gift, Role Matched Donor, for the employer
gift's whole amount. That credit is created when the link is made and removed when the link
is undone, and nothing else touches it. A refund is not a link change: `GiftService.refund`
inserts a negative gift whose `Original_Gift__c` points at the employer's gift, and that
negative gift is not half of a matching pair, so it produces no matched donor credit of its
own. Riverbend matches Ana's gift with 500, Ana is recognized for 500, Riverbend's bank
reverses the check, and Ana is still recognized for 500.

Two facts constrain the answer.

**A partial refund has to come out right.** ADR-0023's governing argument is that deletion
cannot be the general reversal mechanism, because only a full refund moves the original's
status, so a partial refund would leave recognition at the full amount against giving that
has dropped. Any answer here has to survive 500 matched and 200 returned, not only 500
returned.

**ADR-0022's rollup filter already reads both rows.** The two soft credit rollups filter
`Gift__r.Status__c` in Received, Refunded, Written off, and the count row additionally
requires `Amount__c` greater than 0. A positive credit on a refunded gift and a negative
credit on the negative gift that reverses it are therefore both inside the money filter,
and only the positive one is inside the count filter. The arithmetic this decision needs is
already shipped.

## Decision

**A refund propagates along the match link as a negative credit, the same shape R-SC5 gives
every other automatic credit.** When a negative gift reverses a gift that carries automatic
Matched Donor credits, that negative gift carries the matching negative Matched Donor
credits: same person, Role Matched Donor, Is Automatic true, amount prorated to the amount
returned. A write-off is the same shape with a different status on the original.

The mechanism is one idempotent reconcile in `MatchingGiftService`, keyed on the gift being
reversed rather than on the refund action, so it produces the same records whatever order
the two events happen in:

- a refund or write-off of a linked employer gift creates the negative credit, on the
  negative gift, from the gift trigger;
- linking a pair whose employer gift has already been partly refunded creates the positive
  credit and the negative ones together, so recognition never reads the full amount for a
  gift that was already partly returned;
- unlinking removes both halves, because the negative credit exists only to reverse the
  positive one and an orphaned minus 200 is a worse number than no rows at all.

**Only the employer's gift reverses the credit.** The Matched Donor credit is recognition
for the employer's money, and its amount is the employer gift's amount. A refund of the
*employee's* own gift reverses the employee's own hard credit and leaves the match alone:
the company's money is still money the organization holds, and the employee did cause it.
That falls out of the mechanism rather than being special cased, because the credits it
mirrors live only on the employer's gift.

R-G11's refusal to *create* a link involving a refunded gift is unchanged. Refusing a new
link and reversing an existing one are different questions, and the answer to the second is
what makes the refund of an already linked gift safe.

### The worked partial refund

Riverbend gives 500, matched to Ana's gift. Riverbend then asks for 200 back.

| Record | Amount | Status | Ana's matched donor credit |
|---|---|---|---|
| Employer gift | +500 | Received (part is still held, R-G3) | +500 |
| Refund gift | -200 | Received | -200 |

Ana's **Total Soft Credits** reads **300**: both credits are on gifts whose status is
inside ADR-0022's widened set, so the rollup sums 500 and minus 200. Three hundred is what
Riverbend still holds because of her, which is exactly what the number claims to say. Her
**Soft Credit Count** reads **1**, because the count row requires `Amount__c` greater than
0: she was recognized on one gift, and the reversal is not a second one. Refund the other
300 and the total reads 0, the count still reads 1, and the employer gift's status moves to
Refunded, which is inside the money filter and therefore still summed. The same shape
ADR-0022 gave Gift Count and Total Giving, and the same shape ADR-0023 gave household
credits.

## Alternatives considered

**Recompute the matched donor credit down to the amount still held**, so the employer gift
carries a single credit of 300. It reads more simply on one screen, and it is the smaller
diff. Rejected because it makes the reversal silent: the row that said 500 now says 300 and
nothing on the record says it ever said 500. ADR-0010 and ADR-0023 both turn on reversal
being visible, a year end recognition list produced before the refund has to be explicable
afterwards, and a credit whose amount depends on rows belonging to other gifts stops
answering "what did this gift recognize". It would also be the only automatic credit in the
package that reverses by edit rather than by a second row.

**Leave the credit standing and document it.** The honest version of the argument is that
Ana did the work: she asked her employer to match, and the employer's later reversal is not
her failure. Some shops would keep the recognition on those grounds. Rejected, and I do not
believe it: a recognition total sits next to a giving total on the same record, and 500
recognized against nothing held reads as a data error rather than as a considered position.
The record of what Ana earned is not lost by this decision, because the positive credit
stays on the employer's gift with its date; what changes is only what the total says the
organization is holding because of her. A shop that wants to honor the intent has the row
to report on.

**Unlink the pair automatically on a full refund**, letting R-G11's existing removal do the
work. Rejected twice over: it deletes the positive credit as well, which is the silent
erase ADR-0023 rejected, and it does nothing at all for a partial refund, because there is
no partial unlink.

## Consequences

- **A refunded matching gift shows two matched donor rows**, one on each gift, both with
  the Automatic badge, exactly as a refunded household credit does. The matching gifts and
  soft credits admin guides say so.
- **The matching gifts guide no longer tells staff to unlink before refunding.** That
  advice existed because the credit did not reverse. The link now survives the refund on
  purpose: it is the record of what the money was, and the recognition corrects itself.
- **The receipt lock is not in the way.** This path inserts, updates and deletes
  `Soft_Credit__c` rows only. It never edits a gift's amount, date or donor, so ADR-0024's
  lock has nothing to refuse and needs no override.
- **No object, field or rollup row changes.** ADR-0022's widened status filter is what
  makes the pair net, and it is already shipped on all 38 rows.
- **Matched donor credits are still not recomputed when the employer gift's amount is
  edited.** Only the reversal path is settled here. An edit to a linked gift's amount leaves
  the credit at the old amount, which is a real gap and a separate one from this question.
- **Unverified in an org.** No Salesforce org is available to this change, so the Apex tests
  added with it compile but have not been executed, and the behavior above is reasoned from
  the code rather than observed.

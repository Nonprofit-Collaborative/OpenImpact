# Refunds and write-offs

## What it does

Sometimes money goes back: a card is charged twice, a donor asks for a gift to be returned,
or a pledged gift is never going to arrive and finance writes it off. Open Impact never
edits or deletes the original gift, because it really happened and Jen reconciles against
it. Instead it records a second gift for a negative amount, linked to the original, with
the reason on it.

That keeps three things true at once: the bank reconciles, fund and donor totals correct
themselves automatically, and anyone looking at the original gift can see what became of it.

## How to turn it on

Refunds and write-offs arrive with the Giving module. There is nothing to configure.

The **Refund** and **Write Off** actions appear on the gift page for anyone with the
**Giving Staff** or **Giving Admin** permission set. **Giving Read Only** users can see the
result but cannot record one.

## A five-minute walkthrough

You are David. The 250 check from the Gifts page walkthrough was partly a mistake: 100 of it
was meant for another organization, and the donor has asked for it back.

1. Open the gift `G-000001`. Its **Status** is `Received` and its **Amount** is 250.
2. Click **Refund**.
3. Enter 100 as the amount and "Donor asked for the misdirected portion back" as the reason,
   then confirm.
4. Open Impact creates a second gift for minus 100. Open it. Its **Original Gift** points at
   `G-000001`, its **Donor** and **Appeal** are the same as the original, its **Gift Date**
   is today, its **Status** is `Received` (because the refund itself is a transaction that
   happened), and its **Refund Reason** carries what you typed.
5. Look at that refund gift's allocations: one allocation for minus 100 against `General`,
   mirroring the original's designation, so the fund's total corrects itself.
6. Go back to `G-000001`. It still shows 250 and its **Status** is still `Received`, because
   only part of it came back. The refund is visible in its **Refunds** related list.
7. Now refund the rest: click **Refund** on `G-000001` again, enter 150, and confirm. This
   time the original's **Status** changes to `Refunded`, because the whole gift has now gone
   back.
8. To see a write-off instead, enter a new gift for 500, open it, and click **Write Off**
   with the reason "Pledged at the gala, never paid". Open Impact creates a linked gift for
   minus 500 and sets the original's **Status** to `Written off`.

## Common mistakes

- **Editing the gift amount instead of refunding.** If a receipt has been issued the save is
  refused outright, and if it has not, you have quietly restated a period Tom already
  reported to the board. Record a refund: it is one click and it leaves a trail.
- **Refunding more than is left.** The action is refused with "This refund is larger than
  the amount left on the gift." Check the gift's **Refunds** related list: part of it may
  have gone back already.
- **Deleting the negative gift to "undo" a refund.** That leaves the original marked
  `Refunded` with nothing explaining why. If a refund was recorded in error, record the
  correcting entry and note the reason, so the history stays readable.
- **Expecting totals to move immediately.** Donor, fund and appeal totals are calculated by
  the rollup engine. Each record's **Rollups Last Calculated** tells you when its numbers
  were worked out.

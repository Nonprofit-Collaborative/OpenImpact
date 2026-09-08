# Refunds and write-offs

## What it does

Sometimes money goes back: a card is charged twice, a donor asks for a gift to be returned,
or a pledged gift is never going to arrive and finance writes it off. Open Impact never
edits or deletes the original gift, because it really happened and Jen reconciles against
it. Instead it records a second gift for a negative amount, linked to the original, with
the reason on it.

That keeps three things true at once: the bank reconciles, fund and donor totals correct
themselves automatically, and anyone looking at the original gift can see what became of it.

## What a refund does to the donor's totals

The negative gift and the gift it reverses cancel each other, so nothing has to be adjusted
by hand. Ana gave 250 and asked for 100 back:

| After | Total giving | Gift count |
|---|---|---|
| The 250 gift | 250 | 1 |
| 100 refunded | 150 | 1 |
| The other 150 refunded as well | 0 | 1 |

**A fully refunded gift leaves the donor's total at zero and still counts as one gift.**
That is deliberate. Ana did give, once, and it is part of her history with you; the
organization is simply holding none of it. A write-off behaves the same way. The same
arithmetic runs on the fund's and the appeal's total raised, on a pledge's paid to date,
and on Ana's giving for the fiscal year the gifts fall in.

Two things follow from it that surprise people. Total giving divided by gift count is not a
useful average gift for a donor with refunds, because the two numbers deliberately answer
different questions. And Ana's **Last gift date** stays on the day of the original gift
rather than moving to the day of the refund, because the date totals ignore negative gifts.

## How to turn it on

Refunds and write-offs arrive with the Giving module. There is nothing to configure.

The **Refund or Write Off** action appears on the gift page for anyone with the **Giving
Staff** or **Giving Admin** permission set. It asks which of the two you are recording, so
there is one button rather than two that look unrelated. **Giving Read Only** users can see
the result but cannot record one.

## A five-minute walkthrough

You are David. The 250 check from the Gifts page walkthrough was partly a mistake: 100 of it
was meant for another organization, and the donor has asked for it back.

1. Open the gift `G-000001`. Its **Status** is `Received` and its **Amount** is 250.
2. Click **Refund or Write Off**.
3. Leave the choice at the top on **Refund part or all of this gift**. The amount starts at
   what is left of the gift, which is 250. Change it to 100, type "Donor asked for the
   misdirected portion back" as the reason, and click **Record it**.
4. Open Impact creates a second gift for minus 100. Open it. Its **Original Gift** points at
   `G-000001`, its **Donor** and **Appeal** are the same as the original, its **Gift Date**
   is today, its **Status** is `Received` (because the refund itself is a transaction that
   happened), and its **Refund Reason** carries what you typed.
5. Look at that refund gift's allocations: one allocation for minus 100 against `General`,
   mirroring the original's designation, so the fund's total corrects itself.
6. Go back to `G-000001`. It still shows 250 and its **Status** is still `Received`, because
   only part of it came back. The refund is visible in its **Refunds** related list.
7. Now refund the rest: click **Refund or Write Off** on `G-000001` again. The amount starts
   at 150, which is what is left. Give a reason and click **Record it**. This time the
   original's **Status** changes to `Refunded`, because the whole gift has now gone back.
8. To see a write-off instead, enter a new gift for 500, open it, click **Refund or Write
   Off**, and choose **Write off what is left of this gift** with the reason "Pledged at the
   gala, never paid". There is no amount to type: a write-off is always what is left. Open
   Impact creates a linked gift for minus 500 and sets the original's **Status** to
   `Written off`.

## Common mistakes

- **Editing the gift amount instead of refunding.** If a receipt has been issued the save is
  refused outright, and if it has not, you have quietly restated a period Tom already
  reported to the board. Record a refund: it is one click and it leaves a trail.
- **Refunding more than is left.** The action is refused with "This refund is larger than
  the amount left on the gift." Check the gift's **Refunds** related list: part of it may
  have gone back already.
- **Typing a negative gift by hand instead of using the action.** You cannot: **Original
  Gift** and **Refund Reason** are filled in by the action and are read only on the page. The
  action is what mirrors the original's designation and updates its status, and a hand-typed
  negative gift would do neither.
- **Deleting the original to make a refund go away.** Open Impact refuses, with "This gift has
  a refund or a write-off linked to it, so it cannot be deleted". If the refund itself was
  recorded in error, delete the refund first.
- **Expecting totals to move immediately.** Donor, fund and appeal totals are calculated by
  the rollup engine. Each record's **Rollups Last Calculated** tells you when its numbers
  were worked out.

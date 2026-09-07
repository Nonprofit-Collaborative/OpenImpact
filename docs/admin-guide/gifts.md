# Gifts

## What it does

A gift is one transaction that arrived: money, stock or goods, from one donor, on one date.
David enters the gift, and Open Impact fills in the rest: the household it should be
credited to, the date if he leaves it blank, and the fund it is designated to when he does
not choose one. Because a gift is a record of something that happened, it is never edited
away: a refund is a separate, linked gift (see the Refunds page).

Everything the board and the bookkeeper ask for comes off these records: donor totals, fund
balances, appeal results, and the receipt.

## How to turn it on

Gifts arrive with the Giving module. Before David enters his first gift, do two things
once:

1. Create at least one fund and mark it as the default (see the Funds page). A gift saved
   without a designation goes there.
2. Open **Nonprofit Settings**, choose **Giving**, and check the settings on that page:
   **Default Fund**, **Default Appeal** (optional), and **Automatic Household Soft Credits**.

Then give your fundraising staff the **Giving Staff** permission set, and give yourself
**Giving Admin**. People who only need to see gifts get **Giving Read Only**.

No Salesforce Setup step is needed.

## A five-minute walkthrough

You are David, and a check from Maria's neighbour arrived this morning.

1. Open the **Funds** tab, click **New**, name the fund `General`, tick **Is Default**, and
   save.
2. Open the **Appeals** tab, click **New**, name the appeal `Spring appeal`, and save.
3. Open the **Gifts** tab and click **New**.
4. In **Donor Contact**, choose a person who belongs to a household. Leave **Donor Account**
   empty: a gift has one donor, either a person or an organization, never both.
5. Enter an **Amount** of 250, choose the **Type** `Check`, and leave **Gift Date** empty.
6. Choose `Spring appeal` in **Appeal** and save.
7. Look at the saved gift. **Gift Date** is today, because you left it blank. **Household**
   shows the donor's household, filled in by Open Impact rather than by you, which is what
   keeps household totals right after somebody moves house or marries.
8. Scroll to **Gift Allocations**. There is one allocation, for the whole 250, designated to
   `General`. You never asked for it: a gift with no designation is allocated in full to the
   default fund, so no money is missing from fund reporting.
9. Open that allocation and change its **Amount** to 100. The save is refused with "The
   allocations of this gift total 100.00, but the gift is 250.00. The difference is 150.00."
   Set it back to 250 and save, or add a second allocation for the other 150 to a different
   fund.
10. Now refund part of the gift: follow the Refunds page from step 1.

## Common mistakes

- **Filling in both Donor Contact and Donor Account.** The save is refused with "Enter a
  donor contact or a donor account, not both. A gift has exactly one donor." Use the account
  when an organization or a household gives in its own name, and the contact when a person
  gives.
- **Entering a gift of zero.** The save is refused with "A gift amount cannot be zero."
  Zero-value records break averages and counts. If you are recording goods, enter the fair
  market value.
- **Editing the amount after a receipt has been issued.** The save is refused with "This
  gift has a receipt number, so its amount, date and donor cannot change. Void the receipt
  and reissue it, or record a refund." That rule protects the document already in the
  donor's hands.
- **Splitting a gift and leaving the split short.** Allocations always total the gift. The
  error names the difference so you can see exactly how much is unallocated.
- **Typing a name for the gift.** You never do: gifts number themselves, `G-000001` and
  onward. That number is not a receipt number.

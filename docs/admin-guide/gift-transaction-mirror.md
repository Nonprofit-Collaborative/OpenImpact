# Gift Transaction Mirror

## What it does

BarnCRM records money received as gifts. Nonprofit Cloud (Agentforce Nonprofit) records the
same thing as Gift Transactions, and everything it builds on top reads only those: donor gift
summaries on donor pages, giving levels, actionable lists and Agentforce actions. The Gift
Transaction mirror keeps the two in step, in one direction you choose, so an organization that
enters gifts in BarnCRM still sees them in Nonprofit Cloud, or one whose gifts arrive in Nonprofit
Cloud still gets them in BarnCRM.

- **Gifts to Gift Transactions.** Every received gift gets a matching Gift Transaction. Choose
  this when you enter gifts in BarnCRM and still use Nonprofit Cloud's donor summaries or
  Agentforce.
- **Gift Transactions to Gifts.** Every paid Gift Transaction becomes a gift. Choose this when
  gifts still arrive in Nonprofit Cloud, through its gift entry or a payment integration.

Only one direction can be on. It is separate from the [Opportunity mirror](opportunity-mirror.md),
which has its own direction. Each gift remembers its Gift Transaction in its **Gift Transaction
ID**, whichever side came first, so changing the direction later never copies anything twice.

The mirror works in runs: **Run now**, and a nightly run at 01:35. Saving a gift does not copy it
at once. Nonprofit Cloud works out its donor summaries in its own scheduled runs, so a gift copied
at once would not show on a donor page any sooner.

**Gifts to Gift Transactions** copies each gift that is Received, has an amount above zero and is
not in-kind, dated on or after the start date you set:

| On the gift | On the Gift Transaction |
|---|---|
| Donor Account, or the donor's Household | Donor |
| Gift Date | Transaction Date |
| Amount | Original Amount, and Current Amount when it is created |
| (the paid status you set) | Status, when it is created |
| Gift number (for example G-000123) | Name, when it is created and your org lets it be set |

When the gift changes, the next run updates the Donor, Transaction Date and Original Amount. It
never changes Status or Current Amount afterwards: Nonprofit Cloud keeps those up to date itself,
for example when you record a refund there. Nothing else is written: no designation, campaign,
source code, payment details or soft credits yet.

Refunds and write-offs are not copied. BarnCRM records a refund as a second gift with a negative
amount, and Nonprofit Cloud would count that as one more gift. A gift refunded after it was copied
keeps its Gift Transaction as it was. If Nonprofit Cloud's totals must show the refund, record the
refund on the Gift Transaction in Nonprofit Cloud too. The reconciliation lists every such gift.
Pending, Cancelled and in-kind gifts are not copied either.

**Gift Transactions to Gifts** makes one gift from each Gift Transaction that has your paid status
and is dated on or after the start date: the donor is the Gift Transaction's donor account, the
amount is its Original Amount, the date its Transaction Date, the type Other and the status
Received. The gift then gets its fund, household and thank-you status from your Giving settings,
like any gift. A gift is never changed afterwards, even if its Gift Transaction is: the
reconciliation shows the difference.

Nothing is ever deleted. Deleting a gift leaves its Gift Transaction, and the Error Log gets one
Warning naming the gifts deleted and their Gift Transactions. In Gift Transactions to Gifts, the
next run makes a new gift from a Gift Transaction that is still paid. Turning the mirror off
leaves every record where it is.

## How to turn it on

You need the Connect module and Nonprofit Cloud fundraising: the Fundraising Access license, and
for you and whoever schedules the run, the Fundraising User permission. Without them the Gift
Transaction mirror page says the mirror is not available, and nothing else happens.

1. Give yourself the **Gift Transaction Mirror** permission set. Until the Module Manager
   arrives, module permission sets are assigned in Setup.
2. Find the Status value that means paid in your org. In Nonprofit Cloud, open any paid Gift
   Transaction and note its Status. The mirror needs the value's API name, which is usually the
   same as what you see; Setup, Object Manager, Gift Transaction, Fields, Status lists both.
3. Open **BarnCRM Settings**, choose **Giving**, and set:
   - **Gift Transaction mirror paid status** to that value, for example `Paid`;
   - **Gift Transaction mirror start date**: only gifts and Gift Transactions dated on or after it
     are mirrored. If you loaded your Nonprofit Cloud gifts into BarnCRM, choose the day after
     the last load, so those gifts are not copied back as second Gift Transactions and those Gift
     Transactions do not become second gifts;
   - **Gift Transaction mirror direction**.
   Until the paid status and the start date are both set, nothing is mirrored.
4. Still in **Giving**, open **Gift Transaction mirror** (the row shows only to someone with the
   permission set). Click **Run now** once, and **Schedule nightly**, so the mirror catches up
   every night at 01:35. The page shows when the last run completed and what it did, and Health
   Check warns if two days pass without one.

**Whose access the run uses.** A run reads and writes with the access of the person who started or
scheduled it. That person needs the Manage BarnCRM Settings permission, the Gift Transaction
Mirror permission set, and, in Nonprofit Cloud, access to create and edit Gift Transactions. Gift
entry staff need none of this: their gifts are copied by the next run.

**Two switches, one of them in charge.** **Gift Transaction mirror direction** decides what the
mirror does. The **Gift Transaction mirror** row on the Automation page is the switch every
BarnCRM automation has: switched off, the runs stop. While automation is paused, or the switch is
off, a run does nothing and the Error Log says so once.

## A five-minute walkthrough

Do this as Maria, in an org with Nonprofit Cloud fundraising and the sample data loaded.

1. In **BarnCRM Settings**, **Giving**, set **Gift Transaction mirror paid status** to your paid
   value, **Gift Transaction mirror start date** to the first of this month, and **Gift
   Transaction mirror direction** to **Gifts to Gift Transactions**. Save.
2. Enter a gift of 100 from Luis Garcia with **Quick gift entry**, dated today.
3. Open **Gift Transaction mirror** and click **Run now**. Wait a minute and reload the page: the
   last run says how many Gift Transactions were created, one for each received gift dated this
   month, Luis's included. Open Luis's gift: its **Gift Transaction ID** is filled in. Open that Gift Transaction: Original Amount 100, Transaction Date today, and the
   donor is Luis's account or household.
4. Change the gift's amount to 150, click **Run now** again, and reload the Gift Transaction:
   Original Amount 150.
5. Back on the page, open **Reconciliation**, choose this month, and click **Compare**. The gift
   count and total match the Gift Transaction count and total, apart from any Gift Transactions
   your org had already, which are listed as having no gift.
6. Set the direction to **Gift Transactions to Gifts** and save. In Nonprofit Cloud, enter a paid
   Gift Transaction of 60 for Luis dated today, then click **Run now**. A gift of 60 for Luis
   appears, and its **Gift Transaction ID** names that Gift Transaction.

## Common mistakes

**The page says the mirror is not available.** You cannot see Gift Transactions: your user needs
the Fundraising User permission, or the org does not have Nonprofit Cloud fundraising. The same
message appears when your org's Gift Transaction fields differ from what this version expects.
Nothing is wrong with your data in that case: tell whoever supports your BarnCRM installation,
because the mirror cannot work in that org until BarnCRM is corrected.

**The page says the paid status is not one of your org's Status values.** The value must match an
active Status exactly, including capitals, as its API name. Copy it again from Setup, Object
Manager, Gift Transaction, Fields, Status.

**Every gift from before the mirror was set up got a second Gift Transaction.** The start date was
set before the day you loaded your Nonprofit Cloud gifts. Delete the extra Gift Transactions in
Nonprofit Cloud (the reconciliation for that range lists them against their gifts), clear those
gifts' **Gift Transaction ID** in the **Gifts and their Gift Transactions** list view, and set the
start date to the day after the load.

**A gift has no Gift Transaction.** The reconciliation lists it. Most often it is dated before the
start date, is not Received, is in-kind, or no run has happened since it was entered. Otherwise
Nonprofit Cloud refused it, for example because the donor has no account (a donor stored as a
contact with no household), or because of a validation rule or a required field your org added.
The Error Log has a Warning with Salesforce's message and the gifts it refused. Fix the cause, then
click **Run now**.

**A linked Gift Transaction was deleted, or is not visible to you.** The mirror does not make a
replacement, because it cannot tell a deleted Gift Transaction from one the person running may not
see, and a replacement for one that still exists would count the gift twice. Check, as someone who
sees every Gift Transaction, whether it exists. If it was deleted, clear the gift's **Gift
Transaction ID** in the **Gifts and their Gift Transactions** list view, which the mirror adds,
and the next run makes a new one.

**Linking a gift to a Gift Transaction you already had.** In the **Gifts and their Gift
Transactions** list view, paste the Gift Transaction's record ID (the 18-character code in its web
address) into the gift's **Gift Transaction ID** and save. In Gifts to Gift Transactions the next
run writes the gift's donor, date and amount onto it. A Gift Transaction belongs to one gift only;
pasting an ID another gift holds fails the save with a duplicate value error.

**Gifts from Gift Transactions are thanked twice.** They are ordinary gifts, so your acknowledgment
rules apply. If Nonprofit Cloud already sends the thank you, add an acknowledgment rule with
channel None for gifts of type Other (see [Acknowledgments](acknowledgments.md)).

**Both mirrors bringing gifts in.** If Gift Transactions to Gifts and the Opportunity mirror's
Opportunities to Gifts are both on, a tool that writes an Opportunity and a Gift Transaction for
the same donation makes two gifts. Choose one of the two.

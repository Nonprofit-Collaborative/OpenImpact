# Opportunity Mirror

## What it does

Open Impact records money received as gifts. Salesforce's own sales object, the Opportunity,
is what NPSP, many fundraising apps and many online giving tools use for the same thing. The
Opportunity mirror keeps the two in step, in one direction you choose.

- **Gifts to Opportunities.** Every gift gets a matching Opportunity, kept up to date when the
  gift changes. Choose this when something in your org still reads Opportunities: NPSP
  rollups and soft credits during a move from NPSP, Campaign totals, or an app that only knows
  Opportunities.
- **Opportunities to Gifts.** Every won Opportunity becomes a gift. Choose this when your
  online giving tool writes Opportunities, so its donations arrive in Open Impact as gifts.

Only one direction can be on. Changing it later never copies anything twice, because each gift
remembers its Opportunity in its **Opportunity ID**, whichever side came first.

**Gifts to Opportunities** copies:

| On the gift | On the Opportunity |
|---|---|
| Amount | Amount |
| Gift Date | Close Date |
| Status | Stage: your won stage (`Closed Won`) for a Received, Refunded or Written off gift; your lost stage (`Closed Lost`) for a gift moved back to Pending or Cancelled |
| Donor Account, or the donor's Household | Account |
| Appeal (its Campaign, when Campaign sync gave it one) | Campaign |
| Donor | Primary Contact Role, with Role Donor |

A new Opportunity is named after the donor and the date, and uses the Donation record type
when your org has one. Pending and Cancelled gifts get no Opportunity. A refund or write-off,
which is its own gift with a negative amount, gets its own Opportunity with that negative
amount, so an NPSP total goes down exactly as the Open Impact total does.

**Opportunities to Gifts** makes one gift from each won Opportunity closed on or after the start
date you set: the donor is the Opportunity's primary contact (or its Account when it has none),
the amount and date are the Opportunity's, the type is Other, the status Received, and the
appeal is the one whose Campaign is the Opportunity's Campaign. The gift then gets its fund,
household and thank-you status from your Giving settings, like any gift. A gift is never
changed afterwards, even if its Opportunity is: the reconciliation shows the difference.

Nothing is ever deleted. Deleting a gift leaves its Opportunity, and turning the mirror off
leaves every Opportunity and gift where it is.

## How to turn it on

You need the Connect module and a Salesforce edition with Opportunities (Sales Cloud, Service
Cloud, NPSP or Nonprofit Cloud). An org on Salesforce Platform licenses only has none, and the
Opportunity mirror page says so.

1. Give yourself the **Opportunity Mirror** permission set. Until the Module Manager arrives,
   module permission sets are assigned in Setup.
2. Open **Nonprofit Settings**, choose **Giving**, and set **Opportunity mirror direction**.
   For **Opportunities to Gifts**, also set **Opportunity mirror start date**: only won Opportunities closed on or after it become gifts.
   Until it is set, no Opportunity becomes a gift, so that a switch in an org with years of
   Opportunities does not create, and thank donors for, a gift for every one of them.
3. Still in **Giving**, open **Opportunity mirror**. Click **Run now** once, to copy what you
   already have, and **Schedule nightly**, so the mirror catches up every night at 01:30.

**Whose access the copy uses.** Opportunities are written with the access of the person saving
the gift, and the nightly run with the access of the person who scheduled it. Someone who
cannot create and edit Opportunities still saves gifts; they get their Opportunities in the
next run. Give fundraising staff Opportunity create and edit access in Setup if you want the
Opportunity at once. The Error Log has one Warning when such a person creates gifts; imports
add none, and the nightly run catches them up.

**Two switches, one of them in charge.** **Opportunity mirror direction** decides what the
mirror does. The **Opportunity mirror** row on the Automation page is the pause every Open
Impact automation has: it stops only the copy made when a gift is saved, and the runs follow
the direction alone.

**Very large saves.** When one save holds so many gifts that copying them would push it past
Salesforce's limits, the gifts save without their Opportunities and one Warning says so. The
next run copies them. A load of 200 rows at a time, as Data Loader and the importer send, is
copied as usual.

## A five-minute walkthrough

Do this as Maria, in an org that has Opportunities, with the sample data loaded.

1. In **Nonprofit Settings**, **Giving**, set **Opportunity mirror direction** to **Gifts to
   Opportunities** and save.
2. Open **Opportunity mirror** and click **Run now**. Wait a minute, then open the
   **Reconciliation** section, choose this year, and click **Compare**. The gift count and total
   match the won Opportunity count and total, and there are no differences.
3. Enter a gift of 100 from Luis Garcia with **Quick gift entry**. Open the App Launcher,
   search for **Opportunities**, and open the newest: Amount 100, Stage Closed Won, Close Date
   today, Luis as the primary contact.
4. Change the gift's amount to 150 and save. Reload the Opportunity: its Amount is 150.
5. On the Opportunity, change the Amount to 175. Back on the page, click **Compare** again: the
   gift and its Opportunity are listed with "Amount differs". Click **Copy these gifts again**;
   when it finishes, the Opportunity is back to 150.
6. Set the direction to **Opportunities to Gifts**, set the start date to today, and save. Create
   a won Opportunity of 60 for Luis, closed today, and click **Run now**. A gift of 60 for Luis
   appears on his record, and the gift's **Opportunity ID** names that Opportunity.

## Common mistakes

**A gift has no Opportunity.** The reconciliation lists it. Most often the person who entered it
cannot create Opportunities (see Whose access the copy uses): the next run copies it. Otherwise a
rule on Opportunity refused it, such as a validation rule or a required field your organization
added. The Error Log has a Warning with the platform's message and the gifts it refused. Fix the
cause, then click **Run now**.

**The Opportunity was changed by hand.** The next time the gift changes, its values replace
yours. Edit the gift instead. Fields that are not copied, such as Description, Next Step or your
own fields, are never touched.

**A won Opportunity without a gift, in Gifts to Opportunities.** It was not made by the mirror:
it was entered directly, came from another tool, or its gift was deleted. The mirror never
deletes an Opportunity. Decide whether it should stay, and delete it yourself if not.

**A linked Opportunity was deleted, or is not visible to you.** The mirror does not make a
replacement, because it cannot tell a deleted Opportunity from one the person saving may not
see, and a replacement for one that still exists would count the gift twice. The Error Log says
so when the gift next changes. Check, as someone who sees every Opportunity, whether it exists.
If it was deleted, clear the gift's **Opportunity ID** in the **Gifts and their Opportunities**
list view and save: a new Opportunity is made.

**Linking a gift to an Opportunity you already had.** Open the **Gifts** tab and choose the
**Gifts and their Opportunities** list view, which the mirror adds. Double-click the gift's
**Opportunity ID** cell, paste the Opportunity's record ID (the 18-character code in its web
address, starting `006`), and save. Be sure it is the right one: in Gifts to Opportunities the gift's amount, date, stage,
account and campaign are written onto it at once. An Opportunity belongs to one gift only;
pasting an ID another gift holds fails the save with a duplicate value error.

**Choosing Opportunities to Gifts in an org that sells with Opportunities.** Every won
Opportunity after the start date becomes a gift, including a sale. Use this direction only when
won Opportunities in your org are donations.

**Gifts from Opportunities are thanked twice.** They are ordinary gifts, so your acknowledgment
rules apply. If your giving tool already sends the thank you, add an acknowledgment rule with
channel None for gifts of type Other (see [Acknowledgments](acknowledgments.md)).

**Turning the mirror off and expecting the copies to go.** They stay. Switching it off stops the
copying and deletes nothing.

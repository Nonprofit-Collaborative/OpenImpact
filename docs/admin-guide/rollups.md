# Rollups

## What it does

Rollups are the totals that appear on a household, a person, an organization, a fund, an
appeal, a pledge, or a scheduled payment without anyone adding them up: total giving,
first and last gift, largest gift, gift count, giving this year and the two years before
it, pledge balance, soft credit totals, what a fund and an appeal have raised, what has
been paid against a pledge, and how many people are in a household.

Open Impact calculates them for you and shows you when each one was last calculated, so
you never have to guess whether a number on a record is current. If the calculation has
not run recently, the Hub says so on the home page rather than leaving a stale number
looking fresh.

## What Open Impact calculates for you

Every total below is created for you on install, and every one of them can be edited,
switched to another mode, or made inactive. Three of the giving totals exist once for each
kind of record, because a household, an organization or person account, and a person each
reach their gifts differently. You see the household one on a household, the account one
on an organization, and the contact one on a person, so on any one record there is a
single number.

**On a household, an organization, and a person**

| Total | What it counts |
|---|---|
| Total giving | Every gift received from this donor. |
| Gift count | How many gifts this donor has given. A gift that was later refunded still counts as one gift. |
| First gift date | The date of the donor's first gift, which is what new donor reporting counts from. |
| Last gift date | The date of the donor's most recent gift, which is what lapsed donor reporting counts from. |
| Largest gift | The largest single gift this donor has given. |
| Giving this year | Given in the fiscal year you are in now. |
| Giving last year | Given in the fiscal year before it, which is the LY in LYBUNT. |
| Giving two years ago | Given the year before that, used by SYBUNT and retention reporting. |
| Pledge balance | Promised and not yet paid. |
| Total soft credits | What this donor is recognized for without being hard credited. |
| Soft credit count | How many gifts this donor is recognized on. |

**On a fund, an appeal, a pledge, and a scheduled payment**

| Record | Total | What it counts |
|---|---|---|
| Fund | Total raised | Everything ever designated to this fund. |
| Fund | Total raised this year | Designated to this fund in the fiscal year you are in now. |
| Fund | Gift count | How many gifts have been designated to this fund, counting a gift once even if it was later refunded. |
| Fund | Last gift date | The date of the most recent gift to this fund. |
| Appeal | Total raised | What this appeal brought in. |
| Appeal | Gift count | How many gifts responded to this appeal. |
| Commitment | Paid to date | What has been paid against this pledge or recurring gift. |
| Installment | Paid amount | What has been paid against this scheduled payment. |

Four things are true of all of them, and they explain most of the questions staff ask
about a number that looks wrong:

- **A pending gift is not in any total.** A promise is not money, so a gift counts only
  once its status is Received, Refunded, or Written off: the three statuses that mean the
  money actually moved. Refunded and Written off are in that list on purpose, and the next
  point says why.
- **A refunded gift stays in the count and leaves the total.** Open Impact records a
  refund as a second gift for a negative amount rather than editing or deleting the
  original, so the two cancel out. A donor who gave $250 and had all of it back shows
  **1 gift** and **$0 total giving**. That is deliberate: they did give, once, and the
  organization is holding none of it. The consequence is that dividing total giving by
  gift count is not a meaningful average gift for a donor with refunds. A gift recorded at
  $0, such as an in-kind gift with no value entered, is not counted either.
- **Soft credits are never added into a giving total.** A soft credit is recognition, not
  money the organization received, so it is counted only in Total soft credits and Soft
  credit count. If it were in Total giving as well, every household gift would be counted
  twice.
- **The year based totals use the gift date.** Which fiscal year a gift lands in is
  decided by its **Gift Date**, not by the day it was entered, so a December gift entered
  in January still counts in the right year.

## How to turn it on

Rollups are on when you install Open Impact. The packaged totals are created for you on
install and start calculating as soon as there is something to calculate. If an org has
none, or you have removed one you want back, **Restore shipped rollups** on the Rollups
page creates the ones Open Impact provides and leaves every rollup you have edited alone.

There is one thing to switch on, and the Setup Assistant does it for you: the nightly
recalculation. If you skipped that step, you can start it yourself:

1. Open the **Nonprofit Hub** app and choose the **Nonprofit Settings** tab.
2. Choose **Rollups** in the left navigation.
3. Click **Schedule nightly recalculation**. The page then shows "Nightly recalculation
   is scheduled for 2:00 AM".

Two settings on the same page change how every rollup behaves:

- **Fiscal year start month** decides where "this year", "last year", and "two years ago"
  begin. Set it to the month your fiscal year starts. Changing it and recalculating is
  all that is needed to correct every year based total in the org.
- **Default rollup mode** decides how a newly created rollup starts out: Real time,
  Scheduled, or Both.

You need the **Manage Nonprofit Settings** permission to change any of this. Without it,
the Rollups page still opens and still shows every total and its last calculated time; the
controls are simply read only.

## A five-minute walkthrough

Do this as Maria, with the sample data loaded.

1. Open the **Nonprofit Hub** app. On the home page, find the **Rollups** tile. It reads
   "Rollups last completed" with a time. If it has been more than 36 hours, the tile turns
   into a warning and offers a link to the Rollups page. Click that link, or open
   **Nonprofit Settings** and choose **Rollups**.
2. You are looking at every total Open Impact maintains, a little over thirty rows. Each
   row says what the number means in plain language, what it counts ("SUM Amount__c on
   Gift__c"), where it shows ("Account.Total_Giving__c"), its mode, and when it was last
   calculated. The names begin with the kind of record the number lands on, so
   **Household total giving**, **Account total giving**, and **Contact total giving** sit
   next to each other.
3. Find **Household total giving** and change its **Mode** from **Both** to
   **Scheduled**. The change saves as you make it and the row now says Scheduled. That
   total will now be recalculated in the nightly run rather than the moment a gift is
   saved. Change it back to **Both** when you have looked at it; Both is the setting that
   keeps the number visibly right.
4. Click **Recalculate** on that row. The page says "Recalculation started" and the row's
   last calculated time moves to a moment ago when the run finishes. **Recalculate all**
   at the top does the same for every scheduled rollup at once.
5. Open any household record. Its giving totals now match what you just recalculated, and
   the **Rollups last calculated** field on the record shows the same time. That field is
   the answer to "is this number current" for one record; the Rollups page answers it for
   the whole org.
6. Go back to the Hub home page. The Rollups tile shows the time you just recalculated.

## Common mistakes

**Typing over a total by hand.** The giving totals and the member count are calculated
fields. If you edit one on a record, the next calculation overwrites what you typed and
your change disappears without a message. If a total looks wrong, the gift records behind
it are wrong; fix those and recalculate. If you need a number the rollups do not
calculate, add your own field rather than borrowing one of these.

**Expecting a soft credit to show in total giving.** It never will. A spouse recognized on
a household gift has it in **Total soft credits**, and the person who actually gave has it
in **Total giving**. Adding the two together double counts the gift, which is why they are
two numbers and not one. Report on whichever answers your question, and say which one you
used.

**Expecting a nightly total to change immediately.** A rollup in **Scheduled** mode is
recalculated once a night, so a gift entered this afternoon does not move it until
tomorrow morning. That is what the last calculated time is there to tell you. If a total
needs to be right the moment a gift is saved, set it to **Real time** or **Both**.

**Turning a rollup off and expecting the number to clear.** Setting a rollup to inactive
stops it being recalculated; it does not erase the values already on the records. That is
deliberate, so that turning something off never destroys data. If you want the field
empty, clear it after you make the rollup inactive.

**Never starting the nightly schedule.** If nobody clicks **Schedule nightly
recalculation** and nobody finished the Setup Assistant, nothing recalculates overnight
and the Hub tile stays in warning. The tile is the only warning you get, so act on it.

**Changing the fiscal year start month and stopping there.** The year based totals are
recalculated with the new fiscal year at the next run, not the moment you save the
setting. After changing it, click **Recalculate all**, or wait for the nightly run.

## Field reference

For report builders only. Nothing on this page requires you to know these.

| What you see | Field |
|---|---|
| Rollups last calculated, on a record | `Rollups_Last_Calculated__c` |
| Last calculated, on the Rollups page | `Last_Calculated__c` on Rollup Definition |
| Member count on a household | `Member_Count__c` |
| Total giving, on an account or a contact | `Total_Giving__c` |
| Gift count, on an account or a contact | `Gift_Count__c` |
| First gift date | `First_Gift_Date__c` |
| Last gift date | `Last_Gift_Date__c` |
| Largest gift | `Largest_Gift__c` |
| Giving this year, last year, two years ago | `Giving_This_Year__c`, `Giving_Last_Year__c`, `Giving_Two_Years_Ago__c` |
| Pledge balance | `Pledge_Balance__c` |
| Total soft credits, soft credit count | `Total_Soft_Credits__c`, `Soft_Credit_Count__c` |
| Total raised, on a fund or an appeal | `Total_Raised__c` |
| Total raised this year, on a fund | `Total_Raised_This_Year__c` |
| Paid to date, on a commitment | `Paid_To_Date__c` |
| Paid amount, on a scheduled payment | `Paid_Amount__c` |

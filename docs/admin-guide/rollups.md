# Rollups

## What it does

Rollups are the totals that appear on a household, a person, or an organization without
anyone adding them up: total giving, first and last gift, largest gift, gift count,
giving this year and the two years before it, pledge balance, soft credit totals, and how
many people are in a household.

Open Impact calculates them for you and shows you when each one was last calculated, so
you never have to guess whether a number on a record is current. If the calculation has
not run recently, the Hub says so on the home page rather than leaving a stale number
looking fresh.

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
2. You are looking at every total Open Impact maintains. Each row says what the number
   means in plain language, what it counts ("SUM Amount__c on Gift__c"), where it shows
   ("Account.Total_Giving__c"), its mode, and when it was last calculated.
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

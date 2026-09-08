# Commitments: pledges and recurring gifts

**Feature:** G-07 and G-11 | **Package:** Giving | **Iteration:** v0.3

## What it does

A commitment is a promise to give. It covers a pledge, where a donor promises a fixed
total paid over time, and a recurring gift, where a donor gives the same amount on a
schedule with no end in sight. Open Impact keeps both in one place, works out the
payments that are expected and when, and shows what has been paid and what is still
outstanding.

Because the expected payments are real records, David can see what is coming up in the
next thirty days and Jen can see what is overdue, without building a report or exporting
to a spreadsheet.

## How to turn it on

Commitments come with the Giving module. When Giving is on, the Commitments and
Installments tabs are in the app and no further step is required.

Four settings control how the schedules behave. Open **Nonprofit Settings**, choose
**Giving**, and find the **Commitments** section:

| Setting | What it does | Default |
|---|---|---|
| Installment generation horizon (months) | How far ahead payments are created for a recurring gift, so an open-ended schedule does not fill the org with rows | 12 |
| Overdue grace days | How many days an unpaid payment waits after its due date before it is marked Overdue | 5 |
| Apply gifts to installments automatically | When a gift names a commitment but not a particular payment, whether Open Impact links it to the oldest unpaid payment | On |
| Installments last topped up | When the nightly job last extended recurring schedules; read only, shown so you can tell the job is running | (set by the job) |

Change a value and choose **Save**. The new value applies to the next commitment you
create or change; existing schedules are left alone until you edit them.

Two nightly jobs are scheduled for you when the Giving module is turned on: one extends
recurring schedules up to the horizon at 01:15, the other marks payments overdue at 01:45.
If you ever need to check them, the Hub shows when the top up last ran.

## A five-minute walkthrough

Start from the sample data. The first part is David's work, the last step is Jen's.

### David records a pledge

1. Open the **Commitments** tab and choose **New**.
2. Set **Type** to Pledge.
3. In **Donor**, choose a person from a household in the sample data, for example Sarah
   Nguyen. Leave the account donor field empty: a commitment has one donor, not two.
4. Set **Expected total** to 1,200 and **Amount** to 100. The amount is what is expected
   each time, not the total.
5. Set **Frequency** to Monthly and **Start date** to the first day of next month.
6. Leave **Day of month** empty. The day of the start date is used.
7. Set **Installments planned** to 12 and **End date** to the day before the first
   anniversary of the start date.
8. Choose **Save**. You will see twelve scheduled payments on the commitment, the first
   one due next month and the last one eleven months later, each for 100. The balance
   reads 1,200 because nothing has been paid yet.

### David enters the first payment

9. Open the first payment in the list and note its due date.
10. Open the **Gifts** tab, choose **New**, and enter a gift for Sarah for 100 with the
    same date. In **Commitment** choose the pledge you just made, and in **Installment**
    choose the first payment.
11. Choose **Save**, then go back to the commitment. The first payment now reads **Paid**,
    paid to date reads 100, and the balance reads 1,100.

If David had left **Installment** empty, Open Impact would have linked the gift to the
oldest unpaid payment by itself, because the automatic setting is on.

### David pauses a recurring gift

12. Open the **Commitments** tab and open one of the sample recurring gifts, or create one:
    Type Recurring, Amount 25, Frequency Monthly, a start date, no expected total and no
    end date. A recurring gift has payments generated a year ahead, not forever.
13. On the payment schedule card, choose **Pause**. The status changes to Paused, no
    further payments are generated, and the payments already scheduled stay where they
    are. The card then offers **Resume** instead of Pause: choose it when the donor starts
    giving again and the missing payments are filled back in, keeping their original dates
    and their original numbering.

The same card offers **Mark complete** for a commitment that is finished and **Cancel
commitment** for one the donor has stopped. Cancelling marks the unpaid payments Skipped
and deletes nothing.

### Jen checks what is overdue

14. Open the **Installments** tab and choose the **Overdue** list view. Every unpaid
    payment whose due date passed more than the grace period ago is here, with its
    commitment, its donor, and what was expected.
15. Switch to **Upcoming 30 days** to see what should arrive next, which is the list Jen
    uses when she reconciles the bank statement.

## Common mistakes

**Entering the total in the amount field.** Amount is what is expected each time. A
1,200 pledge paid monthly has an amount of 100 and an expected total of 1,200. If the
schedule comes out with twelve payments of 1,200, this is what happened: correct the
amount and save, and the unpaid payments are rebuilt.

**Naming two donors.** A commitment is from one donor: a person or an account, never
both. Saving with both filled in stops with "Choose one donor for this commitment, either
a person or an account, not both."

**Giving a recurring gift an expected total.** A recurring gift is open ended, so it has
no total and no fixed number of payments. If the donor has promised a fixed total, it is
a pledge. Saving a recurring commitment with a total stops with "A recurring commitment
has no expected total. Choose Pledge if the donor promised a fixed amount."

**Deleting a commitment that has been paid.** Once a gift has been received against a
payment, the commitment and that payment are part of the giving history and cannot be
deleted. Cancel the commitment instead: the unpaid future payments are marked Skipped and
nothing already received is touched.

**Editing the amount partway through.** Changing the amount, the frequency, the day of
month, or the end date rebuilds the payments that are still unpaid and leaves every paid
or partly paid one alone. The balance changes as a result, which is what you want, but it
does mean the schedule after the change no longer matches the pledge letter the donor
signed. Note the reason on the commitment's Chatter feed before you save, so the next
person to look at it knows why the numbers moved.

## Field reference for report builders

Everything above is on two objects: Commitment and Installment. The list views named here
are shipped and can be copied.

| What Maria calls it | Where it lives |
|---|---|
| Paid to date | Commitment, Paid To Date |
| Balance | Commitment, Balance |
| Expected payment | Installment, Expected Amount |
| Paid so far on this payment | Installment, Paid Amount |
| Pledge balance for a donor | Account or Contact, Pledge Balance |

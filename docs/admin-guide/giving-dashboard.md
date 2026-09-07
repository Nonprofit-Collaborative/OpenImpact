# Giving Dashboard

## What it does

The Giving dashboard answers the four questions a board asks, without anybody building a
report: how much came in this month, which funds it went to, which appeals produced it,
and who the largest donors are this year. It arrives with the Giving package as a set of
reports and one dashboard, already filtered to the current month and the current year, so
Tom can open it the day after installation and read real numbers.

The reports underneath it are ordinary Salesforce reports in a shared folder. Anyone can
open one, change a filter, and save a copy of their own without affecting what everyone
else sees.

## How to turn it on

1. Open the **Fundraising** app from the app launcher. Tap **Dashboards**, open the
   **Open Impact Giving** folder, and open **Giving Overview**.
2. Set who the dashboard reads as. Open the dashboard, choose **Edit**, and in **View
   dashboard as** choose **The dashboard viewer**. Save. Every person then sees the gifts
   they are allowed to see. If your edition does not offer "The dashboard viewer", choose
   a person who can see all gifts, usually the person who installed the package.
   **Do this once, on the day you install.** A dashboard that arrives in a package has no
   running user of its own, and until one is set the dashboard shows an error instead of
   numbers.
3. Give people access to the folder. In Nonprofit Settings, open **Access** and assign the
   **Fundraising Staff** permission set group, which includes read access to the Open
   Impact Giving reports and dashboards. Tom needs no more than that.
4. Optional, and worth the ten seconds: with the dashboard open, choose **Subscribe** and
   have it emailed to yourself on the first of the month.

Nothing here requires Salesforce Setup.

## A five-minute walkthrough

Do this as Tom, from the sample data, after at least a few gifts exist.

1. Open the app launcher and choose **Fundraising**. Choose **Dashboards**, then the
   **Open Impact Giving** folder, then **Giving Overview**.
2. Read the top left number: **Gifts this month**. It is the total of every gift received
   since the first of this month. Under it, the daily chart shows which days produced it,
   which is how you tell one large gift from a steady week.
3. Read **Giving by month**. Twelve bars, this month at the right, the same twelve months
   again next month with no editing. This is the chart to take to a board meeting.
4. Read **Giving by fund, this year**. Each bar is one fund. A restricted fund with a
   large balance is money you may not spend on operations, so this chart is the one to
   check before a cash flow conversation.
5. Read **Giving by appeal, this year**. Each bar is one appeal, so you can see whether
   the spring mailing outperformed the gala.
6. Read **Top donors, this year**. Households, largest first, with the amount each has
   given since January. Click any row to open the report and see the gifts behind the
   number.
7. Choose **Refresh** in the top right corner. The date and time under the dashboard name
   tell you how current the numbers are; everything on this dashboard is calculated from
   the gifts themselves, so a refresh is all it ever needs.
8. Open **Recent gifts** from the Reports tab, in the same folder, when someone asks
   "did that gift arrive?". It lists every gift from the last thirty days, newest first.

## Common mistakes

**The dashboard shows an error instead of numbers.** The message is "The running user for
this dashboard doesn't have permission to run reports." A dashboard that arrives inside a
package does not carry a running user with it. Fix it once: open the dashboard, choose
Edit, set **View dashboard as** to **The dashboard viewer**, and save. See step 2 above.

**The numbers look too small.** Only gifts with the status **Received** count. A gift left
at Pending, for example a pledge payment that has not arrived, is deliberately excluded so
that the totals match the bank. Open Recent gifts and look at the status column if a gift
you expected is missing.

**A fund total looks short.** A gift counts toward a fund only through its allocation. If
your organization has no default fund chosen in Nonprofit Settings, gifts entered without
a fund have no allocation and appear in the monthly totals but not in the fund chart. Set
the default fund, then edit the affected gifts to allocate them.

**Someone changes the shared report.** The reports live in a shared folder and a person
with edit access can save over them. Ask staff to use **Save As** and keep their copies in
their own folder. If a packaged report is changed by mistake, an upgrade of the Giving
package does not restore it, so keep the edits in copies from the start.

**Top donors looks like it is missing your largest supporter.** Top donors groups by
household, which is how individual donors are counted whether people are contacts or
person accounts in your org. A gift from a company or a foundation belongs to no
household, so it is not on this chart. Use Giving by fund and Giving by appeal, or open
the report and group by donor account, for organization giving.

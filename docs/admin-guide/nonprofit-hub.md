# Nonprofit Hub

## What it does

The Nonprofit Hub is the app you work in every day. It gives you one home page that tells
you what to do next, a setup checklist that remembers how far you got, and a short list of
the places you go most: your households, your people, your organizations, and your
settings.

If you have ever installed something in Salesforce and then wondered where to start, this
is the answer to that question. You start here.

## How to turn it on

There is nothing to turn on. The Hub is installed with Open Impact Core.

1. Click the app launcher (the grid of dots at the top left of Salesforce).
2. Type `Nonprofit` and choose **Nonprofit Hub**.
3. Click the star next to the app name if you want it to open by default.

Everyone who has been given an Open Impact role can open the Hub. Two things on the home
page are for administrators only:

- The **Errors to review** tile counts only errors you are allowed to see, and the Error
  Log tab itself is on the administrator role.
- The **Setup checklist** can be read by anyone, but only a person with the **Manage
  Nonprofit Settings** permission can mark a step done or change a setting.

## A five-minute walkthrough

Maria has just installed Open Impact and has the sample data loaded.

1. Open the app launcher, type `Nonprofit`, and choose **Nonprofit Hub**. The home page
   opens with the heading **Welcome to Open Impact**.
2. Read the **Setup checklist**. There are eight steps, each with one sentence saying what
   it is for. Steps you have already finished show a **Done** badge, and the rest show
   **To do**. The checklist tells you how many are done, for example "3 of 8 steps done".
3. Find the first step, **Confirm how Open Impact fits your existing org**, and click
   **Open**. The Nonprofit Settings page opens at the section that step belongs to. Come
   back to the Hub with your browser's back button.
4. Back on the home page, click **Mark done** on a step you have finished. The badge
   changes to **Done** and the count at the top goes up. Nothing else happens: marking a
   step is a note to yourself, not a switch.
5. Look at the **Errors to review** tile. On a fresh org it says `0`. If it ever shows a
   number, click **Open the Error Log** and read the plain-language message on each row.
6. If someone has paused automation (for example during a large import), a banner sits
   above the checklist saying Open Impact automation is paused. It disappears by itself
   when the pause expires.
7. Use **Quick links** to open Households, Organizations, or Nonprofit Settings without
   going back to the app launcher.

That is the whole home page. Five minutes, and you know what is done, what is next, and
whether anything went wrong.

## Common mistakes

- **Looking for the app in Setup.** The Hub is an app, not a Setup page. Use the app
  launcher, not the gear icon. If `Nonprofit Hub` does not appear in the app launcher, you
  have not been assigned an Open Impact role: ask whoever installed the package to add you
  on the Access page.
- **Expecting Mark done to configure something.** The checklist records your progress. It
  does not change any setting on its own. Use **Open** on the step to make the actual
  change, then come back and mark it done.
- **Reading the checklist as a one-time task.** The checklist stays on the home page after
  you finish it, and you can un-mark a step at any time. Re-run any step whenever your
  organization changes: a new fiscal year, a new staff member, a new bank account for
  receipts.
- **Assuming an empty Errors tile means nothing failed.** The tile counts errors with the
  status **New**. If someone has already marked an error Acknowledged or Resolved, it
  stops counting. Open the Error Log tab to see everything.

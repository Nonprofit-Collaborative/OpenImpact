# Automation control

## What it does

Open Impact does small pieces of work for you in the background: it creates a household
for a new person, keeps household names and greetings up to date, and so on. Automation
control is the page where you can see every one of those pieces of work, read what it
does, and switch it off if it is getting in your way.

It also gives you one big switch: pause everything for a couple of hours while you load a
spreadsheet, then let it turn itself back on. You never have to call anyone to get
unstuck.

## What you will see in v0.1

This page describes the finished feature. Two parts of it arrive with the next pieces of
v0.1, and until they do the walkthrough below cannot be completed end to end:

- The Nonprofit Hub app, its home page, and the Nonprofit Settings console are built by
  feature C-03. Until then there is no page to put automation control on.
- The list of automations is empty, because the first automations (creating households,
  naming them) arrive with feature C-01. Until then the page says so rather than listing
  anything, and the pause button works on nothing.

The pause itself, the switches, the banner and the audit trail are all built and tested.

## How to turn it on

Automation control is on as soon as Open Impact is installed. There is nothing to enable
and nothing to install.

You will find it in two places:

- **Nonprofit Settings, then Automation.** This is the full page: the list of every
  automation with its on and off switch, and the pause button.
- **The Nonprofit Hub home page.** While automation is paused, a banner appears at the top
  of the home page telling you what is paused and when it will come back on.

Changing anything on this page requires the Manage Nonprofit Settings permission, which
comes with the Nonprofit Admin role. If you do not have it, the page still opens and you
can read everything, but the switches are greyed out and a message names the permission
you need to ask for.

## A five-minute walkthrough

Maria is about to load a spreadsheet of 400 people from a partner organization. She wants
the records in first and the automatic housekeeping to happen afterwards, so nothing runs
400 times while she is watching.

1. Open the **Nonprofit Hub** app and click **Nonprofit Settings**.
2. In the left navigation, click **Automation**. You see a list of every piece of
   automation Open Impact ships, each with a plain-language description and a switch.
3. At the top of the page, choose **2 hours** in the **How long** list, then click
   **Pause all automation**. The page now shows a yellow bar: "Automation is paused until
   3:40 PM." Every switch in the list is still where you left it: pausing does not change
   anything you have chosen.
4. Click **Home**. The same banner appears at the top of the Hub, so anyone else working
   today can see why records are not updating themselves.
5. Load your spreadsheet. Nothing runs automatically while you do.
6. Come back to **Nonprofit Settings**, then **Automation**, and click **Resume
   automation**. The banner disappears and the automation starts running again on the next
   record anyone saves. If you forget this step, nothing breaks: automation turns itself
   back on at the two hour mark.
7. Now switch off a single automation instead. Find **Household naming** in the list and
   click its switch to **Off**. Only that one stops running. Everything else carries on.
   (In v0.1 the list is empty until feature C-01 adds the first automations, so there is
   nothing to switch yet.)
8. Switch it back **On**. Every change you make here is recorded with your name, the time,
   and what the value was before, so you can always see who changed what.

That is the whole feature: one switch per automation, one switch for all of them, and it
expires by itself.

## Common mistakes

- **Pausing and forgetting, then wondering why names are wrong.** While automation is
  paused, new people do not get households and names are not recomputed. The records are
  fine, they are just not finished. Resume automation and then re-save the records, or run
  the recompute action on the Households page.
- **Expecting pause to undo work already done.** Pause stops future automation. It does
  not roll back anything that already ran. If something ran that you did not want, fix the
  records themselves.
- **Switching an automation off to stop an error, and never switching it back on.** An
  automation that is off is a piece of your setup that has quietly stopped working. Look at
  the Error Log first: it usually tells you what to fix in the data, and then you can leave
  the automation on. See the [Error Log page](error-log.md).
- **Assuming a pause covers other people's work.** The pause is for the whole organization,
  not for you alone. Anyone saving a record during the pause gets the same behavior, so say
  something in your team channel before you pause during working hours.
- **Looking for the switches with the wrong role.** If the switches are greyed out, you are
  signed in as a user without the Manage Nonprofit Settings permission. Ask whoever
  administers your Salesforce to give you the Nonprofit Admin role.

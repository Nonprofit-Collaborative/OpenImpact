# Error Log

## What it does

When something goes wrong inside Open Impact, it writes down what happened in plain
language and puts it somewhere you can read it. That is the Error Log. Instead of a
technical failure disappearing into a log file only a developer can open, you get a list
of entries that say what went wrong, which record it happened on, and what to do about it.

You can work through the list, mark the ones you have looked at, and mark the ones you
have fixed, so the list stays short and honest.

## What you will see in v0.1

This page describes the finished feature. The Nonprofit Hub app and its home page, where
the tile lives, are built by feature C-03. Until then the Error Log tab is the way in, and
the tile can be placed on any Lightning page. Everything else on this page works today.

## How to turn it on

The Error Log is on as soon as Open Impact is installed. Nothing is recorded unless
something actually fails, so on a healthy organization the list is empty.

You will find it in two places:

- **The Nonprofit Hub home page.** A tile shows how many new errors are waiting and the
  five most recent, with the message and where it came from. Click any of them to open it,
  or click the tile heading to see the whole list.
- **The Error Log tab** in the Nonprofit Hub app. This is the full list, and you can sort
  it, filter it, and build reports on it like any other list in Salesforce.

Everyone with the Nonprofit Staff or Nonprofit Admin role can read the Error Log. Only the
Nonprofit Admin role can change an entry's status.

Errors are recorded whatever else is happening: turning an automation off, or pausing all
automation, never stops the Error Log from recording a problem.

## A five-minute walkthrough

Maria has heard from a colleague that "something did not save this morning."

1. Open the **Nonprofit Hub** app. On the home page, look at the **Error Log** tile. It
   says how many new errors there are, for example "3 new".
2. Read the five most recent entries in the tile. Each line shows the message and where it
   came from, for example "Household naming".
3. Click the entry your colleague described. The record opens.
4. Read the **Message**. It is written for you, not for a developer: it says what went
   wrong and what to do about it, for example "This household could not be renamed because
   every member is marked deceased. Add a living member, or set a custom name on the
   household."
5. Do what it says on the record it names. The **Record reference** on the entry is the
   record involved, so you can open it and fix the data.
6. Come back to the Error Log entry and set **Status** to **Resolved**, then save. It
   drops out of the "New" count on the home page tile.
7. If you cannot fix an entry yourself, set **Status** to **Acknowledged** instead, so
   your colleagues know someone has seen it, and send the **Technical detail** to whoever
   supports your Salesforce. That section is the part written for a developer.
8. Go back to the home page. The tile count has gone down by one.

## Common mistakes

- **Treating the Error Log as a to-do list that someone else owns.** Nobody is emailed
  about these yet (a daily summary email arrives in a later release). If you do not look at
  the tile, nobody looks at it.
- **Deleting entries to clear the list.** Use the status instead. Marking something
  Resolved keeps the history, which is what you want the next time the same thing happens,
  and it keeps the tile count accurate either way.
- **Reading the technical detail first.** The message at the top is the one written for
  you. The technical detail underneath is for a support request, and it will not tell you
  anything about your data that the message does not already say.
- **Expecting an entry for a mistake you made in a spreadsheet.** The Error Log records
  failures inside Open Impact, not every data problem. A person imported with the wrong
  address is a data question, not an error, and it will not appear here.
- **Assuming an empty list means nothing has failed.** If automation is paused, the work
  that would have failed is not running at all. Check the automation banner on the home
  page as well. See the [Automation control page](automation-control.md).

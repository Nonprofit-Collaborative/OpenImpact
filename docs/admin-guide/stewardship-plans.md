# Stewardship plans

## What it does

A stewardship plan is a sequence of follow-up work your organization repeats. Somebody gives
for the first time, and three things should happen: a thank-you call this week, a welcome
packet next week, a check-in call in a month. A plan writes that sequence down once, and
then lays the tasks out for you every time it applies.

Open Impact can start a plan by itself when a gift arrives, or a person can start one by
hand on a donor. Either way, the plan creates ordinary Salesforce tasks, assigned to real
people, with real due dates. Your team works them in the same list they already use.

Three things to hold on to, because they are the questions people ask first:

- **A plan is laid out once, when it starts.** Editing a template later does not reach back
  into plans already running. The tasks are in somebody's list and they have planned their
  week around them.
- **Open Impact never deletes a task it created.** Cancelling a plan marks the plan
  cancelled and leaves the tasks alone, because a task is a record of somebody's work.
  Closing the leftovers is theirs to do.
- **You close a plan yourself.** Open Impact does not mark a plan complete when its last
  task closes. See "What this does not do yet" at the end.

## How to set one up

Everything is in the app. You never open Setup.

1. Open the **Stewardship Plan Templates** tab and choose **New**.
2. Give the plan:
   - a **plan name**, the one your team will recognize, for example "First gift welcome";
   - a **plan key**, a short unchanging code such as `first_gift_welcome`. You will not
     see it again. It is how Open Impact recognizes the plan across upgrades even if you
     rename it;
   - a **trigger event**, which is what starts it:
     - **Manual**: nothing starts it automatically. Somebody starts it on a donor.
     - **First gift**: starts when a donor's first gift arrives.
     - **Gift received**: starts on any gift.
     - **Commitment started**: reserved for a later release, see below.
   - a **minimum amount**, optional, and only for the two gift events. Set it to 1000 and
     the plan waits for a gift of a thousand or more. Leave it empty for any gift;
   - a **description**, optional, which is what somebody reads when picking a plan to start
     by hand.
3. Leave **Active** off until the steps are in. An inactive plan starts nothing.
4. On the saved template, add a **step** for each task, with:
   - an **order**, which is the order the steps are listed in;
   - a **subject**, which is the line the assignee sees in their task list. Write it as an
     instruction: "Call to say thank you", not "Thank you";
   - **days after start**, which is how many days after the plan starts the task is due.
     Zero means the day it starts;
   - **assign to**: **Record owner** gives the task to whoever owns the donor record,
     **Plan starter** gives it to whoever started the plan, and **Specific user** gives it
     to one named person every time;
   - a **priority**;
   - **comments**, optional, which become the task's description.
5. Turn **Active** on when the steps are right.

## A five-minute walkthrough

1. Create a template called "First gift welcome", key `first_gift_welcome`, trigger event
   **First gift**, no minimum amount. Leave Active off.
2. Add three steps:
   - order 1, "Call to say thank you", 1 day after start, Record owner, High;
   - order 2, "Send the welcome packet", 7 days after start, Record owner, Normal;
   - order 3, "Check in and ask what drew them to us", 30 days after start, Record owner,
     Normal.
3. Turn the template **Active** on.
4. Record a gift for a donor who has never given before.
5. Open that donor. Under **Stewardship Plans** you will see one running plan, and three
   tasks now sit in the record owner's list, due tomorrow, next week, and next month.

## Common mistakes

- **Steps added after the plan started.** They do not appear on plans already running.
  Add the step, and the next plan to start gets it.
- **A minimum amount on a manual plan.** Open Impact refuses this at save. A minimum only
  means something for the two gift events, and left on a manual plan it reads like a
  condition that is quietly never applied.
- **Assign To set to Specific user with nobody named.** Refused at save, for the same
  reason. If the named person later becomes inactive, the task goes to whoever started the
  plan rather than to nobody.
- **Expecting the same plan to run twice on one donor.** It will not, while the first one
  is still running. Mark the running one complete or cancelled first. This is what stops a
  donor getting the same three tasks every time they give.
- **Expecting a bulk import to start hundreds of plans.** Switch stewardship off before a
  bulk load, on the **Automation** page in Nonprofit Settings, and the gifts load quietly.
  Switching it back on does not catch up the gifts it missed: a welcome for a gift from
  three weeks ago is not a welcome.

## What this does not do yet

- **Open Impact does not close a plan for you.** When the last task on a plan closes, the
  plan stays Running until somebody marks it Complete. Closing it automatically would need
  Open Impact to put automation on the Task object, which it does not ship. Use the
  **Running Plans** list view to see what is still open.
- **The Commitment started event is not wired up.** The value is on the picklist and a
  template can be saved with it, but no plan starts from it in this release. Gift events
  work today.
- **There is no page in Nonprofit Settings yet.** Templates and steps are managed on their
  own tabs, which is why this guide sends you there rather than to the console.

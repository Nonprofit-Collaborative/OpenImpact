# Households

**Feature:** C-01 Household model
**Package:** Core
**Iteration:** v0.1

## What it does

A household is the group of people you treat as one donor: one mailing, one thank you
letter, one giving history. Open Impact creates a household for every new person you add,
in either way of belonging to a household and whichever record your org stores people on,
keeps track of who belongs to it, and keeps the member count right when people join, move,
or leave.

You never have to create a household by hand, and you never have to remember to fix a
count after a change.

## How to turn it on

Households work as soon as Core is installed. Everything you can change is on the
Nonprofit Settings page, so nobody needs to open Salesforce Setup.

1. Open the **Nonprofit Hub** app and click the **Nonprofit Settings** tab.
2. Click **Households** in the left navigation.
3. Check the three settings and change any that do not match how you work.

| Setting | What it does | Ships as |
|---|---|---|
| How people belong to a household | The simple way (one household per person) or the flexible way (a person can belong to more than one household, and you keep the history of who belonged when) | The simple way |
| Create a household automatically | When you save a new person with no household, one is created for them. This works the same way in both ways of belonging, and for people stored as contacts and for people stored as accounts | On |
| Delete a household when the last person leaves | Keeps your list of households clean | On |

4. Click **Save**. The change applies to the next record anyone saves.

Choose the flexible way if you need one person in two households: a child of divorced
parents, or a student with a family address and a campus address. The rest of the product
behaves the same either way, so it is safe to start simple and change your mind later.

## A five-minute walkthrough

Maria does this from the sample data.

1. Open the **Nonprofit Hub** app and click the **Contacts** tab.
2. Click **New**, choose the **Household Contact** record type, and enter the first name
   `Maria` and the last name `Garcia`. Leave the household blank. Click **Save**.
3. Look at the household field on the new person. It is filled in, and the household is
   called **The Garcia Family**. Maria did not create it.
4. Click through to the household. The **Members** panel lists Maria, and the member count
   reads 1.
5. On the Members panel, click **Add member** and enter the first name `Wei` and the last
   name `Lee`. Click **Save**.
6. Refresh the household. The name now reads **Garcia and Lee Household** and the member
   count reads 2.
7. Open Wei's record, check **Deceased**, and save. Return to the household: the greetings
   no longer mention Wei.
8. Back on the Members panel, use **Move to another household** on Maria and move her to
   any other household. Return to the first household: it is gone, because it had no
   members left and "delete a household when the last person leaves" is on.

That is the whole lifecycle: created for you, named for you, counted for you, and tidied
up for you.

<<<<<<< HEAD
One thing the tidy-up will not do: it never deletes a household that something outside
Open Impact still points at, even when the setting is on and nobody is left in it. It
leaves that household alone and writes an Info entry in the Error Log naming it, so you
can look at it and decide for yourself.
=======
The walkthrough reads the same in the flexible way of belonging, with one difference at
step 3: the household is not shown in the household field on the person, because in that
mode membership is a record of its own. Open the household from the **Households** tab, or
from the Members panel on the person, and everything from step 4 on is identical.
>>>>>>> fix/c-01-junction-mode-auto-create

## If your org stores people as accounts

Some orgs, including most Nonprofit Cloud and Agentforce Nonprofit orgs, store each person
as an account rather than as a contact. Households work there too, with one difference:
choose the flexible way of belonging to a household. It is the only mode that can hold a
person who is stored as an account, and Open Impact selects it for you when it notices your
org is shaped that way.

Automatic creation is the same setting and the same behavior as anywhere else. When "create
a household automatically" is on, saving a new person creates their household and the
membership record that joins them to it, whether that person is a contact or an account.
There used to be a second setting here, "create households for people stored as accounts",
and it has been removed: it shipped off, so an org that took the recommended setup got no
households at all and was told nothing about it. One setting now answers the question for
everybody.

If you are one of the orgs that groups people another way and does not want a household
appearing for each person, turn "create a household automatically" off. Health Check will
tell you the state you are in, so it is a choice rather than a surprise.

Everything else reads the same: the same member counts, the same names and greetings, and
the same Members panel. A household is still its own record, never a person.

## Common mistakes

**"I added a person and no household appeared."**
Either "create a household automatically" is off, or the person already belongs to a
household: you filled the household in yourself when you created them, or a membership
record already joins them to one. Turn the setting back on in Nonprofit Settings, then open
the person and pick or create a household. Health Check reports the setting being off as a
red finding, with a button that turns it on.

**"I deleted the last person and the household is still there."**
Either "Delete a household when the last person leaves" is off, or Open Impact deliberately
left that one alone.

If the setting is off, that is a reasonable choice if you want to keep an empty household
and its giving history. Delete the household by hand, and turn the setting on if you want
it done for you next time.

If the setting is on, look in the Error Log. Open Impact never deletes a household that
something outside Open Impact still points at, because deleting it would delete those
records too, and it writes an Info entry naming each household it left in place for that
reason. This happens most often in orgs that also run Salesforce Nonprofit Cloud, where a
household is a second record attached to the same account and its members are held
somewhere Open Impact cannot count them: the household looks empty here and is not empty
there. Open the household, check what else is using it, and delete it by hand if you are
sure.

**"The member count looks wrong."**
The count includes current members only. In the flexible membership mode, a person whose
membership has an end date of today or earlier has left the household and is not counted.
The Members panel lists current members only and shows no dates, so somebody who has left
is simply absent from it.

**"The primary contact went blank when I moved someone out."**
That is deliberate. The primary contact has to be somebody who is still in the household,
so when that person leaves, Open Impact clears the field rather than leaving a name that no
longer belongs there. It does not choose a replacement for you: pick the new primary
contact yourself on the household record.

**"I moved someone and their gifts stayed behind."**
That is deliberate. Moving a person moves the person, not the giving history of the
household they left. Use merge on the household record page when you want to combine two
households and their history.

## Field reference

For report builders only. Maria never needs this to use the feature.

| Where | Field label | Purpose |
|---|---|---|
| Household | Member Count | Current members of this household |
| Household | Primary Contact | The person named when only one person can be. Cleared when that person leaves the household |
| Household | Anniversary | A household date you steward, most often a wedding anniversary |
| Person | Household Role | Head, Spouse or Partner, Child, or Other |
| Household Member | Start Date and End Date | When the person joined and left (flexible mode only) |

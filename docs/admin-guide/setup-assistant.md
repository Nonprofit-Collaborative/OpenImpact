# Setup Assistant

## What it does

The Setup Assistant is the guided path from "I just installed BarnCRM" to "we are
working with real records", in under thirty minutes, without opening Salesforce Setup and
without reading anything else. It asks its questions one screen at a time, in the order that
makes each answer easy, and it remembers where you got to. Close the browser in the middle
of step four and come back tomorrow: the assistant opens on step four.

The first question is which suite you are setting up. BarnCRM comes as two suites built from
the same app:

- **Nonprofit Suite**: for nonprofits. BarnCRM Core with the Giving module for gifts,
  donors and receipts, and the nonprofit modules (Programs, Logic Models, Volunteers,
  Funders and Connect) to add when you need them.
- **Community Suite**: for any other organization, such as a business, a club or a
  community group. BarnCRM Core for people, households and organizations, with the modules
  that fit any organization (Volunteers today, Events later).

How many steps you see depends on what is installed. BarnCRM Core on its own asks seven
questions. When the **Giving** module is installed as well, Giving adds its own: a step for
the default fund and appeal, the receipt details on the identity step, and a first gift to
check everything with, which makes eight steps. This page numbers the steps as they appear
with Giving installed and marks what comes from Giving. Without Giving, the steps after step
three move up by one.

Nothing it asks is permanent. Every answer is a setting you can change later on the
BarnCRM Settings page, and you can re-run the whole assistant whenever your organization
changes.

## How to turn it on

There is nothing to turn on. The Setup Assistant is the BarnCRM home page until you
finish it.

1. Click the app launcher (the grid of dots at the top left of Salesforce).
2. Type `BarnCRM` and choose **BarnCRM**.
3. The home page opens on the assistant, at the first step you have not finished.

When every step is done, the assistant collapses to a small **Setup complete** tile that
shows how many steps you finished. The tile has a **Reopen setup** button, so the assistant
is always one click away, and it opens straight back on the first step rather than on the
completion screen.

You need the **Manage BarnCRM Settings** permission to change anything in the assistant.
Everyone else sees the same steps, reads the same explanations, and cannot save. If you can
read but not save, the assistant says so at the top and names the permission you are
missing. Ask whoever installed BarnCRM to add you to the **BarnCRM Admin** role on
the Access page.

Two things sit outside the assistant, because Salesforce does not let an app do them:

- **Creating a Salesforce user** who has never signed in. Step five links you to the Setup
  page that does it, then you come back and give the new person a role.
- **Installing another BarnCRM module.** Step one lists the modules your suite offers,
  says which are installed, and tells you how to get the rest.

## A five-minute walkthrough, and then the eight steps

Maria has just installed BarnCRM Core and the Giving module in her organization's
Nonprofit Cloud org. That org has Person Accounts turned on, which matters in step two and
nowhere else. She has half an hour before her next meeting.

### Before you start

Have these to hand. Every one of them is optional, and every one of them is faster to have
ready than to go and find:

- Your organization's legal name as it appears on your official filings.
- Your mailing address as you want it printed.
- With Giving: your tax identification number (in the United States, your EIN).
- With Giving: your logo, as a PNG or JPG file.
- With Giving: a scan of the signature that goes on receipt letters, if you use one.

### Step 1: Choose your suite

Choose **Nonprofit Suite** or **Community Suite**. Each has one line saying who it is for.
The assistant has already chosen one for you: the Nonprofit Suite when the Giving module is
installed, the Community Suite when it is not. Change it if that is wrong, then click
**Choose and continue**.

Under the choice is the list of modules that suite offers, in order, each marked
**Installed** or **Not installed**:

| Suite | Modules listed |
|---|---|
| Nonprofit Suite | Giving (required for the suite), then Programs, Logic Models, Volunteers, Funders and Connect (optional) |
| Community Suite | Volunteers (optional); Events joins the list when it is released |

The Community Suite never lists a module that is only for nonprofits. Choose a different
suite and the list changes at once, before you save anything.

A module that is not installed says how to get it. Each module is a separate package, and no
app can install another package for you, so getting one means opening its installer and
following the Salesforce install screens. BarnCRM has no published package versions yet, so
for now the row says so in one sentence and its **Learn more** link opens this guide. When a
module's package is published, an **Install** link appears in the same place with no change
to your org.

What the choice changes, and what it does not:

- It decides which modules this step lists and offers. That is all it changes today.
- It never installs, removes, hides or switches off anything. A module you already have
  keeps working whichever suite you choose.
- **Nonprofit Suite without Giving installed.** The step says plainly that the Nonprofit
  Suite needs the Giving module, and setup carries on with the steps every organization
  answers. Install Giving when you are ready: its steps (the fund and appeal, the receipt
  details and the first gift) appear the next time you open the home page.
- **Community Suite with Giving installed.** Giving's steps and settings stay exactly where
  they are. The Community Suite's list simply leaves the nonprofit modules out, installed
  or not.

The step finishes once a suite is saved. Your choice is the **Suite** setting in the
General section of BarnCRM Settings, where you can change it later.

If you finished setup before the suite question existed, your setup stays finished and
nothing about your org changes: this step takes the place of the module list that was step
six, which you already marked done. Reopen setup, or open BarnCRM Settings, whenever you want
to record your suite.

**What Maria sees:** Nonprofit Suite already selected, because she installed Giving, and
the list: Giving installed, the other five not installed, each with a sentence and a link.
She clicks **Choose and continue**.

**What she decides:** which kind of organization she is setting up. For Maria, a
nonprofit.

### Step 2: Confirm how BarnCRM fits your org

BarnCRM looks at your org and tells you what it found, in plain words:

- **"Your org uses Person Accounts, as Nonprofit Cloud orgs do."** This is Maria's case.
  BarnCRM recommends **Agentforce Nonprofit coexistence**: households are tracked with
  a membership record for each person, so a person can belong to more than one household
  and nothing you already have is disturbed. Your existing records keep working exactly as
  they do today. Confirming this mode switches household membership to those membership
  records, and from then on saving a new person creates their household and their
  membership of it, exactly as it does in the simple mode. The switch that governs that is
  "create a household automatically" on the Households page of BarnCRM Settings.
- **"NPSP is installed in this org."** BarnCRM recommends **NPSP coexistence**, which
  records that NPSP is here. In this version it changes no behaviour: BarnCRM builds its
  own households and leaves NPSP's alone.
- **"This looks like a fresh org."** BarnCRM recommends **Standalone**, the simplest
  arrangement.

Read the recommendation, then click **Confirm and continue**. If you know something the
detection cannot see, choose a different mode from the list first and then confirm.

**What Maria sees:** the sentence about Person Accounts, the recommended mode already
selected, and one button. She clicks it. Two seconds.

**What she decides:** nothing, unless she disagrees with the detection.

### Step 3: Confirm how households are named

The assistant opens the household naming settings inside the step, with the live preview.
Choose the pattern for the household name, the formal greeting, and the informal greeting,
and watch five sample households, which ship with the product, change as you type.

Click **Save**, and the step completes itself. If your org does not have the household
naming screen yet, the step says so and tells you that BarnCRM will name households
with the pattern it ships until you change it.

**What Maria sees:** `The Smith Family`, `Mr. and Mrs. John Smith`, `John and Jane`. She
tries `Smith Household` in the name box, sees it in the preview, decides she prefers the
default, and puts it back.

**What she decides:** whether her households are a Family or a Household. That is genuinely
the whole decision.

### Step 4: Pick your default fund and appeal (Giving)

This step comes with the **Giving** module, which is a separate package. Without Giving the
step is not there at all, and the assistant goes straight from naming to access.

You get two pickers: the fund a gift belongs to when nobody says otherwise (usually your
general operating fund) and the appeal it is credited to (usually a general or unsolicited
appeal). Choose them and click **Save**. The pickers only offer real funds and appeals, and
anything else is refused, so a default can never point at the wrong kind of record. If you
install Giving after finishing setup, this step appears as **To do** the next time you open
the home page.

**What Maria sees:** her General Fund and her Unsolicited appeal in the pickers. She picks
both and clicks **Save**.

**What she decides:** where a gift goes when nobody says.

### Step 5: Give your colleagues access

Pick one person, pick a role, and click **Give access**. The step confirms with "Access
given. Add another person, or continue.", and the person box clears so you can do the next
one. Give access to as many colleagues as you like, one at a time. The roles are:

| Role | Who it is for |
|---|---|
| BarnCRM Admin | Maria: everything, including settings |
| Fundraising Staff (comes with Giving) | David: gifts, donors, receipts |
| Program Staff | Priya: participants and services |
| Volunteer Coordinator | Volunteer jobs, shifts, and hours |
| Read Only | Tom and Jen: see everything, change nothing |

The person has to exist as a Salesforce user first. If someone is missing from the list,
click **Create a user in Setup**, create them there, come back, and refresh the step.

**What Maria sees:** her four colleagues in the picker. She gives David the Fundraising
Staff role and Tom the Read Only role. The step marks itself done.

**What she decides:** who gets to change settings. Give that to as few people as the work
allows: settings change how the whole org behaves.

### Step 6: Set your organization's identity

This is the form the "before you start" list was for. Core asks for two things:

- **Legal name**, exactly as on your official filings, not your nickname.
- **Address**, on one line, as you want it printed.

With the Giving module installed, the same form also asks for what your receipts print:

- **Tax identification number** (EIN in the United States).
- **Logo**: click **Upload logo** and choose the file. The logo appears under the button
  once it has uploaded, so you can see what your receipts will carry.
- **Signature image**: the same, for the scanned signature on receipt letters.
- **Signer name and title**, for example `Ana Ruiz` and `Executive Director`.

Click **Save**. The step completes when the legal name is filled in, because that is the
one a receipt or letter cannot be printed without.

Two things to know about the uploaded files. They are stored as Salesforce files owned by
whoever uploads them, and they are attached to that person's user record, because
Salesforce requires an uploaded file to be attached to a record and there is no better
record to attach a logo to. Two consequences: keep the person who uploads the logo as an
active user, and if the logo needs to change, upload the new one rather than editing the
old file.

**What Maria sees:** five boxes, two upload buttons, and the logo and signature themselves
once they are uploaded. The tax identification number box says what one looks like
(`12-3456789`) and tells her to leave it blank outside the United States.

**What she decides:** which name is the legal one. If you have a "doing business as" name,
the legal name goes here and your everyday name goes on the letter text later.

### Step 7: Bring in your data

Two buttons, and you may use either, both, or neither:

- **Load the sample data** puts about two hundred realistic households, people, and
  organizations in your org so you can practise on something that is not your real data.
  You can remove it again from the same panel.
- **Import a spreadsheet** opens the Import tab, where you upload your file, map your
  columns, run a dry run, and see what would happen before anything is created.

If the Import tab is not in your org yet, the step says so rather than sending you to a
page that does not exist, and the same is true of the sample data loader.

**What Maria sees:** both buttons. She loads the sample data, because her real export is
still being cleaned up.

**What she decides:** practise first, or go straight to the real thing. Practise first.

### Step 8: Check that everything works

Follow the short walkthrough: add a person and see their household appear. With the Giving
module installed, the step also has **Enter your first gift**, which opens the Giving
module's own gift entry screen: enter one gift, save it, and you have proved the whole chain
works, from donor to household to gift. Come back to the home page afterwards and click
**Finish**.

Click **Finish**. The assistant shows the completion screen: every step with its status,
and how long setup took, measured from the first change you made.

**What Maria sees:** "You are ready", her eight steps, and `21 minutes`. Two buttons sit
under the summary: **Reopen setup** walks the steps again with her answers intact, and
**Start setup again** forgets the progress it recorded so the checklist starts from the
first step. Neither of them empties a setting: a step whose answer is already saved stays
finished, because it is.

## Common mistakes

- **Treating Skip for now as done.** Skipping moves you on without marking the step
  finished, on purpose. A skipped step still shows as **To do**, and the next time you open
  the home page the assistant opens on it again.
- **Marking coexistence mode and then changing your mind quietly.** Changing the mode later
  is allowed and is a real change: it changes how household membership is tracked from that
  point on. Change it on the BarnCRM Settings page, read the note there first, and do it
  before you import, not after.
- **Uploading the logo from a colleague's login, then deactivating them.** The file belongs
  to the person who uploaded it. Upload the logo and the signature from an account that
  will stay active, ideally the administrator's.
- **Putting the everyday name in the legal name box.** Receipts have to carry the name your
  official filings carry. If they differ, the legal name goes in step six.
- **Expecting the assistant to install Giving.** No app can install another package for
  you. Step one says how to get it, and the Giving steps appear the moment you come back
  after installing it.
- **Choosing the Community Suite to switch Giving off.** The suite decides what the
  assistant offers, not what runs. A module you have installed keeps working whichever suite
  you choose; to stop using one, uninstall it.
- **Re-running setup to fix one thing.** You do not have to. Every answer is on the
  BarnCRM Settings page, grouped by section, with a search box. Reopen the assistant when
  something big changes, such as a new fiscal year or a merger, not to correct a typo.

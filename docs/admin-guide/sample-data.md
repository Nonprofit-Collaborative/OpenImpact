# Sample data

## 1. What it does

Sample data fills your org with a realistic demo dataset: 200 households, 440 people,
and 25 organizations such as foundations, local businesses, churches, and a school
district. Use it to see Open Impact working with real-looking names and
addresses before you import your own list, to train a new colleague, or to try a
setting change (for example a household naming pattern) against data that already has
the variety your real list has: shared surnames, different surnames, hyphenated names,
single-person households, three-generation households, and a few households with a
deceased member. You can remove every sample record in one action when you are done
with it.

## 2. How to turn it on

1. Open **Nonprofit Settings**.
2. In the **General** section, find **Sample Data** and open it. If you do not see it,
   type "sample" in the settings search box.
3. Read the warning, then select **Load Sample Data**.
4. Confirm in the dialog. Loading runs in the background; the card shows progress and
   updates automatically until it finishes, usually under a minute.

If you came here from the Setup Assistant, the same **Sample Data** step takes you to
this screen. Loading sample data is entirely optional; skipping it does not block any
other step.

You need the **Manage Nonprofit Settings** permission to load or remove sample data.
Without it, the card is read only and tells you who to ask.

Sample data loads whichever way your org tracks household membership. In the simple way,
each sample person carries their household on their own record. In the flexible way (the
Agentforce Nonprofit coexistence mode, which Nonprofit Cloud orgs get), each sample person
is joined to their household by a household member record, exactly as your own people are,
and the card says so before you load.

One difference to expect in an org that stores people as accounts: the sample people arrive
as contacts. Open Impact never creates person accounts, so the sample set shows you
households of contacts. Everything else behaves as it will with your own data: the same
household records, names, greetings, member counts, and Members panel.

## 3. A five-minute walkthrough (as Maria)

1. Open **Nonprofit Settings**, go to **Sample Data**, and select **Load Sample Data**.
   Confirm the dialog. Wait for the card to show **Loaded**, with counts for
   households, contacts, and organizations.
2. Open the **Households** tab. Use the list view search to find "Garcia" and open
   **The Garcia Family**.
3. On the household record, check the formal and informal greeting fields. They read
   naturally, for example "Mr. and Mrs." followed by the names, and a first-names-only
   informal greeting, because they were computed by the naming rules from the sample
   household's members. The names and greetings are computed by household automation as
   the people are added, so they only appear if household naming is turned on.
4. Still on **Households**, search for "Staff Household". This is the sample data's own
   staff family: Maria, David, Priya, Tom, Jen, and Sam appear here as contacts, so you
   can find a familiar name while you are learning the app.
5. Return to **Nonprofit Settings**, **Sample Data**, and select **Remove Sample Data**.
   Confirm the dialog. The card returns to **Not loaded** and every household, contact,
   and organization the loader created is gone, along with the household member records
   that joined them if your org uses the flexible way. Anything you entered yourself is
   untouched.

## 4. Common mistakes

- **Loading sample data into a production org.** Sample data is meant for scratch orgs,
  sandboxes, and demos, never for the org your organization runs on day to day. The
  warning on the Sample Data card says so before you confirm; if you see real donor
  records in a report next to "Garcia Family" or "Staff Household," you loaded it by
  mistake. Remove it right away with **Remove Sample Data**, and audit any receipts,
  exports, or emails sent while it was present.
- **Trying to load twice.** Loading again while sample data is already present shows a
  message that it is already loaded. Remove it first if you want a fresh copy. While a
  load is still running, both **Load Sample Data** and **Remove Sample Data** are
  unavailable: removing halfway through would delete households the loader is still
  attaching people to.
- **Assuming removal is instant.** Removal deletes several hundred records and takes a
  few seconds; wait for the card to confirm **Not loaded** before assuming it is done.
- **Expecting sample person accounts in an Agentforce Nonprofit org.** The sample people
  are contacts even where your own people are stored as accounts. That is a limit of the
  sample set, not of households: the households, memberships, names, greetings, and counts
  all work the same way they will with your own records.
- **Not having the permission.** If the **Load Sample Data** button does not appear, you
  are missing **Manage Nonprofit Settings**. Ask an administrator to grant it from the
  **Access** page, not from Setup.

## Reference

| What you see | Underlying field or object |
|---|---|
| Sample Data checkbox on households, contacts, and organizations | `Sample_Data__c` on Account and Contact |
| The join between a sample person and their household, flexible mode only | `Household_Member__c`, removed with the household it belongs to |
| Sample Data settings entry | `Setting_Definition__mdt` record `Sample_Data` |

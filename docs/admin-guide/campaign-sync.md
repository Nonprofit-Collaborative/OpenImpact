# Campaign Sync

## What it does

Open Impact records fundraising efforts as appeals. Salesforce has its own object for the
same idea, the Campaign, and many tools only understand that one: Campaign Members, email
marketing apps, event tools, and the Campaign reports your team may already use.

Campaign sync gives each appeal a matching Campaign and keeps it up to date. When David
creates the spring appeal, a Campaign named `Spring appeal` appears with the same dates,
goal and cost, and anyone who manages mailing lists can add Campaign Members to it straight
away. When David changes the appeal, the Campaign follows.

It works in one direction only. The appeal is the record you edit; the Campaign is a copy.

| On the appeal | On the Campaign |
|---|---|
| Name | Campaign Name |
| Description | Description |
| Start Date | Start Date |
| End Date | End Date |
| Goal | Expected Revenue in Campaign |
| Cost | Actual Cost in Campaign |
| Active | Active |
| Parent Appeal | Parent Campaign (the parent appeal's Campaign) |

Nothing else is written. A new Campaign takes your organization's usual Type and Status. The
Campaign's own money totals come from Opportunities, not from gifts, so they stay empty
unless your organization also mirrors gifts to Opportunities.

Campaign sync never deletes a Campaign. Deleting an appeal leaves its Campaign, and its
members, where they are.

## How to turn it on

You need the Connect module installed, and a Salesforce edition that has Campaigns (Sales
Cloud, Service Cloud, or Nonprofit Cloud). An org on Salesforce Platform licenses only has no
Campaigns, and the Campaign sync page says so.

1. Give yourself the **Campaign Sync** permission set. Until the Module Manager arrives,
   module permission sets are assigned in Setup.
2. Open **Nonprofit Settings**, choose **Giving**, and switch on **Copy appeals to
   Campaigns**.
3. Still in **Giving**, open **Campaign sync**. It shows how many appeals have a Campaign.
   Click **Sync all appeals** once, so the appeals you already had get their Campaigns.

**Who gets a Campaign when they save an appeal.** The Campaign is created with the access of
the person saving the appeal. Salesforce only lets someone create Campaigns when their user
record has the **Marketing User** box ticked and their profile or a permission set allows
creating and editing Campaigns. Both are in Setup. If David does not have them, his appeals
still save, but they get no Campaign until someone who does have them clicks **Sync all
appeals**. Choose one:

- tick **Marketing User** for the people who create appeals, and give them Campaign create
  and edit access; or
- leave their access as it is, and click **Sync all appeals** after a batch of new appeals.

Clicking **Sync all appeals** needs the Manage Nonprofit Settings permission (the Nonprofit
Admin permission set has it) as well as Campaign access.

## A five-minute walkthrough

Do this as Maria, in an org that has Campaigns, with the sample data loaded and Campaign
sync switched on as above.

1. Open **Nonprofit Settings**, **Giving**, **Campaign sync**. Note the numbers: for
   example `0 of 6 appeals have a Campaign.`
2. Click **Sync all appeals**. The page says the sync has started. Wait a minute and reload
   the page: every appeal now has a Campaign.
3. Open the **Appeals** tab and click **New**. Name it `Giving Tuesday`, set a **Goal** of
   5,000 and a **Start Date**, and save.
4. Open the App Launcher, search for **Campaigns**, and open the list. `Giving Tuesday` is
   there, with Expected Revenue of 5,000 and the same start date.
5. Back on the appeal, change **Goal** to 7,500 and save. Reload the Campaign: its Expected
   Revenue is now 7,500.
6. Create a second appeal, `Giving Tuesday: matching challenge`, with **Parent Appeal** set
   to `Giving Tuesday`. Its Campaign shows `Giving Tuesday` as its Parent Campaign.
7. On the `Giving Tuesday` Campaign, add a Campaign Member. Open the appeal again: nothing
   about it changed, because the copy only goes from appeal to Campaign.

## Common mistakes

**An appeal has no Campaign.** The **Appeals and their Campaigns** list view on the
Appeals tab shows which ones: their Campaign ID is empty. Most often the person who saved it cannot create Campaigns
(see How to turn it on). The Error Log has a Warning for that save. Otherwise a rule on
Campaign refused it: a validation rule or a required field your organization added to
Campaign. The Error Log has a Warning naming the appeal and what Salesforce said. Fix the
cause, then click **Sync all appeals**.

**Editing a copied field on the Campaign.** The next time the appeal changes, its values
replace yours. Edit the appeal instead. Fields that are not copied, such as Type, Status or
your own custom fields, are never touched.

**Linking an appeal to a Campaign you already had.** Open the **Appeals** tab and choose
the **Appeals and their Campaigns** list view, which Campaign sync adds. It shows each
appeal's **Campaign ID**. Double-click the appeal's Campaign ID cell, paste the existing
Campaign's record ID (the 18-character code in its web address, starting `701`), and save. The appeal's name, dates, goal and cost are written onto that
Campaign, replacing what it had. One Campaign can belong to only one appeal. A value that is
not a Campaign's record ID is refused.

**A linked Campaign was deleted.** Campaign sync does not make a replacement, because it
cannot tell a deleted Campaign from one you are not allowed to see, and a replacement for a
Campaign that still exists would be a duplicate. Each change to the appeal logs a Warning.
Clear the appeal's **Campaign ID** in the **Appeals and their Campaigns** list view and
save: a new Campaign is created.

**Turning Campaign sync off and expecting the Campaigns to go.** They stay. Switching it off
stops the copying and deletes nothing.

**Switching on in an org that already uses Campaigns, such as an NPSP org.** Sync all
appeals creates a new Campaign for every appeal that has none. If an appeal and an existing
Campaign are the same effort, link them by Campaign ID first (see above), then sync.

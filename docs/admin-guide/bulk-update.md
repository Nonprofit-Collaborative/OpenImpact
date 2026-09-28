# Bulk update

## 1. What it does

**Bulk update** changes up to five fields on every record a [Find](find.md) query returns, in
one go: set a field to a value, clear it, or copy another field of the same record into it.
Before anything changes you see how many records match and how the first few would change,
and you confirm that number. Every change is recorded, so for as long as an import could be
undone (30 days unless your administrator changed it) you can undo the bulk update: each value
is put back, except where somebody has changed it since.

A bulk update acts with your own access. It changes only records you may edit and fields you
may edit, and it runs your organization's automation, validation rules and duplicate rules as
any save does.

## 2. How to turn it on

Bulk update is in the BarnCRM app for anyone who holds the **Bulk Update Records**
permission.

1. The **BarnCRM Admin** role includes it. To let somebody bulk update without being an
   administrator, give them the **BarnCRM Bulk Update** permission set on its own: in Setup,
   open **Users**, choose the person, and under **Permission Set Assignments** add **BarnCRM
   Bulk Update** (the **Access** page gives roles, not single permission sets). It opens the
   Bulk Update tab and lets them see data jobs; it gives no access to any record. To build new queries as well, they also need **BarnCRM Find and Export**; without
   it they can use saved queries only.
2. Open **BarnCRM Settings** and choose **Import**. **Most records one bulk update may change**
   is 49,000 unless you change it, and anything from 1 to 49,000 is accepted. It cannot be
   higher, because Salesforce lets one request count just under 50,000 records.
3. **Days an import can be undone**, on the same page, is also how long a bulk update can be
   undone. Each bulk update keeps the deadline it started with.

## 3. A five-minute walkthrough (as Maria)

Start with the sample data loaded and the saved query from the [Find](find.md) walkthrough.

1. Open the **Find** tab, open your saved query, select **Run**, then **Send to bulk update**.
   (Or open the **Bulk Update** tab and choose the query from **Open a saved query**.) The page
   shows the kind of record and the query it will use.
2. Under **Changes**, choose the field **Mailing City**, **Set to a value**, and type
   `Portland`. Select **Add a change** for a second field, up to five.
3. Select **Preview**. BarnCRM says how many records match and shows the first five, each with
   the value before and the value after.
4. Type that number into **Type the number of records to confirm**, then select **Update 12
   records** (the button shows your number).
5. The job runs in the background. **Recent bulk updates** at the bottom of the page shows it,
   with how many records were updated and how many failed, and why. The same job also shows on
   the **Data Jobs** tab.
6. To undo it, select **Undo** beside it, check the numbers, and confirm. Each value goes back
   to what it was, unless somebody changed it since the bulk update; those are left alone and
   listed.

## 4. Common mistakes

- **"More records match now than the ... you confirmed."** Somebody added or changed records
  between your preview and your confirmation. Nothing was changed. Select **Preview** again and
  confirm the new number.
- **"Too many records match to count in one go."** One request can count just under 50,000
  records. With the 49,000 maximum you should not see this; if you do, the page already used
  part of its allowance for other reads. Narrow the query, or run it in parts.
- **"... cannot be bulk updated: BarnCRM calculates it."** Some fields are kept by BarnCRM
  itself: every rollup total, a household's name and greetings, member counts and last
  calculated times. Formula fields, fields numbered automatically and fields Salesforce sets
  cannot be changed either, and neither can BarnCRM's own records (imports, data jobs, the
  journal, the error log, settings and setting changes, receipts). Change what they are
  calculated from instead.
- **Some records failed.** A record fails when a validation rule, a locked receipt, a
  duplicate rule or your access refuses the save. The rest still save. Each failure is listed
  with the reason on the job; fix those records by hand, or fix the cause and run a new bulk
  update over them.
- **The undo did not put everything back.** A value somebody changed after the bulk update is
  kept, on purpose, because putting back the old value would silently overwrite their
  correction. The undo lists each such value.
- **"More than ... records match, the most one bulk update may change."** Narrow the query,
  or run it in parts (for example one filter per postal code range).

## Reference

The maximum is `Bulk_Update_Max_Records__c` on BarnCRM Settings. A bulk update is a Data Job
(`Import_Batch__c`) with Operation `Update`; its query and changes are kept on the job.

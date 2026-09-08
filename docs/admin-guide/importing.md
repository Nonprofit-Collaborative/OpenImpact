# Importing

## 1. What it does

Importing loads a spreadsheet of people, households, and organizations into Open Impact
without a consultant. You upload the file, Open Impact suggests which column means what,
you say how a row should be matched against records you already have, and then you run a
**dry run** that tells you exactly what would be created, updated, matched, or rejected
before anything is written. When the preview looks right you commit it, and the results
screen tells you what happened, row by row, including every row that failed and why.

Every record an import creates is tagged with the import it came from, so six months
later you can still answer "where did these 400 households come from".

## 2. How to turn it on

Nothing to turn on. The **Import** tab is in the Nonprofit Hub app for anyone with the
**Manage Nonprofit Settings** permission. If you do not see the tab, ask whoever set up
your org to give you the Nonprofit Admin role on the **Access** page.

Two things are worth setting before your first large file:

1. Open **Nonprofit Settings** and choose **Import**.
2. **Rows per chunk** controls how many rows are processed at a time. Leave it at 200.
   Lower it to 50 if your org has a lot of custom automation and an import fails with a
   limit error; raise it only if a very large file is running slowly and nothing else
   fires on save.
3. **Import** on the same page has an **Open the import wizard** link, which is the same
   place the **Import** tab takes you.

Open Impact ships two ready-made mappings, a **generic donor list** and a **generic gift
list**. You can edit either one, and your edits are never overwritten by an upgrade.

## 3. A five-minute walkthrough (as Maria)

You need a CSV file. A small one is best for the first run: five or six rows.

1. Open the **Import** tab. Select **Generic donor list**, then **Next**.
2. Select **Upload file** and choose your CSV. Open Impact reads the header row and shows
   you every column it found, with the first few values from the file underneath each one.
3. Check the columns. Each column shows what Open Impact thinks it is, for example
   "Email" for a column headed `Donor Email`. Change anything that is wrong from the
   picker beside it. A column you do not want loaded is set to **Do not load**, and its
   values are kept on the staged row but written nowhere.
4. Choose how rows are matched. **Email exact** is the safe default. Read the sentence
   under each rule before you change it: **Name plus postal code** will treat two
   different people who share a name at one address as the same person.
5. Select **Dry run**. Nothing is written. When it finishes you see four counts, "would
   create", "would update", "would match and change nothing", and "would be rejected",
   and a table of the rejected rows with the reason for each one. Select **Download
   exceptions** to get those rows back as a CSV you can fix in your spreadsheet.
6. If the preview is wrong, fix the file or the mapping and dry run again. Nothing you
   have done so far has changed a record.
7. When the preview is right, select **Commit**. Processing runs in the background and
   the screen updates as it goes.
8. The results screen shows the same four counts for what actually happened, the run log,
   and links to the records. Select **View rows** to see every row and what became of it.

To check the tag, open one of the new households and look at **Created By Import Batch**.
It links back to the import.

## 4. Common mistakes

**"No column was matched to a name or an email."** The dry run refuses to run when the
mapping has no way to identify a person or an organization. Usually the file's header row
is not the first row: a title line or a blank line above it means Open Impact read the
wrong row as the header. Delete the rows above the header in your spreadsheet and upload
again.

**Every row comes back as "would create" when you expected updates.** The matching rule
is not finding your existing records. **Email exact** matches only when the email in the
file is exactly the email on the record, so a file of work addresses will not match
people whose personal address you hold. Run a dry run with a different rule, or add an
external identifier column to the file and use **External ID**.

**Rows rejected with "Required value missing: last name".** A person needs a last name.
Rows where the name column is empty, or where a single "Full Name" column was mapped to
first name only, fail this way. Map the full name column to **Full name** and Open Impact
splits it, or split the column in your spreadsheet.

**The import finished but some rows failed.** That is by design: one bad row does not
throw away the rest of the file. The failed rows are counted as rejected, each carries the
reason, and none of them wrote anything. Fix those rows in your spreadsheet, save them as
a smaller file, and import that file on its own.

**Gift columns in the file were not loaded.** This version loads people, households, and
organizations. Gift columns are recognized and kept with the staged row, and the run log
says so, but the gifts themselves are loaded by the Giving module in a later release. Use
the gift entry screen for gifts until then.

## Field reference

For building a report on your imports.

| What you want | Object | Field |
|---|---|---|
| One upload and its counts | Import Batch | Row Count, Rows Created, Rows Updated, Rows Matched, Rows Rejected |
| Why an import failed as a whole | Import Batch | Run Log |
| One row of the file | Import Row | Row Number, Status, Error Message |
| The records a row resolved to | Import Row | Household, Contact 1, Contact 2, Organization |
| The import a record came from | Account, Contact | Created By Import Batch |

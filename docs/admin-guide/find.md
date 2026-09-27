# Find and export records

## 1. What it does

**Find** lists exactly the records you ask for, from any kind of record you can see, without
a report and without Setup. You choose the kind of record, the columns (including columns
from a related record, such as the name of a person's organization), the filters, the order
and how many rows you want. The results show in a table, you can save the question to ask it
again or share it with colleagues, download the results as a CSV file that Excel opens
cleanly, or send them to [Bulk update](bulk-update.md) to change many records at once.

Find only ever shows what your own access allows. A colleague who opens a query you shared
sees the records their access allows, which may be fewer than yours, and a column they may
not see is refused with a sentence naming it.

## 2. How to turn it on

Find is in the BarnCRM app for anyone who holds the **Find and Export Records** permission.

1. The **BarnCRM Admin** role includes it. To let somebody find and export without being an
   administrator, give them the **BarnCRM Find and Export** permission set on its own: in
   Setup, open **Users**, choose the person, and under **Permission Set Assignments** add
   **BarnCRM Find and Export**. This is the one step that needs Setup, because the **Access**
   page gives roles, not single permission sets. The set opens the Find tab and nothing else:
   it gives no access to any record.
2. Open **BarnCRM Settings** and choose **Import**. **Export row limit** is how many rows one
   export may download. The default is 50,000, and anything from 1 to 100,000 is accepted.
   A larger export is slower in the browser; narrow the filter rather than raising the limit
   when you can.
3. **Find** on the same page has an **Open this page** button, which goes where the **Find** tab
   takes you.

## 3. A five-minute walkthrough (as Maria)

Start with the sample data loaded ([Sample data](sample-data.md)).

1. Open the **Find** tab. In **Find**, choose **Contacts**. The query box underneath shows
   the query BarnCRM will run, and it changes as you build.
2. Under **Columns**, choose **First Name**, then **Add column**. Do the same for **Last
   Name** and **Email**. To add a column from a related record, choose **Account >**, then
   **Account Name** from the second list, then **Add column**. A column can follow at most
   two such steps, for example **Account > Owner > Full Name**.
3. Under **Filters**, select **Add filter**. Choose **Mailing Zip/Postal Code**, the condition
   **starts with**, and type `97`. Add a second filter: **Created Date**, **equals**, and
   under **When** choose **This year** instead of a date.
4. Leave **Filter logic** empty to require every filter. To say something else, number the
   filters: `1 AND (2 OR 3)`.
5. Under **Sort by**, choose **Last Name**, **Ascending**. Leave **Row limit** empty.
6. Select **Run**. The table shows the matching contacts, at most 2,000 of them, and says how
   many it shows.
7. Select **Save query**, name it `Portland contacts this year`, tick **Share with other
   people who use Find** if colleagues should see it, and select **Save**. Next time, choose it
   from **Open a saved query**.
8. Select **Export to CSV**. BarnCRM downloads every matching row, a page at a time, up to the
   export row limit, and saves a file named after the kind of record and the date.
9. To change these records, select **Send to bulk update** ([Bulk update](bulk-update.md)).

The query in the read-only box is standard SOQL. A trained administrator can check it or
copy it into another tool; you cannot type a query into Find.

## 4. Common mistakes

- **"The field ... does not exist on ..., or you do not have access to it."** The query names
  a column or filter your access does not include, often because somebody else saved and
  shared it. Remove that column or filter, or ask your administrator for access to the field.
- **The export has fewer rows than the table said.** The export follows the filters and the
  row limit, in the order the records were created, not the sort shown in the table. If it
  stopped with "The export stopped at the export row limit", narrow the filter or ask your
  administrator to raise **Export row limit** in BarnCRM Settings, Import.
- **A number or date in Excel looks wrong.** The file writes dates as `2026-09-27` and times in
  UTC. Excel may show them in its own format; the value is the same. A text value that starts
  with `=`, `+`, `-` or `@` is written with an apostrophe in front, so Excel shows it as text
  instead of running it as a formula.
- **"Only the person who saved a query can change or delete it."** You opened a query a
  colleague shared. Change it, then use **Save query** with a new name to keep your own copy.
- **A lookup does not offer a second list.** A lookup that can point at more than one kind of
  record (for example an owner that may be a person or a queue) cannot be followed in this
  version. Its record ID can still be a column.

## Reference

The export row limit is `Export_Row_Limit__c` on BarnCRM Settings. Saved queries are stored as
Saved Query records, which only their owner can see unless they are shared.

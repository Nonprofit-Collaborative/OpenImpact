# Duplicates

## What it does

Finds people and households that are in your database twice, and helps you deal with them one
at a time. Salesforce itself does the finding: it can warn the person typing that somebody
similar already exists, and it keeps a list of every pair it has spotted. Open Impact switches
that on with rules written for a nonprofit, adds a scan for the duplicates that were already
there before you installed anything, and puts the whole list on one page with the household
merge one click away.

Nothing is ever merged or deleted for you. Every merge is a pair you looked at and confirmed.

## How to turn it on

Two of the steps are in Setup, and they cannot be moved into the app: activating a matching
rule is a Salesforce Setup action with no equivalent an installed app can perform. Everything
after that is in Nonprofit Settings.

1. In Setup, go to **Matching Rules**. Activate **Open Impact contact match** and **Open Impact
   household match**. Activation takes a minute or two and the page shows when it is done.
2. In Setup, go to **Duplicate Rules**. Activate **Open Impact contact duplicates** and **Open
   Impact household duplicates**. A duplicate rule cannot be activated until the matching rule
   it uses is active, which is why the order matters.
3. In the Nonprofit Hub, open **Nonprofit Settings**, choose **Households**, and scroll to
   **Duplicates**. Each rule is listed with On or Off next to it. If one still says Off, go
   back to step 1.
4. Press **Scan for duplicates**. This looks through the people and households you already
   have. It runs in the background and can take a while in a large database.

From now on, Salesforce warns anybody who saves a record that looks like one you already have,
and records the pair on this page whether they heed the warning or not.

If you would like the warning to appear on the record page as well as at the moment of saving,
edit the Contact or Account Lightning page and add the standard **Potential Duplicates**
component. That is a Salesforce component, not an Open Impact one.

## A five-minute walkthrough

Start with the sample data loaded (see [sample-data.md](sample-data.md)) and the rules
activated as above.

1. Open **Nonprofit Settings**, choose **Households**, and scroll to **Duplicates**.
2. Press **Scan for duplicates**. You will see "Scan started. It runs in the background and the
   suggestions appear here as they are found."
3. Wait a minute, then refresh the page. Under **Possible duplicates** you will see pairs, each
   showing two records with their town and postal code, or a person with their email address.
4. Find a pair of households. Press **Compare and merge**. You will see the two households side
   by side, the fields where they disagree, and a choice of which one to keep.
5. Choose the household to keep and press **Merge these two**. The other household's members,
   gifts, files and activities move to the one you kept, and the suggestion disappears from the
   list. You will see "The two households are now one."
6. Find a pair of people who are not actually the same, for example two sisters at one address.
   Press **Not a duplicate**, type a short reason, and confirm. You will see "Noted. This pair
   will not be suggested again." Press **Scan for duplicates** again and check that the pair
   does not come back.
7. For a pair of people who are the same, press **Open** on either one, then use the Salesforce
   merge on their record. Salesforce merges people better than we could, and it keeps their
   gifts, activities and files.

## Common mistakes

**The page says no rule is switched on, and the scan button refuses.** The scan asks Salesforce
to apply your active duplicate rules to records that already exist. With no active rule there
is nothing to apply, and reporting a clean database would be a lie. Activate the matching rules
first, then the duplicate rules, and check that all four show On before scanning.

**The scan finds nothing in a database you know has duplicates.** The shipped rules are strict
on purpose: two people match on the same email address, or on the same last name with the same
mailing postal code. Two households match on the same name with the same billing postal code or
the same billing street. Records with no email and no postal code cannot match on anything, so
a spreadsheet imported without addresses will not produce suggestions. Fill in the postal codes
first, or loosen the matching rule in Setup and scan again.

**The same pair keeps coming back after you merged them.** Merging households from this page
removes the suggestion. If you merged somewhere else, for example in the Salesforce merge on a
record, the old suggestion can linger until the next scan. Press **Not a duplicate** on it, or
delete the duplicate record set from the Duplicate Record Sets tab.

**A colleague sees the page but the Scan and Not a duplicate buttons are missing.** Those two
actions need the Manage Nonprofit Settings permission, which the Nonprofit Admin permission set
grants. Reviewing and merging do not: anybody who can edit both households can merge them.

**You dismissed a pair and now want it back.** Dismissals are records. Open the Duplicate
Dismissals list, find the pair, and delete it. The next scan will suggest that pair again.

## What Open Impact ships

| Thing | Name in Setup | What it matches |
|---|---|---|
| Matching rule | Open Impact contact match | The same email address, or the same last name with the same mailing postal code |
| Matching rule | Open Impact household match | The same account name with the same billing postal code or the same billing street |
| Duplicate rule | Open Impact contact duplicates | Warns on save, never blocks, and records the pair |
| Duplicate rule | Open Impact household duplicates | Warns on save, never blocks, and records the pair |

These are the same tests the import wizard uses to decide that a row in your spreadsheet is
somebody you already have, so an import and a duplicate scan agree about who is who. All four
ship switched off, because Salesforce requires a matching rule to be activated after it is
installed rather than during.

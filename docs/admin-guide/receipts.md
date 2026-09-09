# Receipts and year-end statements

## What it does

Open Impact produces the numbered PDF a donor needs at tax time: one receipt for one gift,
or one consolidated statement listing everything a donor gave in a year. Each document
carries a number that is used once and never again, and the file is stored on the gift and
on the donor so anyone can find the exact copy the donor received.

A receipt never changes after it is issued. If something on it is wrong, you void it and
issue a new one; both stay on the record, so you can always answer the question "which
document does this donor actually hold".

The required tax wording is written by Open Impact, not by you. You write the letter around
it.

## How to turn it on

Everything is on one page: **Nonprofit Hub, then Nonprofit Settings, then Receipts**.

### 1. Check your organization details

The Organization section of Nonprofit Settings holds your legal name, your tax
identification number, your address, your logo, your signature image, and the name and
title of whoever signs your letters. A receipt prints these. If you completed the Setup
Assistant they are already filled in. If your legal name is blank, receipts will not
generate and Open Impact tells you which field is missing.

### 2. Set your numbering

In the Receipts section:

- **Receipt number prefix.** Two or three letters, usually your initials. The number is
  built as prefix, year, counter: `HFH-2026-000001`.
- **Next counter.** Leave it at 1 unless you are moving from another system and want to
  carry on from where it stopped. Set it once, before you issue anything.
- **Statement year.** The tax year the year-end run covers. Set it in January to last year.
- **Place of issue.** The city and region you issue from. Optional in the United States.

### 3. Write your two letters

Also in the Receipts section, **Receipt letters and year end statements** opens a panel with
two tabs. On the **Receipt templates** tab, Open Impact ships one letter of each kind:

- **Per gift receipt**, for a single gift.
- **Consolidated statement**, for a donor's whole year.

Pick a letter, edit the wording, keep the tokens (`{{DonorName}}`, `{{Amount}}`,
`{{GiftDate}}` and the rest, listed under the editor), and click **Save**. If the letter you
edited is not the one in use, **Use this letter** switches it on and switches the other one of
its kind off. Only one letter of each kind is in use at a time.

**You cannot delete the tax sentences by deleting them from the template.** Open Impact adds
them to every document regardless of what the letter says. That is deliberate: those
sentences are what makes the document a valid receipt.

### 4. Give people access

On the Access page, **Giving Staff** and **Giving Admin** can issue, void and reissue
receipts and start a run. Everyone with any Giving permission set can read receipts and open
the stored files. **Nobody can edit or delete an issued receipt or its file**, including
Nonprofit Admin. That is not an oversight, and there is no switch for it.

## A five-minute walkthrough

Start from the sample data.

1. Open **Nonprofit Settings**, then **Receipts**. Set the prefix to `TEST`, leave the next
   counter at 1, and set the statement year to last year.
2. Open **Receipt letters and year end statements**, and on the **Receipt templates** tab
   check that a letter of each kind is in use. If one is not, pick it and click **Use this
   letter**.
3. Open any gift from the sample data. Click **Issue receipt**. You will see a receipt
   number appear on the gift, and a PDF in the Files list on the gift and on the donor.
4. Open the PDF. It states your organization's name, the amount, the date, and the sentence
   "No goods or services were provided in exchange for this contribution."
5. Now break it on purpose. Try to change the gift's amount. The save is refused with "This
   gift has a receipt number, so its amount, date and donor cannot change. Void the receipt
   and reissue it, or record a refund."
6. On the gift, click **Void and reissue**. Type a reason, for example "Amount was entered
   wrongly". You get a second receipt with the next number, the first one is marked Void with
   your reason and today's date, and **the original PDF is still there, untouched**. Open
   both files and compare them.
7. Go to the **Receipts** tab and look at the two records. The voided one points at its
   replacement, the replacement points back at what it replaces.
8. Back in Nonprofit Settings, under Receipts, open the **Year end statements** tab, check
   the statement year, and click **Generate**. A run appears in the list below and counts up
   as it goes; **Refresh** updates it. When it finishes, open a household with several gifts
   in that year and read its statement: every gift is a line, each line carries its own
   status, and the total at the bottom is the sum of the lines.

That is the whole feature. Steps 5 and 6 are the ones worth doing twice, because they are
what makes the rest trustworthy.

## Common mistakes

**Changing the prefix or the counter after you have issued receipts.** The numbering
sequence is created the first time a receipt of a given kind is issued in a given year, and
it keeps the prefix and starting counter it was created with. Changing the settings later
affects next year's series, not this one. If you have issued one test receipt with the wrong
prefix, void it and say so in the reason, then fix the setting before you issue anything
real.

**Expecting the numbers to have no gaps.** They will occasionally have gaps, and that is
normal and safe. If a document fails to generate after its number was handed out, Open
Impact does not hand that number to somebody else. It creates a receipt record with status
Void and the reason "Generation failed", so if an auditor asks what happened to number 47,
you can show them. A gap you cannot explain would be the problem; a gap with a Void record
against it is an answer.

**Deleting a receipt's file to "cancel" it.** Voiding is the way to cancel a receipt, and it
deliberately leaves the file alone: the donor still has their copy, so the org should too.
Nobody has delete access on receipts or their files, so this mostly shows up as a puzzled
"why can't I delete this". Void it instead.

**Running year-end statements before the year's gifts are all entered.** A donor who already
has a statement for the year is skipped when you run again, so late gifts will not appear on
a second run. Fix that donor by voiding their statement and reissuing it, which picks up
everything. Running the batch twice is safe and cheap; it is only the donors already
receipted that are skipped.

**Putting a value on an in-kind gift's receipt.** You cannot, and you should not want to. For
a gift of goods, Open Impact prints the description the donor gave and never a value, because
in the United States valuing a donated item is the donor's responsibility and not yours. The
Fair Market Value you record stays in Open Impact for your own reporting.

## Two things that are not settled yet

Recorded here rather than hidden, because both may change what you see:

1. **Logos and signature images on the PDF may not appear yet.** How an image reaches the PDF
   renderer has not been confirmed in a real org (ADR-0016). A receipt with no logo and no
   signature is a legally valid receipt, so this does not stop you sending them. If your logo
   does not print, that is this, not your setup.
2. **The speed of a very large year-end run has not been measured.** If you have tens of
   thousands of donors, run your statements early in January rather than the night before you
   want to post them, and watch the Receipt Run record.

## Fields, for a report builder

| What you want to report on | Object |
|---|---|
| Each document issued, its number, status and amount | Receipt |
| Each generation run, its counts and outcome | Receipt Run |
| The number series and where each one has got to | Receipt Number Sequence |
| The letters themselves | Receipt Template |

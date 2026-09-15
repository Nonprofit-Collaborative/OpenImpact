# ADR-0032: Acknowledgments send standard email templates and keep a ledger, and share no machinery with receipts

**Status:** Accepted
**Date:** 2026-09-09
**Source:** plan Section 5.2 feature G-12 ("Acknowledgment rules and templates (email, letter
merge) with sent tracking", note: "Uses standard email templates where possible"); plan
Section 4.11 (`Acknowledgment_Rule__c`); ADR-0006, ADR-0016, ADR-0017, ADR-0020, ADR-0021,
ADR-0024, ADR-0027

## Context

G-13 shipped receipting hours before this was written, and the two features look alike from a
distance: both take a gift, produce a document with the donor's name and amount in it, send it,
and record that it went. Building the second one on the first is the obvious move and it is
wrong in most of its parts.

A receipt is a tax document. Its number is consumed once, its stored PDF never changes, its
content sentences are fixed by IRS Publication 1771 and are emitted by code rather than by a
template, and a correction is a void and a reissue (ADR-0010, ADR-0016). An acknowledgment is a
thank you. Its wording is entirely the organization's, it is re-sendable, it carries no
statutory content, nobody audits it, and its worst failure is embarrassment rather than a
donor's amended return.

Four questions had to be answered before anything could be built: what starts an
acknowledgment, where "we thanked this donor" is recorded, what the letter path actually
produces, and what stops a donor being thanked twice.

## Decision

**1. A rule marks; a run sends. Nothing sends inside a trigger.**
`Acknowledgment_Rule__c` holds what the plan's Section 4.11 says it holds: amount range, gift
type, appeal, first gift, and an order, matched first-rule-wins, resolving to a channel (Email,
Letter, None) and, for Email, an email template. The switchable automation
`Gift_Acknowledgment` (`GiftAcknowledgmentHandler`, order 40, `Always_Runs__c` false, because
thanking a donor is a convenience and not a rule under ADR-0024) does one cheap thing on save:
it sets `Acknowledgment_Status__c` to `To acknowledge` or `Not required`. Sending happens in
`AcknowledgmentBatch`, started by a button on the Acknowledgments page or by an optional
nightly schedule. A trigger that sent mail would send 200 thank yous in the middle of an
import, could not be reviewed before it went, and cannot report what it did.

**2. Sent tracking is a record, not a field.** `Acknowledgment__c` carries one row per
acknowledgment: gift, rule, channel, the template's developer name as it was at the time,
status (Queued, Sent, Failed, Skipped), sent time, recipient, failure reason, and its run. A
field on Gift cannot answer "did this go twice", "which letter did they get" or "why did it
fail", and the January question after a mail merge goes wrong is exactly the second one. The
two Gift fields that already exist (`Acknowledgment_Status__c`, `Acknowledgment_Date__c`,
R-G9) stay as the cheap summary that list views and reports read, written from the ledger and
never the other way around.

**3. Email is a standard `EmailTemplate` sent with `setTemplateId`, and the package composes
no email HTML at all.** The message names the donor Contact as target and the gift as
`WhatId`, so `{!Contact.FirstName}` and `{!Gift__c.Amount__c}` are merged by the platform, in
the template editor the admin already knows, with the preview and the test-send Salesforce
already ships. The package writes no merge engine, ships no email template object, and reuses
nothing from `ReceiptTemplateService` or `ReceiptContentBuilder`.

**4. The letter path produces a CSV of merge rows and says so.** `Acknowledgment_Run__c` of
channel Letter gathers the gifts whose rule says Letter, writes one `ContentVersion` CSV
(one row per gift: donor name, greeting, address lines, amount, gift date, appeal, fund,
tribute, rule name) linked to the run, and leaves its ledger rows Queued. The admin downloads
the file, merges it in Word or Google Docs against their own letter, prints, and then presses
**Mark as sent**, which stamps the rows and the gifts. The package renders no letter PDF: a
printable pack would need the ADR-0016 renderer, whose spikes are still open, and would replace
the merge document the organization already has and wants to keep using.

**5. Two things stop a donor being thanked twice.** `Acknowledgment__c.Gift_Key__c` is a
unique text field holding the gift id while an acknowledgment stands, so a second row for the
same gift cannot be inserted, which is what makes a retried batch chunk resume rather than
re-send (the same mechanism as `Receipt__c.Donor_Year_Key__c`, R-RC9). And the automation
never returns an Acknowledged gift to the queue: only a person setting
`Acknowledgment_Status__c` back to `To acknowledge` does that, and the handler treats that as
the deliberate act it is, releasing the key on the standing row so a second row can be written
and both survive to be counted.

**6. Refunds and reversals are never thanked.** Only a gift with `Status__c` Received and
`Amount__c` greater than zero is ever queued or sent, so a refund, a write-off and the negative
gift that records one are outside the feature. A refund does not un-acknowledge the original
gift: the donor was thanked, and that happened.

## Alternatives considered

- **Reuse `Receipt_Template__c` and `ReceiptContentBuilder` for acknowledgment wording.**
  Rejected: it would replace a standard email template with a custom HTML body an admin edits
  in a textarea, losing the platform's editor, preview, test send and merge-field picker, and
  it is what the plan's note on G-12 tells us not to do.
- **Reuse `Receipt__c` as the sent record.** Rejected: it is immutable by validation rule and
  by field level security, nobody may create one, and its numbering is a locked sequence. All
  three exist for a document an acknowledgment is not.
- **A `Last_Acknowledgment_Sent__c` field instead of a ledger.** Rejected under question 2.
- **Send from the gift trigger.** Rejected under question 1.
- **Render letters as PDFs through `ReceiptRenderer`.** Rejected under question 4; revisit when
  the ADR-0016 spikes close and an organization asks for it.
- **A second scheduled job with no way to schedule it.** Rejected: `GivingScheduler.scheduleAll`
  is called by a module turn-on step that does not exist, so the Giving nightly jobs are
  scheduled nowhere in a real org. The acknowledgment send follows C-18 instead: its own
  `Schedulable`, started and stopped by a toggle on its own page (ADR-0027), which is the only
  pattern in this repository that has ever actually scheduled anything.

## Consequences

- **What is shared with G-13:** the Error Log contract, the trigger framework and
  `Automation_Registry__mdt`, the settings console and `Setting_Definition__mdt`, the
  ADR-0021 system-mode writer posture, the run-record-with-counts shape, and the unique-key
  idempotency trick. **What is not:** template storage, merge tokens, numbering, immutability,
  content rules, the PDF renderer, the file store and the permission. Two features that both
  write a run record are not one feature.
- **The console reaches this page by navigation, not by a component.** Core cannot import a
  component from a package that depends on it (ADR-0020), so the Setting Definition row carries
  `Navigation_Target__c` and no `Component__c`.
- **The default thank you ships as metadata, in a packaged email folder.** Until the first
  managed package version is created there is no upgrade to be safe from. When it is created,
  a packaged template may be read only in the subscriber org, which Principle 6 forbids: the
  follow-up is to materialize a copy the org owns, and it is recorded in the plan's parking
  lot rather than built now.
- **A rule names its template by developer name, as text.** No lookup to `EmailTemplate` is
  possible. A name that does not resolve is shown on the page as "template not found" and marks
  its acknowledgment Failed with that reason, rather than sending an empty letter.
- **An organization donor with no contact cannot be emailed.** That acknowledgment is Skipped
  with a readable reason and the gift stays in the queue for the letter run, rather than
  failing the chunk.
- **Revisit when**: an org asks for printable letter PDFs, when Enhanced Email templates
  replace Classic ones for `setTemplateId`, or when the first 2GP version makes the shipped
  template read only.

## First three tests

1. **`AcknowledgmentRuleMatchTest`**: first rule wins by order; a gift outside a rule's amount
   range, of the wrong type or on another appeal does not match it; the first-gift rule matches
   only a donor's first gift; a gift matching no rule is left alone; a refund and a negative
   gift match nothing at all.
2. **`AcknowledgmentSendTest`**: the ledger is the guard. A second send over the same queue
   writes no second row and sends no second message; a chunk whose send fails marks that row
   Failed with a reason, writes an Error Log entry, and leaves the other rows Sent; a person
   re-queueing an acknowledged gift releases the key and a second row is written, so the gift
   shows two acknowledgments and not one.
3. **`AcknowledgmentLetterMergeTest`**: the merge file is a file. The CSV carries one header
   and one row per queued letter gift, a donor name containing a comma and a quote is escaped
   so the row still parses, the rows stay Queued until Mark as sent, and marking sent stamps
   both the ledger rows and the gifts.

## Sources

- [Messaging.SingleEmailMessage: setTemplateId, setTargetObjectId, setWhatId](https://developer.salesforce.com/docs/atlas.en-us.apexref.meta/apexref/apex_classes_email_outbound_single.htm)
- [Email limits for Apex: 10 sendEmail invocations, 100 recipients per message](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_gov_limits.htm)
- [IRS Publication 1771, for what an acknowledgment is not](https://www.irs.gov/pub/irs-pdf/p1771.pdf)

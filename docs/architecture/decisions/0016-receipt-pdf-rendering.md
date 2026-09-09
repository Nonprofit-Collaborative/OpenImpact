# ADR-0016: Receipt PDFs are rendered by the Visualforce PDF rendering service, called from Apex

**Status:** Accepted
**Date:** 2026-09-07
**Accepted:** 2026-09-08, by the owner, as the v0.4 prerequisite the plan names
  (Section 6 "PDF generation approach settled", Section 11.2 open question 6)
**Source:** plan Section 11.2 open question 6; plan Section 6 v0.4 engineering item
"PDF generation approach settled"; features G-13 and G-18; ADR-0010

## Context

G-13 requires numbered, immutable receipt PDFs per gift and consolidated year end
statements per household or organization, generated in batch and stored as Files on the
record. ADR-0010 makes the stored PDF the document of record: once issued it never
changes, and a correction voids and reissues.

The constraints are hard. Plan Section 4.2 puts the floor at Salesforce Platform
licences with no paid add on, which removes OmniStudio Document Generation. Principle 1
means an administrator must never install or configure anything extra, which removes any
external rendering service and any default callout. Principle 8 means we use a platform
feature rather than write one.

The plan's provisional recommendation, recorded in Section 11.2, was Visualforce
render as PDF via `PageReference.getContentAsPDF()`. Since Winter '16 those methods are
treated as callouts: they cannot run in a trigger, they fail after DML in the same
transaction, and in an async context they consume the callout allocation, capping a batch
`execute` at ten documents. A 40,000 household year end run under that cap is 4,000
chunks of pure overhead.

Spring '26 changed the situation. `Blob.toPdf()` now renders HTML through the same
Visualforce PDF rendering service, with the same fonts and multi byte support, as plain
Apex rather than as a callout, and the release update that switches the engine is
enforced in Summer '26, before v0.4 ships. The rendering engine the plan chose is
therefore available in the execution context the plan needs it in.

## Decision

- **Receipt and statement PDFs are produced by the Visualforce PDF rendering service,
  invoked from Apex as `Blob.toPdf()` over HTML that the package composes.** Templates
  are HTML with merge tokens, not Visualforce markup.
- Generation sits behind one interface, `ReceiptRenderer`, with a single shipped
  implementation. A Visualforce `renderAs="pdf"` implementation is the named fallback if
  the spike in Section "Consequences" fails; nothing else in the feature knows which is
  in use.
- **Numbering.** `Receipt__c.Receipt_Number__c` is a text field written by a package
  owned sequence, never a Salesforce auto number. Numbers come from a single `FOR UPDATE`
  locked sequence row per series, where a series is a receipt type plus a statement year.
  Format is `{prefix}-{year}-{counter zero padded}`, prefix and starting counter set in
  settings. Batch runs allocate a block of numbers per chunk in one update.
  - A number is **consumed once and never reused.** Gaplessness is not attempted at the
    database level, because a rolled back transaction cannot un-consume it. Instead every
    consumed number is accounted for: a reconciliation step records any number with no
    surviving `Receipt__c` as a `Receipt__c` with `Status__c = Void` and
    `Void_Reason__c = Generation failed`, so an auditor asking what happened to number
    N always gets a record rather than silence.
- **Void and reissue.** `Status__c` is `Issued` or `Void`. Voiding sets `Voided_On__c`
  and `Void_Reason__c` and never touches the stored file. The replacement receipt takes
  the next number and points at the voided one through `Replaces__c`, with
  `Replaced_By__c` on the original. Issued receipts and their files are read only to
  everyone, enforced by validation rules and by field level security in the packaged
  permission sets.
- **Storage.** The bytes live in one `ContentVersion` per receipt, titled with the
  receipt number, linked by `ContentDocumentLink` to the `Receipt__c` and, per receipt
  type, to the `Gift__c` (per gift receipts) and to the donor `Contact` or `Account`
  (both types). `Receipt__c` carries the number, type, status, statement year, donor,
  household or organization, total amount, issue date, and the `ContentDocumentId`.
  Regeneration is never an update: it is a void plus a new receipt.
- **Settings** (per ADR-0006, a protected hierarchy custom setting for scalars and a
  packaged custom object for the template bodies): legal organization name, EIN, address
  lines, city, state, postal code, country, place of issue, signer name, signer title,
  logo file reference, signature file reference, receipt number prefix, next counter,
  statement year, and template text per receipt type with merge tokens.
- **Content rules are code, not template prose.** The renderer emits a goods and services
  sentence per gift: none provided by default; description plus good faith estimate plus
  deductible amount for a quid pro quo benefit; the intangible religious benefits sentence
  when that flag is set. In kind gifts (G-18) print the donor supplied description and
  **never a value asserted by the organization**. Consolidated statements print the status
  on each line, not once in a footer.
- **Batch design.** `Receipt_Run__c` is the parent record for one generation run, with
  counts and status. `ReceiptStatementBatch implements Database.Batchable<SObject>,
  Database.Stateful` iterates donor records that have at least one qualifying gift in the
  statement year, with a **scope of 25**, chosen so peak heap stays far under the 12 MB
  async limit while amortising the per chunk query and sequence lock. Blobs are inserted
  and released inside each `execute`; nothing holds a PDF in stateful members. A unique
  external id on donor plus statement year plus receipt type makes a retried chunk
  idempotent, so a partial run is resumed rather than restarted. Per chunk failures are
  written to the in app Error Log, never swallowed, and never abort the run.
- **Delivery is separate from generation.** Email sends the stored `ContentVersion`; it
  never re-renders.

## Alternatives considered

- **`PageReference.getContentAsPDF()` from a Visualforce page**: the same renderer, but
  callout semantics cap a batch `execute` at ten documents, forbid use in triggers, and
  fail after DML in the same transaction. Retained as the documented fallback because the
  output is byte comparable and the migration is one class.
- **LWC with `window.print()`**: better styling, but the bytes never come back to the
  platform without a user upload or a callout, so no immutable stored document exists.
  This is the option the plan weighed, and it fails ADR-0010 rather than merely costing
  more.
- **OmniStudio Document Generation**: needs an OmniStudio licence plus Document
  Generation permission set licences outside Industries products. Rejected by ADR-0009.
- **A pure Apex PDF writer**: no maintained permissively licensed option exists, and
  owning font embedding and text layout is exactly the custom code principle 8 forbids.
- **A callout to an external renderer**: rejected by principle 1 and 4; also a security
  review liability and a donor data egress question we will not answer for a free product.

## Consequences

- **The receipt template is HTML restricted to what the rendering service supports.** No
  web fonts, no JavaScript, no `data:` URI images, `Arial Unicode MS` for non Latin text,
  and page headers and footers only through `@page` margin boxes. The shipped template is
  written to that envelope and the admin edits text and tokens, not CSS.
- **Two spikes gate the build, both in the first week of v0.4.** One: confirm in a scratch
  org that `Blob.toPdf()` is not metered as a callout and runs inside `Database.Batchable`
  at the intended scope. Two: settle how the logo and signature reach the renderer, trying
  a `ContentVersion` download URL, then a base64 `data:` URI, then a `Document` marked
  externally available via `servlet.ImageServer`. If both fail, the fallback implementation
  ships and this ADR is superseded. **The receipt is legally valid with no images at all**,
  so neither spike blocks G-13.
- **PDF bytes cannot be asserted in Apex tests** on the fallback path and probably not on
  the chosen one. Tests assert the composed HTML and the record and file graph; one manual
  visual check per release joins the v0.4 definition of done.
- **The 40k run must be measured, not assumed.** 40,000 households at scope 25 is 1,600
  chunks; at 30 seconds a chunk that is over 13 hours. The v0.4 performance baseline sets
  the real scope size and, if needed, splits a run into segments. The run is resumable
  precisely because it will be long.
- **The sequence row is a contention point.** Only receipt issuance touches it, block
  allocation keeps the lock short, and a run holds one lock per chunk rather than per
  receipt.
- **Localization is deferred but not designed out.** CRA receipts need a serial number, an
  advantage value, a place of issue and an authorized signature, all of which this design
  already has; the Canadian template itself is out of scope for v1.
- **Revisit when**: `Blob.toPdf()` behaviour changes, a standard Flow PDF action ships
  without an add on licence, or the year end run misses an overnight window in a real org.

## First three tests

1. **`ReceiptNumberSequenceTest`**: a number is allocated once and never reused.
   Consecutive allocations strictly increase, a batch block allocation does not overlap a
   later single allocation, and a number consumed by a failed generation is reconciled
   into a `Void` receipt rather than reissued.
2. **`ReceiptVoidReissueTest`**: ADR-0010 holds end to end. An issued receipt's number,
   amount and `ContentVersion` are unchanged after a void; the void carries a reason and
   a date; the reissue has the next number and the two records point at each other; and
   changing the gift amount while an issued receipt exists fails with a readable message.
3. **`ReceiptContentRulesTest`**: the IRS language is emitted by code. A plain cash gift
   renders the no goods or services sentence with organization name, amount and date; a
   quid pro quo gift over $75 renders the benefit description, good faith estimate and
   deductible amount; an in kind gift renders the description with no organization
   asserted value; a consolidated statement carries the status on every line.

## Sources

- [Fonts Available When Using Visualforce PDF Rendering](https://developer.salesforce.com/docs/atlas.en-us.pages.meta/pages/pages_output_pdf_supported_fonts.htm)
- [PageReference getContent() and getContentAsPDF() methods behave as callouts](https://salesforcekings.blogspot.com/2015/12/pagereference-getcontent-and.html)
- [Use Visualforce PDF Rendering Service with Apex Blob.toPdf() (Release Update)](https://help.salesforce.com/s/articleView?id=release-notes.rn_apex_system_blob_topdf.htm&language=en_US&release=260&type=5)
- [Omnistudio requirement for Salesforce Document Generation](https://help.salesforce.com/s/articleView?id=ind.sf_docgen_requirements_two.htm&language=en_US&type=5)
- [IRS Publication 1771, Charitable Contributions: Substantiation and Disclosure Requirements](https://www.irs.gov/pub/irs-pdf/p1771.pdf)
- [What information must be on an official donation receipt from a registered charity (CRA)](https://www.canada.ca/en/revenue-agency/services/charities-giving/charities/operating-a-registered-charity/issuing-receipts/what-information-must-on-official-donation-receipt-a-registered-charity.html)

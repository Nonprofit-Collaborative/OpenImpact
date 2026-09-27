# ADR-0047: Data management runs in the org, compiles queries from a document, and is phased

**Status:** Accepted
**Date:** 2026-09-23 (amended 2026-09-27: C-32 and C-33 builder decisions, below)
**Source:** product owner decision (Brandon, 2026-09-23), plan Section 4.9, Section 6 and
Section 12 decision D-13; amends the import framework scope of C-14 and C-19

## Context

Maria has to load her old spreadsheet, fix many records at once and find and export exactly the
records she needs, without Setup, API names or an outside tool (plan Section 2.3). The owner asked
for NPSP Data Importer parity, Jetstream's query builder and bulk update, and the useful
dataimporter.io capabilities, phased, with the rest later. Gift import does not work today: no
package implements `ImportEntityProcessor`, and Core looks up a `GiftImportProcessor` class that
does not exist, while the first customers must migrate gifts. A Lightning session cannot call the
REST or Bulk API; the workaround is a Named Credential calling the org from Apex, a stored token
and a self-callout to explain at security review. Plan Section 4.10 forbids SOQL typed by admins.

## Decision

- **Everything runs inside the org, with no call to Salesforce's own APIs.** Batch Apex and
  user-mode DML only; no Named Credential, connected app or Bulk API in v1 or 1.x. Revisited only
  with scheduled imports (C-38), and only if the 1M-gift scale test shows Batch Apex too slow.
- **Queries are compiled from a document, never accepted as text.** Find, bulk update and saved
  queries share one query document (object, fields, R-R2 filter, order, limit). The compiler takes
  object and field names only from describe results, binds every value, and runs
  `Database.queryWithBinds` with `AccessLevel.USER_MODE`. The SOQL shown is rendered for display
  only. Typed SOQL is not in v1; C-36 may add it later only through its own ADR.
- **Bulk update is a data job.** It is an `Import_Batch__c` with `Operation__c` Update, stages no
  rows, treats the confirmed count as a ceiling, journals every change through the C-19 import
  journal, and is undone the same way an import is. The API names stay; the tab reads "Data jobs".
- **Phasing.** v1: gift import (G-23) and donation matching (G-24) in v0.5; matching and per-file
  values (C-32), load one object (C-33), Find with CSV export (C-34) and bulk update (C-35) in a
  new v0.7 Data management iteration. Later: typed SOQL and advanced find (C-36); transforms,
  dedupe on import and bulk delete (C-37); scheduled imports and external sources (C-38), which
  supersede R-IT6's "nothing loads on a schedule" only for that release.
- **Defaults.** When a matching key finds several records the row is rejected. Import stays with
  the settings permission; `Find_And_Export_Records` and `Bulk_Update_Records` are new custom
  permissions that grant no record access.
- **Never built.** Jetstream's metadata deploy, anonymous Apex, permission, API explorer and
  org-wide automation tools, and dataimporter.io's org-to-org migration and backup: Setup, Data
  Loader and Jetstream serve the rare technical user, and each would add security review risk for
  nothing Maria needs. Jetstream is Apache-2.0 with the Commons Clause, not an open source
  license, so its ideas are used and its code is not.

## Alternatives considered

- **Leave data management to Data Loader, Jetstream and dataimporter.io.** Rejected: API names, no
  undo, and a third party holding an OAuth token to donor data.
- **A Bulk API path through a Named Credential.** Rejected for v1 and 1.x: Setup steps, a stored
  token and a self-callout, for speed Batch Apex already has at our scale.
- **Accept typed SOQL from v1.** Rejected: a second enforcement path and an exception to Section
  4.10, for a need reports and list views meet until use shows otherwise.
- **Fold C-34 and C-35 into Hardening.** Rejected: it breaks the three-major rule and puts the tools
  past the beta cohort that should test them.

## Consequences

- Plan Section 5.1 gains C-32 to C-38; the duplicate C-25 (interaction notes) becomes C-39.
  Section 5.2 gains G-23 and G-24 in v0.5, which now carries four major features.
- A new v0.7 Data management iteration is inserted; Volunteers to AppExchange renumber to v0.8 to
  v0.13. Earlier ADRs that name an iteration (ADR-0046 names v0.7 and v0.10) keep their text; the
  plan's roadmap governs.
- The query compiler needs security review notes, and v0.7 proves a 250,000-row import and a
  50,000-record bulk update with undo in the scale org.
- Undoing a gift import keeps any gift with an issued receipt (ADR-0010, ADR-0024).

## Amendment, 2026-09-27: C-32 builder decisions (import matching and per-file values)

Builder decisions under plan Section 9.3, made while building C-32; the owner decisions above
stand unchanged. Canonical model R-IT8, R-IT9, R-IB14, R-IB15, R-IR8 and R-IJ3 carry the detail.

- **Choices are template attributes, not a document.** People keep `Matching_Rule__c` and gain
  `Person_Match_Field__c`; organizations gain `Organization_Matching_Rule__c` (Name exact,
  External ID) and `Organization_Match_Field__c`; `Several_Matches__c` holds the rule for
  several matches. An empty value keeps what a template did before C-32, except the rule for
  several matches, whose empty value is the owner's default (reject), so a template saved before
  C-32 rejects a row it once resolved to the earliest created record. That is the one
  behaviour change for existing templates, and the dry run shows every such row.
- **An empty external ID field means the first one.** A template that used the External ID
  rule before C-32 named no field and matched on the object's first external ID field; it still
  does. A chosen field must be an external ID or unique field the user may read, checked
  against describe when the dry run starts.
- **What counts as several.** The key is the one the importer already matches on (R-IB12): a
  shared email or surname and postal code narrowed to the row's first name where several hold
  it. Several records under the narrowed key, or under the shared key when the row gives no
  first name, or under an external ID, are several matches. Several holders of a shared key
  none of whom has the row's first name is not several matches: the person is created, as
  before, because taking one of them would rename somebody.
- **"Most recently changed" is Last Modified Date**, the higher identifier breaking a tie, so a
  file resolves the same way twice.
- **The dry run lists several-match rows either way** through a checkbox on the row
  (`Import_Row__c.Several_Matches__c`), shown as its own table beside the rejected rows.
- **Per-file values live on the batch** (`File_Values_JSON__c`), in the mapping document's
  defaults format, because they describe one file and must not come back with the next. The
  row's own value wins, then the file's, then the template's defaults.
- **Affiliation is resolved in Core** from the row's first person and organization, matched to a
  current affiliation between them, and journaled. Affiliations carry no batch tag; rather than
  add one, the journal gains a Created entry and a per-page `Created_Count__c`, and undo deletes
  journaled creations with the same checks as tagged ones. C-33 reuses the same entry for
  objects that can never carry a tag.
- **Staged rows are purged by a batch job after the commit's finish**, in system mode
  (ADR-0021), keeping rejected rows. A job, not the finish itself, because a large file's rows
  are more than one transaction may delete.
- **The checkbox work item is folded in** (contributor guide, CI work item 2): true is `true`,
  `yes`, `y`, `1`, `x`, `checked`, `on`, `t`; false is `false`, `no`, `n`, `0`, `off`, `f`, all
  ignoring case; blank changes nothing; anything else leaves the field unloaded and says so in
  the run log, once per field and value.

## Amendment, 2026-09-27: C-33 builder decisions (load one object)

Builder decisions under plan Section 9.3, made while building C-33. Canonical model R-IT10 to
R-IT12 carry the detail.

- **One template shape, two row models.** A template with `Target_Object__c` set loads one
  object (`ImportObjectLoader`); without it, the people and organizations model of Section 17 is
  unchanged. `Load_Operation__c`, `Load_Match_Field__c` and `Lookup_Not_Found__c` join the
  template; `Several_Matches__c` (C-32) also governs an upsert's key and every lookup. The
  mapping targets are `Record.` plus a field name, and a lookup column carries `lookupField`
  in the mapping document rather than a new attribute, because it belongs to the column.
- **Upsert is not `Database.upsert`.** The loader finds the record by the external ID in user
  mode, then inserts or updates, so the dry run can make the same decision, several matches
  can be refused, and the journal gets the values before. Upsert keys are external ID fields
  only (the platform's own meaning of upsert); lookups may also use unique and name fields.
- **Created records are journaled, not tagged.** An object Core does not own has no
  `Created_By_Import_Batch__c`, so every created record is a Created journal entry (C-32's
  mechanism) and undo deletes it with the same checks as a tagged record.
- **A repeated key is rejected wherever it falls.** The digest of each row's key is written to
  `Import_Row__c.Processor_Key__c` in the dry run and the commit (Core owns that field when no
  entity processor runs, which it never does for a one-object template), so a row repeating an
  earlier row's key is rejected identically whatever the chunk boundaries.
- **An unreadable value rejects the row** in a one-object load, where the people model skips
  the field and says so: a person row has other entities to load, a one-object row does not.
- **Protected fields are one reusable class.** `DataProtectedFields` builds the plan's list at
  run time from describe and the Rollup Definitions (all definitions, active or not), and C-35
  is meant to use the same class. The receipt and closed-period locks stay in their triggers.
- **The object list comes from describe**, filtered to objects the user can create or edit,
  that are queryable, and that are not bookkeeping, settings, metadata, events, big or external
  objects. Salesforce setup and security objects (users, groups, profiles, roles, permission
  sets and their assignments) are refused by name, because D-13 leaves permission management
  to Setup and an import would otherwise be a bulk permission tool. Core still names no
  standard object as a type (ADR-0013).

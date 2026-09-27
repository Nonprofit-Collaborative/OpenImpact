# ADR-0047: Data management runs in the org, compiles queries from a document, and is phased

**Status:** Accepted
**Date:** 2026-09-23 (amended 2026-09-27: C-32 and C-33 builder decisions, below)
**Source:** product owner decision (Brandon, 2026-09-23), plan Section 4.9, Section 6 and
Section 12 decision D-13; amends the import framework scope of C-14 and C-19
**Amended:** 2026-09-27, in place, by the owner's rule that data management decisions are
recorded here rather than in new ADRs: the query compiler's security review notes (required
before C-34 by plan Section 6, v0.7), and the builder decisions of C-34 (Find) and C-35 (bulk
update), each in its own section below and marked as such.

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

## Security review notes for the query compiler (C-34, amended 2026-09-27)

Written before C-34, as plan Section 6 (v0.7) requires. They cover `QueryDocument`,
`QueryCompiler`, `QuerySelector`, `FindController`, `SavedQueryService`, `BulkUpdateService`,
`BulkUpdateBatch` and the two Lightning components, `find` and `bulkUpdate`. A security
reviewer should be able to check every row of the table against the code.

**What crosses the trust boundary.** The browser sends a query document (JSON), a saved
query's name, a shared flag, a page cursor (the last record Id of the previous page), and, for
bulk update, up to five assignments and a confirmed count. The server never accepts SOQL text,
an operator it did not define, or a field or object name it has not found in the running
user's own describe results.

| Threat | How it is prevented |
|---|---|
| **SOQL injection through a name** (object, field, relationship, sort field) | Names are never copied from the document into a query. The compiler looks each one up in the running user's describe results (`Schema.getGlobalDescribe`, then the object's field map, then each relationship's `getRelationshipName`), refuses anything it does not find, and writes into the query the name describe returned (`getName()`, `getRelationshipName()`). A name that is not an identifier is refused before the lookup. A path is at most three parts: two relationships and a field. |
| **SOQL injection through a value** | Every value is a bind variable (`:b0`, `:b1`, ...) passed to `Database.queryWithBinds`, `Database.countQueryWithBinds` or `Database.getQueryLocatorWithBinds`, typed from the field's describe (text, number, date, date and time, true or false, record Id). The row limit, the page size and the export cursor are binds too. A LIKE pattern's own wildcards (`\`, `%`, `_`) are escaped before the pattern is bound. No value is concatenated into executed SOQL. |
| **Operators and filter logic** | Operators come from the fixed list of canonical model R-R2 plus the relative date periods, each mapped to a comparison in code. The logic string may hold only condition numbers, brackets, AND, OR and NOT, as `RollupFilterParser` already enforces, and each number must name a condition in the document. |
| **Object and field access** | Every read runs with `AccessLevel.USER_MODE`, so object permissions, field-level security and sharing apply to every row and every field. Before running, the compiler also refuses an object the user cannot read and a field (or a lookup on the way to one) they cannot read, with a sentence naming it, so a missing permission is a message, not a query exception. Filter and sort fields must be filterable and sortable in describe. |
| **Sharing** | All classes are `with sharing` and every record read and write is in user mode, so a record the user cannot see is never counted, returned, exported or updated. The one read outside sharing is the list of saved queries other people marked shared (see the C-34 decisions): it returns query documents, never records, and a shared document is compiled again as the person who opens it. |
| **Writes** | Bulk update saves with `Database.update(records, false, AccessLevel.USER_MODE)`. Each target field must be updateable for the user and not on the protected-fields list (`DataProtectedFields`, built at run time from describe and the Rollup Definitions). The only system-mode writes are the job record (`Import_Batch__c`) and its journal (`Import_Journal__c`), under ADR-0021. |
| **Row limits** | The grid returns at most 2,000 rows a request. Export is paged by the browser in record Id order, 1,000 rows a request, up to the export row limit setting (default 50,000). A count reads at most what one request can: never more than the rows the transaction has left, so a count cannot hit the query row limit. The export limit and the bulk update maximum are guards against accidental heavy work, not access controls: a person can only ever read what their own access allows. |
| **CPU and heap** | A document may name at most 50 fields, 20 conditions, 100 values in one list, 3 sort fields and 32,768 characters; values are at most 255 characters. Describe results are cached per transaction. Rows are flattened on the server into one map per row and nothing else is held. Bulk update runs in Batch Apex in chunks of the import chunk size (at most 200), and each chunk re-reads only its own records. |
| **CSV injection in the export** | The file is built in the browser. A text cell that begins with `=`, `+`, `-`, `@`, a tab or a carriage return is prefixed with an apostrophe, so a spreadsheet shows it as text and never runs it as a formula. Number, date and true or false columns are written as values. Every cell is quoted where it holds a comma, a quote or a line break, and quotes are doubled. The file is UTF-8 with a byte-order mark. |
| **Cross-site scripting** | Values are rendered only through Lightning base components (`lightning-datatable`, `lightning-formatted-*`), never as HTML. The generated SOQL is shown in a read-only text area. |
| **Permission to use the tools** | Every controller method checks its custom permission first (`Find_And_Export_Records`, `Bulk_Update_Records`). Neither grants access to any record. |
| **Confirmation and replay** | A bulk update starts only with a confirmed count; the server counts again and refuses when more records match than were confirmed, or than the maximum per bulk update allows. The job reads at most the confirmed number of records, and each chunk updates only records that still match the filter when it runs. |

**What is displayed is not what runs.** The SOQL shown to the administrator is rendered from
the same compiled document, with each bound value written out as a literal (text quoted and
escaped) so it can be copied into another tool. That text is display only: it is never sent
back and never executed.

## C-34 builder decisions (Find, amended 2026-09-27)

1. **One query document for Find, saved queries and bulk update** (`QueryDocument`, canonical
   model Section 17B): object, fields (paths of at most two relationships), an R-R2 filter,
   up to three sort fields and an optional row limit. R-R2 is extended, not replaced: a
   condition's field may be a parent path, and a date or date and time condition may carry a
   `relative` period (today, this month, last month, this year, last year, last N days, next N
   days) instead of a value. A relative period is worked out when the query runs, in the
   running user's time zone, and bound as two dates, so a saved query always means "now".
2. **Saved queries are private to their owner by default and shared by a flag.**
   `Saved_Query__c` has private sharing, and its owner edits and deletes it in user mode. A
   query marked shared is listed to every holder of `Find_And_Export_Records` by
   `SavedQuerySharedReader`, a `without sharing` class that reads only saved queries with the
   shared flag set, and only their name, object, owner and document. It is the one read in this
   feature that crosses sharing, and it is recorded here as the ADR the contributor guide asks
   for: it returns a definition the owner chose to publish, never a record, and opening a shared
   query compiles it again as the person opening it, so each person sees only what their own
   access allows. Apex managed sharing to all internal users was the alternative; it needs the
   Group object, which is not on the allowlist, and share rows to keep in step with the flag.
3. **Relationships that can point at more than one kind of record are not followed** in v1
   (for example an owner that may be a user or a queue); their Id can still be shown.
4. **Export follows the query's filter and row limit, in record Id order**, whatever sort the
   grid shows, because paging by the last Id is the only paging that neither skips nor repeats
   a row while others edit. The header row uses the column labels the grid shows.
5. **Export row limit** is a new setting, `Export_Row_Limit__c`, default 50,000, accepted from
   1 to 100,000, in the Import section of the settings console.
6. **Permission set.** `Find_And_Export_Records` is in Barn Admin and in a new set, Barn Find
   and Export, assignable alone, which grants the Find tab, the controller and access to saved
   queries, and nothing else.

## C-35 builder decisions (bulk update, amended 2026-09-27)

1. **A bulk update is a data job, and runs as the person who started it.** `BulkUpdateService`
   checks the document and up to five changes as that person, counts the matching records in
   user mode, and refuses to start when more match than they confirmed or than the maximum
   per bulk update allows (`Bulk_Update_Max_Records__c`, default 50,000, accepted from 1 to
   50,000). It then writes an `Import_Batch__c` with `Operation__c` Update, the document, the
   changes and the confirmed count in `Operation_JSON__c`, the undo deadline stamped from the
   import undo setting, and no staged rows; the job record is written in system mode under
   ADR-0021. `BulkUpdateBatch` reads at most the confirmed number of records in Id order, and
   each chunk reads its records again with the filter, so a record that no longer matches is
   left alone and counted. Saves are `Database.update(records, false, AccessLevel.USER_MODE)`.
2. **A count never exceeds the rows one request may read.** A count reads at most the rows the
   transaction has left, less a margin; a preview or start that cannot tell whether more
   records match than it may change is refused with a sentence asking for a narrower query,
   never guessed. In practice a single bulk update tops out a few hundred records under the
   50,000 maximum.
3. **The journal is the import journal.** Each chunk writes one commit page (canonical model
   R-IJ1) holding an Updated entry per record it changed, with the value before and after for
   each field that changed, and a Failed entry per record the platform refused, with the
   platform's reason. A record whose fields already held the new values is not saved and not
   journaled. The undo is the import undo (`ImportUndoService`, `ImportUndoBatch`): for a job
   whose operation is Update it runs the restore pass only, and it restores any object the
   journal names that describe still finds, where an import restores only people,
   households and organizations. The count an undo shows is the job's updated records.
4. **Protected fields are worked out at run time** by `DataProtectedFields`, from describe
   (formula, auto-number, fields Salesforce sets, fields the person may not edit, custom
   settings, metadata, events and sharing, history and feed objects), from the Rollup
   Definitions (every target field, active or not), and from a short list of what the package
   computes (household name and greetings, member count, primary affiliation, every rollup
   last calculated time, the import batch tag, the sample data key and a saved query's
   document) and of its bookkeeping objects (data jobs, import rows and templates, the
   journal, the error log, settings, setting changes, automation settings, rollup
   definitions, duplicate dismissals, and Giving's receipts, receipt runs and receipt number
   sequences, named as text so Core holds no reference to them). An organization's own name
   is protected with the household's, because both are the Account name. Fields locked by an
   issued receipt are refused by the receipt lock triggers, which still run, and those records
   are journaled as Failed. C-33 built the same class in parallel; the two are one class,
   whose lists are the union of both, so bulk update also refuses Salesforce setup and
   security objects (C-33 decisions below). Bulk update asks `objectReason` and `fieldReason`
   (canonical model R-IB17), a one-object import `objectRefusal` and `isProtected` (R-IT12).
5. **Compatible copies.** A field may be copied into another of the same type; any text,
   email, phone, web address or picklist into a text field; any number into a number field;
   and a lookup into a lookup that can point at the same kind of record. A value too long for
   its target fails that record, journaled with the reason.
6. **Permission set.** `Bulk_Update_Records` is in Barn Admin and in a new set, Barn Bulk
   Update, assignable alone, which grants the Bulk Update and Data Jobs tabs, the controller,
   read access to data jobs and saved queries, and nothing else. The shared saved query list
   (C-34 decision 2) is open to it as well, so a person who may bulk update and not build
   queries can use a query a colleague shared.
7. **Data Jobs.** `Import_Batch__c` is labelled Data Job, with a Data Jobs tab in the Hub app;
   its API name is unchanged, as the plan requires.

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

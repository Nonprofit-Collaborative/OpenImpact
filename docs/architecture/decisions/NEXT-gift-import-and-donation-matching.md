# ADR-NEXT: Gift import through the entity processor seam, and donation matching

**Status:** Accepted (builder decision)
**Date:** 2026-09-24
**Source:** builder decision under plan Section 9.3, features G-23 and G-24 (plan Section 4.9,
"Row semantics", "Donation matching (Giving)"); refines ADR-0014, ADR-0017 and the undo rules
of C-19 (canonical model R-IB9, R-IR6)

## Context

Core's importer offers the gift, allocation and soft credit columns of a row to an
`ImportEntityProcessor` class named `GiftImportProcessor`, found with `Type.forName` (R-IR6,
ADR-0017). No package ships one, so those columns are staged and never loaded, although a
generic gift list template ships. G-23 builds it in Giving and G-24 adds donation matching.

Building it showed that the seam, as C-14 left it, cannot carry a gift import:

1. The processor was called before Core wrote the resolved people and organization onto the
   rows, although its contract says the rows carry them, and it had no way to say what it did
   with a row: Core then overwrote the row's status from its own work alone, so a row whose
   gift failed would still count as created.
2. Core said "these columns were not loaded" in the run log whenever the mapping named a gift,
   whether or not a processor loaded them.
3. Undo (R-IB9) leaves "what Core cannot name to its owner", but there was no way for the owner
   to take part: Core's undo would delete an imported person and leave their gifts pointing at
   nobody, and nothing kept a receipted gift. ADR-0010 and ADR-0024 make a receipted gift
   immutable, and a person holding `Override_Receipt_Lock` can delete one.
4. The plan asks for per-template donation matching values and per-file control totals.
   ADR-0014 records that a package cannot add fields to another package's custom object, so
   Giving cannot put them on `Import_Template__c` or `Import_Batch__c`.

The plan is silent on several choices a builder has to make: which record on a row is the
donor, whether an existing gift found by external ID is updated, what "amount within
tolerance" is compared with, and which installments count as open.

## Decision

**The seam.** `ImportEntityProcessor` (Core, `@NamespaceAccessible`, not `global`) has four
methods. The interface had no implementation, so it is rewritten rather than extended.

- `targets()` names the columns the processor loads, with their labels, so the column picker
  offers them only where they load.
- `resolve(batch, template, rows, entitiesByRowId, dryRun)` is called once per chunk after
  Core has resolved the organization, household and people and written them onto the rows,
  with each row's values grouped by entity with the template's defaults applied. A row Core
  rejected arrives with Status Rejected and is left alone. The processor reports per row by
  setting Status (Rejected with Error Message, Created, or Matched) and the Gift and Soft
  Credit identifiers; Core folds that into the row's final status: a rejection wins, a
  creation counts the row Created. It returns an `ImportEntityResult` carrying a run log note
  and the total of the file's gift amounts in the chunk, for control totals.
- `taggedObjects()` names the objects it tags with Created By Import Batch.
- `reasonsToKeep(batchId, type, ids)` says why records must survive an undo, for the
  processor's own objects and for Core's people and accounts.

The class is found by namespace and name, the pattern `SampleDataModules` uses, not by an API
name prefix.

**Undo.** Core deletes the processor's tagged records itself, in a pass per tagged object
before the people, with the same one-batch filter, the same "edited or gained since" checks
and the same user-mode delete as its own records (R-IB8, R-IB9), and adds the processor's
reasons to keep. Core names no Giving object: the types come from the processor and the
queries are built from describe. The Giving processor keeps a gift that carries a receipt
number, has a receipt record of any status, or falls on an issued year-end statement for its
donor and year, and journals the reason; and it keeps a person, household or organization
that a kept gift, or a soft credit on one, still names. A person is therefore never deleted
out from under a receipted gift.

**Where the values live.** Donation matching's three per-template values (behaviour, date
window, amount tolerance) are fields on Core's `Import_Template__c`, and the per-file control
totals (expected rows, expected amount, and the amount the dry run read) are fields on Core's
`Import_Batch__c`. They are scalars, never references, which ADR-0014 permits; the precedent
is `Default_Fund__c` on Core's settings. The org-wide default window and tolerance are Giving
settings, in the console's Import section beside the other import settings.

**Control totals.** Optional, per file, entered in the wizard. The dry run compares the
expected rows with the rows in the file and the expected amount with the total of the file's
gift amounts (every row that carries a readable amount, rejected or not, because the check is
whether the file is the one on paper). A mismatch is said in the run log and a commit is
refused until a dry run matches.

**Gift rows, where the plan is silent (conservative choices):**

- **The donor** is the row's first person when it has one, otherwise its organization. A
  `Gift.Donor` column or default naming `Contact1`, `Organization` or `Household` overrides it, because
  an organization's gift file often lists a contact person too.
- **Every imported gift is created with Status Received**, through the path gift batch entry
  and the Connect API use: a user-mode insert, then `GiftService.applyChosenFunds` for a
  single fund. A split across funds is inserted with the gift's default allocation suppressed
  and all its allocations in one save, because the allocation total rule (R-GA1) refuses any
  intermediate state.
- **A row's gift, allocations, soft credit and tribute are saved together or not at all.**
  When a later part fails, the gift is deleted and the row rejected with the reason.
- **An existing gift found by External Id is the row's gift and is not changed.** The row is
  Matched. Updating it would need a journal of gift values and would collide with the receipt
  lock; the plan's purpose for the match is idempotence.
- **An in-kind gift has no amount** (R-G12, the gift's own validation): an empty amount on an
  In-kind row reads as 0, and any other amount rejects the row in the dry run.
- **An inactive fund is accepted.** A migration of old gifts names funds that have closed.
- **Dates** are read as `YYYY-MM-DD`, then in the running user's locale; an unreadable date
  rejects the row rather than defaulting to today.
- **Payment methods** are matched to the gift type picklist ignoring case, with a short list
  of common words ("credit card", "cheque", "bank transfer"); anything else rejects the row
  and names the accepted values.

**Donation matching, where the plan is silent:**

- **External ID is identity, not matching**, and applies under Always create, Match or create
  and Match only: re-running a file never duplicates a gift. Under Never match an existing
  external ID rejects the row, since the administrator said nothing should match.
- **An open installment** has Status Scheduled, Overdue or Partially paid, on a commitment that
  is Active or Paused.
- **The same donor** is a commitment whose donor contact or donor account is the gift's donor,
  or whose household is the donor's household.
- **The amount** is compared with the installment's Expected Amount, not what is left to pay:
  Paid Amount is a rollup that can lag, and a comparison that depends on timing would make the
  dry run disagree with the commit.
- **Within one run**, an installment an earlier row claimed is not offered to a later one,
  across chunks too: the processor carries the claimed installments in the state Core's
  import batch holds between chunks (`ImportEntityProcessors.carriedState`), so a dry run
  reports what the commit will do.
- **A row repeating an earlier row's external ID in the same file** is that row's gift, under
  every behaviour: under Never match only a gift that already existed before the file rejects
  the row.
- **An organization donor has no household**, so only its own commitments are candidates. A
  donor the import would create has none, so in a dry run Match only rejects that row.
- **Precedence** is the template's value, else the org setting, else the shipped default (7
  days, exact amount), applied in Apex (ADR-0035). An empty template value means the setting.

## Alternatives considered

- **Keep the interface and pass results through the row fields only.** Rejected: the control
  totals and the undo need methods, and there is no implementation to keep compatible.
- **Let Giving delete its own records inside the undo job.** Rejected: it would duplicate
  Core's "edited or gained since" checks, and the two would drift.
- **Giving extension fields on the import objects.** Rejected by ADR-0014's constraint.
- **Template values in the mapping document's defaults.** Rejected: the wizard rewrites the
  column document on every run and the defaults document is not edited in the wizard, so a
  value there could not be set by Maria.
- **Update a gift matched by External Id from the row.** Rejected for now (above). A later
  feature can add it with a journal of gift values.
- **Compare the amount with the unpaid remainder of the installment.** Rejected (above).

## Consequences

- Core carries five scalar fields that only matter with Giving installed. The wizard shows
  the amount control total and the donation matching block only when a gift processor is
  installed, so an org without Giving never sees them.
- The dry run cannot run gift triggers, so a platform validation (for example an in-kind gift
  without a description) is reported by the commit, not the preview. The preview checks
  everything the processor can check without saving.
- Core carries one more piece of processor contract: `ImportEntityProcessors.carriedState`,
  a string the import batch hands from chunk to chunk, so claimed installments are remembered
  across chunks and a dry run reports what the commit will do.
- One more class for the security review to read against ADR-0021:
  `GiftImportIntegritySelector` is `without sharing` and reads `WITH SYSTEM_MODE`. Its reads
  decide, and are never shown: whether a gift with this external ID already exists (a gift
  the importing user cannot see must still stop a second copy, which the platform would refuse
  anyway with a message naming nothing), and what an undo must keep (a receipt or statement the
  undoing user cannot see must still keep its gift). Funds, appeals and installments stay
  within the user's sharing: what the user cannot see, the user cannot allocate to or pay.
- Undo keeps more than it did: people who gave a receipted gift stay. That is the point.

# ADR-0029: Which Health Check findings get a fix button

**Status:** Accepted
**Date:** 2026-09-08
**Source:** builder decision under plan Section 9.3, for C-21 (plan Section 5.1); extends ADR-0006 and ADR-0021

## Context

Health Check v1 (C-11) tells Maria what is wrong. C-21 lets her put it right from the same
screen. The code for that is small. The decision is which findings get a button, and it has to
be written down before any button exists, because a Fix button on a finding whose remedy is
ambiguous is worse than no button at all: it turns a report she reads into an action she trusts,
and the trust is spent the first time a button does something she did not mean.

Two things about this codebase sharpen the question. First, package owned defaults are
materialized rather than shipped as records (ADR-0006): rollup definitions, automation switch
rows and import templates are created from custom metadata the first time some page asks for
them, so an org where nobody opened that page is missing rows it is supposed to have, and the
post install script says in its own header that its second step, assigning the Nonprofit Admin
role, can fail while the platform is still calculating the permission set group. These are
states that are definitionally wrong, that Health Check can already see, and that have one
correct end state. Second, this repository has already lost 440 contacts and 225 accounts to an
unguarded cleanup query, so the cost of a fix that deletes is not hypothetical here.

## Decision

A finding gets a Fix button only when all six of these hold. If any one fails, the finding stays
a finding: it says what is wrong, and where a person has to decide, it links to the page where
they decide it.

1. **One right answer, and Health Check can name it.** The end state follows from the finding,
   not from what the organization meant. "Which rollups does this package ship" has one answer.
   "Who should administer Open Impact" does not.
2. **Package owned configuration only.** A fix writes settings keys this package defines, rows
   materialized from this package's own shipped metadata, and assignments to this package's own
   roles. It never writes a constituent, a gift, an address, or any amount.
3. **Create or set, never delete, never overwrite.** A fix creates rows that are missing, or
   sets a package owned setting to the one value the finding names. **No fix deletes a record,
   whatever the finding says.** No fix replaces a value an administrator chose.
4. **Pressing it twice is pressing it once.** Idempotence is by construction, not by care: the
   framework re-reads the org and builds the preview again inside the apply call, and does
   nothing at all when that second preview is empty.
5. **It says what it will do before it does it, counted from this org.** A preview names the
   rows or the people it will touch and how many, and the button that commits is a second click.
   Afterwards the fix reports what it actually did, and the report is re-run underneath it.
6. **All or nothing, and a failure is visible.** One transaction, rolled back to a savepoint on
   any exception, written to the Error Log through `ErrorLogger`, and returned to the person as
   a sentence rather than a silent no-op.

Six fixes pass: set the coexistence mode detection recommends, switch household membership to
the junction, create the missing packaged rollup definitions, create the missing automation
switch rows, create the missing packaged import templates, and finish the Nonprofit Admin role
assignment for the people who already hold the Nonprofit Admin permission set.

These findings are refused a button and keep their link: nobody holds the Nonprofit Admin role
(condition 1, the organization chooses who), users cannot see the app (condition 1), automation
is paused (condition 1: only the person running the bulk load knows whether it should resume),
new entries in the Error Log (condition 1), multi currency and the Connect module note (there is
nothing to press). Automation Setting rows left behind by an upgrade that no longer ships them
are reported as information and given no button, because the only remedy is a delete and
condition 3 is absolute; they are harmless, since nothing runs an automation with no registry
row behind it.

## Alternatives considered

- **A confirmation dialog on every fix and no rule.** Rejected: a confirmation prompt asks Maria
  to make the judgment the button was supposed to save her, on the least information she will
  ever have about it, and it is the mechanism people learn to click through.
- **Let each finding declare its own fix ad hoc.** Rejected: that is how a delete arrives later,
  in a feature branch, defended on the merits of one finding. The rule is what refuses it.
- **A fix that deletes the stale rows, guarded by a preview.** Refused under condition 3. A
  guarded delete is still a delete written by an agent that cannot run it against an org, and
  the rows cost nothing to leave.
- **Restore the shipped defaults from a scheduled job instead of a button.** Not chosen: it hides
  a change nobody asked for. The finding plus the button keeps the org's state visible and the
  change deliberate.

## Consequences

- Every fix reuses an existing service (`CoexistenceService`, `RollupService.ensureDefaults`,
  `AutomationControl.ensureDefaults`, `ImportTemplateService.materializeDefaults`,
  `AccessService.assignRole`), all of which were already idempotent and already gated. C-21 adds
  no new write path to package data and no new exception to ADR-0021: the system mode writes it
  reaches are the ones the Rollups page and the install script already make, gated at
  `HealthCheckController` on `Manage_Nonprofit_Settings` exactly as `RollupController` gates
  restoring the shipped rollups.
- The Nonprofit Admin role fix is defensible only while `Nonprofit_Admin_Group` contains exactly
  the `Nonprofit_Admin` permission set, so that granting the role widens nobody's access beyond
  the permission set they already hold. If a second set is ever added to that group, this fix has
  to be re-examined or withdrawn.
- That fix writes a setup object, and the platform refuses setup and ordinary DML in one
  transaction, so it is the one fix the framework does not record as a Setting Change row. It is
  visible instead on the Access page, which is where a role assignment belongs.
- A seventh fix cannot be added by writing one, only by passing the six conditions in review.
  The reviewer checklist question is: which condition does it satisfy, one at a time.

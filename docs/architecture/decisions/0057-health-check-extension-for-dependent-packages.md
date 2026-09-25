# ADR-0057: A Health Check extension seam lets a dependent package add findings without Core depending on it

**Status:** Accepted (builder decision)
**Date:** 2026-09-25
**Source:** ADR-0053's recorded follow-up ("A Health Check finding for unposted gifts in a
closed period... Not built: the plan does not ask for it, and a new Core finding naming a
Giving rule runs against C-29. Recorded as follow-up work"); builder decision under plan
Section 9.3; amends ADR-0021
**Amended by:** ADR-NEXT on the Opportunity mirror (`HealthCheckExtensions` also looks up
Connect's `ConnectHealthCheckExtension`)

## Context

ADR-0053 (G-20) locks a gift that is in the books (a counting status, ADR-0022) and either
posted or dated on or before Books Closed Through. It named a gap on purpose: an
administrator who closes a period without exporting and marking every gift posted has no way
to find those gifts from Health Check, and ADR-0053 recorded why it was not built there and
then: "a new Core finding naming a Giving rule runs against C-29" (plan Section 4.1, Core
carries no nonprofit wording).

`HealthCheckService` (C-11, ADR-0039) is the one report an administrator reads; it lives in
Core. Giving cannot write to it directly, because Giving depends on Core and Core may not
depend back (ADR-0014). Core already reaches across this same boundary once, in
`ReceiptGapSelector`: it counts `Receipt__c` rows by describing the object dynamically and
running dynamic SOQL, because the count itself is a single field comparison. This finding is
different in kind: "in the books, and dated in a closed period, and not posted" is
`GiftPostingLock`'s rule, expressed in `BOOK_STATUSES`, `TYPE_IN_KIND` and `closedThrough()`.
Re-deriving that rule inside Core, even through dynamic SOQL, means keeping two copies of a
Giving rule in step, which is exactly the coupling C-29 exists to prevent, and is the reading
ADR-0053 rejected.

Core already has a mechanism for the opposite shape of problem: `ImportEntityProcessor`
(R-IR6, ADR-0017) is an interface Core defines and a dependent package implements, found at
runtime with `Type.forName` under a known class name. Core never learns what the class does;
it only learns that a class of that name, implementing that interface, may or may not be
installed.

## Decision

Core gains a second instance of that same mechanism, for Health Check:

- **`HealthCheckExtension`**, an interface in Core: one method, `findings()`, returning a list
  of `HealthCheckService.Finding`. A package that implements it decides everything about what
  it reports and to whom; Core never inspects the list beyond folding it into the report.
- **`HealthCheckExtensions`**, a resolver in Core, the same shape as `ImportEntityProcessors`:
  it looks up a class named `GivingHealthCheckExtension` by namespace and name with
  `Type.forName`, instantiates it, and returns it if it implements the interface, or `null` if
  the class is absent, cannot be built, or is the wrong shape. Looked up once per transaction.
  `@TestVisible` overrides (`extensionOverride`, `noneForTest`) let Core's own tests assert the
  isolation behavior without a real Giving package to resolve.
- **`HealthCheckService.run()`** calls `HealthCheckExtensions.find()` after its own checks and
  folds the extension's findings into the one list it returns, isolated exactly the way one
  failing check already is: an extension that throws becomes a single `check_failed_...`
  finding, logged to the Error Log, and the rest of the report stands.
- **`GivingHealthCheckExtension`**, in Giving: `@NamespaceAccessible`, implements the
  interface, and does nothing but delegate to `HealthCheckGivingChecks.findings()`, the class
  that actually asks the question (grouped the way ADR-0039 groups Core's own checks, so a
  second Giving check has an obvious home). It reads `GiftPostingLock.BOOK_STATUSES`,
  `TYPE_IN_KIND` and `closedThrough()` directly, the same constants the lock itself enforces
  by, so the finding can never disagree with what the lock actually did. It is asked only when
  `HealthCheckService.canManageSettings()` is true, matching every other Settings-category
  check that reads organization-wide state.

The one finding this ships: gifts with a counting status (Received, Refunded or Written off,
ADR-0022) and a type other than In-kind, dated on or before Books Closed Through, that
`Accounting_Posted_At__c` is still empty on. Capped at 1,000 (`countCap + 1`, reported as
"More than 1,000"), with the first five linked, the same shape `HealthCheckHouseholdChecks`
already reports orphan records in. The fix points at `SettingSections.GIVING`, the Accounting
Periods page's own section, and the detail names both ways out: mark the gifts posted, once
they are genuinely in an export, or move Books Closed Through back (which needs Override
Posting Lock and is logged, per ADR-0053).

## Amendment to ADR-0021: an explicit sharing exception for a read that reaches a user

ADR-0021's last condition keeps two kinds of read apart: a read that computes a package-owned
value may run in system mode, but "reads that reach a user... stay in user mode." The count and
the linked gifts behind this finding reach a user directly, an administrator reading Health
Check, and still have to run without sharing to be correct, which is the case that line was
written to rule out. This amendment records why this one read is an exception rather than a
violation.

- **Why.** Gift__c ships Private sharing (R-G14). A count of gifts locked and unposted in a
  closed period is a fact about the organization's books, not about which gifts the viewer
  happens to own or share; an administrator who owns only some of the org's gifts would
  otherwise see a Health Check finding that silently under-counts, which is a wrong answer, not
  a narrower one. `WITH SYSTEM_MODE` alone does not reach this: it lifts field and object
  security, but record sharing is decided by the querying class's `with sharing`/`without
  sharing` keyword, not by the query's security mode clause, so the read has to live in a class
  that gives up sharing.
- **What is exposed.** `HealthCheckGivingSelector` exposes exactly two shapes of answer, both
  capped: `countUnpostedInClosedPeriod` returns an integer, capped at the finding's own cap plus
  one so the report can say "more than"; `unpostedInClosedPeriod` returns at most five gifts,
  each carrying only `Id`, `Name` (the gift's AutoNumber) and `Gift_Date__c`, to link a few
  examples. No donor, amount, payment reference or any other field crosses the sharing boundary,
  and nothing here is ever returned to a viewer who may not manage settings.
- **The gate.** `HealthCheckService.canManageSettings()` is asserted inside
  `HealthCheckGivingSelector` itself, not only by its caller (`HealthCheckGivingChecks`), so a
  future caller cannot reach this without-sharing read by skipping the check;
  `HealthCheckGivingSelectorTest.aViewerWithoutManageSettingsGetsNothingEvenCalledDirectly`
  proves it directly, bypassing `findings()` entirely.

## Alternatives considered

- **A Core finding, reading `Gift__c` dynamically the way `ReceiptGapSelector` reads
  `Receipt__c`.** Rejected: this finding is not one field comparison, it is "in the books,
  dated in a closed period, not posted," which is `GiftPostingLock`'s rule restated. A second
  copy of that rule in Core drifts from the first the next time the lock's definition of "in
  the books" changes, and ADR-0053 already named this shape of finding as the one that runs
  against C-29.
- **A Giving-only page, outside Health Check, on Accounting Periods.** Considered because it
  needs no Core change at all. Rejected: ADR-0053 called this "a Health Check finding" by
  name, Health Check is the one report an administrator is told to read for anything wrong
  with the org, and a second, separate warning surface for one package's findings is a worse
  outcome for the reader than the small seam this ADR adds.
- **A registry custom metadata type, the way `Automation_Registry__mdt` drives trigger
  dispatch.** Rejected: one extension point, one dependent package that will ever implement
  it in this product's lifetime (Giving), and a registry buys nothing a single well-known
  class name does not already give, at the cost of a new object.

## Consequences

- A second dependent package that wants to add Health Check findings implements the same
  interface under its own class name; today only `GivingHealthCheckExtension` is looked up,
  so `HealthCheckExtensions.CLASS_NAME` would need a list rather than one constant if that
  ever happens. Not built ahead of the need.
- Core's test suite exercises the isolation behavior (installed, absent, throwing) entirely
  through `@TestVisible` overrides, the same as `ImportEntityProcessors`; it asserts nothing
  about what Giving's extension actually says, which stays Giving's tests' job
  (`HealthCheckGivingChecksTest`, `GivingHealthCheckExtensionTest`).
- `docs/admin-guide/health-check.md` gains one row; nothing about how Health Check is reached
  or read changes.
- ADR-0021 carries an "Amended by" line pointing here: its own reads-that-reach-a-user
  restriction has one named exception, this finding's selector, which is why the exception is
  written up above rather than folded quietly into ADR-0021's own text.
- The exception is scoped to `HealthCheckGivingSelector` only. Any other read that bypasses
  sharing to reach a user, including a future Health Check extension, needs its own ADR; it
  cannot cite this amendment in place of one.

# ADR-0021: System-mode writes for package-owned data

**Status:** Accepted
**Date:** 2026-09-08
**Source:** builder decision under plan Section 9.3 (platform limitation); refines plan Section 4.13 and ADR-0006

## Context

Plan Section 4.13 requires Apex to run `with sharing` and to check CRUD and FLS through user
mode unless a documented reason exists. Four kinds of write cannot meet that rule for the users
the product is built for:

1. **Protected hierarchy custom settings** (`Nonprofit_Settings__c`, `Giving_Settings__c`).
   Subscriber administrators cannot be granted field access to a protected setting, so a
   user-mode upsert of the org default fails for everyone outside a System Administrator
   profile. Maria, who holds only the packaged permission sets, could not save a setting.
2. **Package-owned computed fields** (household Name, Formal Greeting, Informal Greeting,
   Member Count, and later rollup targets). A user who may edit a Contact but lacks edit
   access on the household's computed fields would otherwise get a raw DML error on an
   ordinary save, or leave the household with a placeholder name.
3. **Error Log entries.** A log must be written even when the running user has no create
   access on `Error_Log__c`, and it must survive the rollback of the transaction it documents.
4. **Rollup writes by the vendored engine** (ADR-0015): computed totals must be correct
   regardless of the running user's sharing.

## Decision

Each of these writes goes through a small, dedicated writer class that runs `without sharing`
with `AccessLevel.SYSTEM_MODE`, carries a header comment naming this ADR and the reason, and
meets all of these conditions:

- It is reached only after the caller has enforced the relevant custom permission
  (`Manage_Nonprofit_Settings` for settings) or after the platform has already authorized the
  user's own record write (a Contact save that triggers household upkeep).
- Its inputs are validated before the call (settings values against `Setting_Definition__mdt`,
  computed household values produced by package code, log fields from exceptions the package
  caught) and no user-typed text reaches a query or a dynamic field name.
- It writes only fields the package owns; nothing else in the transaction is elevated.
- Reads that reach a user, and the audit trail (`Setting_Change__c`), stay in user mode. A
  read whose only purpose is to compute one of these package-owned values may run in system
  mode for the same reason as the write it feeds, provided the class says plainly which of
  its reads are upkeep and which are shown to somebody (`HouseholdSelector` does).

The writer classes in v0.1 and v0.2: `SettingsWriter`, `AutomationSettingsWriter`,
`HouseholdWriter`, `ErrorLogWriter` and `ErrorLogEventHandler`, and the vendored rollup
engine's updater classes (documented in `packages/core/vendor/apex-rollup/VENDOR.md`). A writer
may narrow `without sharing` to `with sharing` where its work must never cross sharing, and
must say so in its header: `HouseholdWriter` does, because household upkeep must not create,
rename or delete a household the running user cannot see.

## Alternatives considered

- **Grant object and field access in the packaged permission sets.** Impossible for protected
  custom settings, and insufficient for computed fields because a user editing a Contact may
  hold no packaged set at all.
- **Unprotected custom settings.** Would expose engine and package settings in Setup, contrary
  to the console-only rule (plan Section 2.3) and ADR-0006.
- **Skip the write when the user lacks access.** Wrong totals and missing names are worse than
  an elevated write of package-owned data (plan Principle 2).

## Consequences

- Security review reads each writer class against this ADR; every new writer must cite it and
  satisfy the four conditions above.
- CI cannot enforce the conditions mechanically; the reviewer checklist (plan Section 9.4) asks
  whether any new `without sharing` or `SYSTEM_MODE` usage is one of the listed writers.
- Feature branches that cited ADR-0006 or ADR-0017 for these writes are repointed to this ADR
  at integration.

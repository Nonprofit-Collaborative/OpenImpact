# ADR-0014: Core holds Giving record identifiers, not lookups

**Status:** Accepted
**Date:** 2026-09-07
**Source:** plan Section 9.3 (platform limitation), affecting plan Sections 4.8 and 4.9

## Context

Plan Section 4.9 specifies `Import_Row__c` with "a fixed set of resolved lookups such as
`Household__c`, `Contact1__c`, `Contact2__c`, `Organization__c`, `Gift__c`". Plan Section
4.8 specifies a Setup Assistant step that picks a default fund and a default appeal, and
the natural home for those choices is the `Nonprofit_Settings__c` hierarchy custom
setting.

Both put a reference to a Giving object inside a Core object. The package graph runs the
other way: Giving depends on Core (ADR-0003), so Core is installed first and can be
installed alone. A managed package cannot hold a lookup to an object that does not exist
when it is installed, and a second-generation package cannot add fields to another
package's custom object, so Giving cannot supply the missing lookups later either.

Two more constraints narrow the options. Custom settings support no lookup field type at
all, only scalar types, so the default fund and appeal could not be lookups even within
one package. And plan Section 4.2 forbids a Core reference to anything that is not always
present.

## Decision

**Where a Core object or setting must point at a Giving record, it stores the record
identifier as text, and the Giving package resolves it.**

- `Import_Row__c` carries `Gift_Id__c` and `Soft_Credit_Id__c` as Text(18) instead of
  lookups. Its Core-owned references (`Household__c`, `Contact_1__c`, `Person_1_Account__c`,
  `Contact_2__c`, `Person_2_Account__c`, `Organization__c`) stay real lookups.
- `Nonprofit_Settings__c.Default_Fund__c` and `Default_Appeal__c` hold record identifiers.
  The settings console shows a fund picker and an appeal picker, rendered by Giving, so
  the administrator never sees or types an identifier.
- `Rollup_Definition__c` already names its source and target objects and fields as text
  (canonical model R-R7), so the rollup engine drives Giving objects with no change.

The reverse direction is unrestricted: Giving holds real lookups to Core objects, which
is why `Gift__c.Created_By_Import_Batch__c` is a lookup to `Import_Batch__c`.

## Alternatives considered

- **Move Import Row into the Giving package**: the importer is a Core feature that must
  work in an org with no Giving installed (plan Section 4.9), so the staging object cannot
  live in Giving.
- **Put every object in one package**: rejected in ADR-0003 because an unused module must
  leave nothing in the org.
- **A polymorphic lookup**: the platform offers these only on standard objects that
  already have them, not as a field type we can create.
- **Store nothing and re-resolve by external id on every read**: slower, and it loses the
  link when the source file's identifiers are reused.

## Consequences

- The two import links are not clickable in the standard record UI and cannot be reported
  on through a relationship. The import results screen resolves and links them, which is
  where an administrator actually looks.
- Nothing cascades: deleting a gift does not clear the identifier on the staged row. The
  undo feature (C-19, v0.5) resolves identifiers before it acts and ignores those that no
  longer exist.
- Referential integrity for these two links is the Giving package's job, not the
  platform's, and its tests own that.
- The canonical model records the deviation at the point of use (rules R-IR2 and R-F4), so
  a contributor reading the field list sees why the type is text.

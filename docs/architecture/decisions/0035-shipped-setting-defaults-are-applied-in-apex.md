# ADR-0035: A setting that ships switched on is switched on in Apex, not by its field default

**Status:** Accepted
**Date:** 2026-09-09
**Source:** ADR-0006 (settings storage), plan Section 7.2, defect found by the first org run of C-15

## Context

Every Core setting lives on `Nonprofit_Settings__c`, a protected hierarchy custom setting
(ADR-0006). A checkbox field there can declare `<defaultValue>true</defaultValue>`, and the
console, the field's help text and the admin guide all read that declaration as the answer to
"how does this ship?".

Apex does not. `Nonprofit_Settings__c.getOrgDefaults()` on an org that has never saved its
settings returns a materialized record whose checkboxes are all `false`: not null, and not the
declared default. A feature guarded by such a setting therefore does nothing on every fresh
install, and does it silently, because "the org switched this off" is a legitimate answer that
raises nothing and logs nothing.

C-15 shipped that way. `Relationship_Auto_Reciprocal__c` declares a default of true, the admin
guide says "leave it switched on, which is how it ships", and `RelationshipService` treated
anything that is not an explicit false as on. The first Apex run this project ever had, against
a real org, returned thirteen failures across four test classes, every count exactly half of
what was expected: the validation half of the feature ran and the half that writes the other
side of a relationship never ran at all. No offline check could see it. The field metadata was
right, the Apex compiled, and the assumption that joined them was written in a comment.

There is a second half to the same trap. The console writes only the keys it was given, so the
record created the first time an administrator saves anything at all would carry a `false` for
every checkbox nobody touched, and would switch a shipped feature off on the way past.

## Decision

The shipped value of a Core checkbox setting is declared in Apex, in `SHIPPED_DEFAULTS` in
`SettingsService`, and applied by `getSettings()` to a settings record the org has never saved.
Field metadata keeps its `defaultValue`, because the console and Setup read it, and the two have
to agree.

Applying the default to the record that `getSettings()` returns settles both halves: reads on a
fresh org get the shipped value, and the first save carries that value into the record it
creates, because `applyValues` clones the same record. From that point the stored value governs,
including a deliberate false.

`scripts/ci/check-setting-defaults.py` enforces the agreement. A checkbox on a hierarchy custom
setting that declares a default of true has to be registered in `SHIPPED_DEFAULTS`, or listed in
the script's `KNOWN_UNREGISTERED` table with the reason it is not. Registering a field the
metadata does not ship on fails the same check, and so does an excuse that outlives its field.

## Alternatives considered

- **Leave it to each feature to spell its own default.** This is what C-15 did, and what
  `HouseholdService` and the Giving readers still do, each in a slightly different dialect
  (`!= false`, `!= true`, `== null`). One of the four was wrong for a year of writing and
  nothing said so. A default that is written once is checkable; four of them are not.
- **Read the metadata default at run time through describe.** `DescribeFieldResult` does expose
  a default, but its behavior differs by field type and by whether the default is a formula, so
  the mechanism would be less predictable than the trap it replaces, and it would silently flip
  the four settings recorded as known gaps below without anyone measuring the result.
- **Materialize the settings record at install.** `CorePostInstall` could write an org-level
  record carrying every shipped default. That fixes an install but not a scratch org, a test, or
  a package upgrade that predates the script, and it puts a DML in the install path for
  something a read can answer. Worth revisiting only if a setting ever needs to exist as a real
  record for some other reason.
- **Do nothing and fix the relationship read alone.** It would have closed thirteen failures and
  left the same trap armed for the next feature that ships something on.

## Consequences

`SHIPPED_DEFAULTS` is now the one place that says how a Core checkbox ships, and it has to be
edited whenever a setting is added that ships on. The CI gate makes forgetting it a build
failure rather than a silent half-working feature.

Four checkboxes that ship on are recorded in the gate as known gaps rather than registered:
`Auto_Create_Households__c` and `Delete_Empty_Households__c`, which `HouseholdService` reads as
`!= true` so a fresh org gets the opposite of the shipped default, and Giving's
`Auto_Apply_Gifts_To_Installments__c` and `Automatic_Household_Soft_Credits__c`, which are read
through `SettingsService.getValue` on a module settings object, where an unsaved record returns
null rather than false and both readers treat null as on. The household two are a live defect of
the same shape; they are not fixed here because turning household creation on changes the
behavior of every test class that never saves settings, and only an org run can measure that.
The Giving two reopen the moment a Giving settings record exists for any other key, which is
what a module-side mechanism would have to close.

The mechanism covers Core's settings object only. A module settings object read through
`orgDefault` still gets `type.newSObject()`, whose checkboxes are null. When a module needs a
shipped default, this decision is the shape to extend, not to copy.

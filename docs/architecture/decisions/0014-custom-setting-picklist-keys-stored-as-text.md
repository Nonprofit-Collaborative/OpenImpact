# ADR-0014: Nonprofit Settings picklist keys are stored as text

**Status:** Accepted
**Date:** 2026-09-07
**Source:** builder decision under plan Section 9.3 ("when a platform limitation blocks the plan, record an ADR with the workaround and continue")

## Context

Decision D-06 (ADR-0006) puts the org's simple toggles and values in a protected hierarchy
custom setting, `Nonprofit_Settings__c`, so that the settings console can write them
synchronously. The canonical model's v0.1 key inventory (Section 12) describes two of
those keys as picklists: `Coexistence_Mode__c` (Standalone, NPSP, AgentforceNonprofit) and
`Household_Membership_Mode__c` (Contact, Junction).

Custom settings do not support picklist fields. The platform allows Checkbox, Currency,
Date, Date/Time, Email, Number, Percent, Phone, Text, Text Area, and URL on a custom
setting, and nothing else. The canonical model's rule 3 says the platform wins and the
deviation is recorded here.

Moving the two keys to a custom object was considered and rejected: they are single
org-wide values, not list-shaped configuration, so ADR-0006's own test puts them in the
custom setting.

## Decision

Both keys are **Text fields on `Nonprofit_Settings__c`**, holding one of the values the
canonical model lists, with the shipped default set as the field's default value.

The allowed values live in Apex, in `SettingsService`, which validates any write and
rejects a value outside the list with a labelled error. The settings console renders the
key as a choice list built from that same source, so an administrator picks from a list
and never types a value. Nothing outside the settings service writes these keys.

## Consequences

- Validation is code, not schema. A direct data load or a Setup edit could write an
  invalid value; readers therefore treat an unrecognized value as the shipped default
  rather than failing. The setting is protected, so Setup is not a realistic path.
- Reports cannot group by these keys. They are org-wide singletons, so there is nothing to
  group.
- Adding a value is a source change in one place (the allowed-value list in
  `SettingsService`) plus a canonical model row, rather than a picklist edit in Setup. That
  matches how every other packaged default is shipped.
- The same constraint applies to every future custom setting key. A new key that wants a
  fixed set of values follows this pattern; a key that wants list-shaped configuration
  belongs in a custom object instead, per ADR-0006.

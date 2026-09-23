# ADR-NEXT: Duplicate detection uses the org's own duplicate rules, and Open Impact ships none

**Status:** Accepted (builder decision, conservative; confirm on review)
**Date:** 2026-09-23
**Source:** plan Section 5.1, feature C-20 ("uses platform duplicate rules where present");
Principles 1 and 8; canonical model Section 29A

## Context

C-20 asks for duplicate detection and merge suggestions for households and people. The
platform already has every part of detection: matching rules say what counts as the same
record, duplicate rules run them when a record is saved, `Datacloud.FindDuplicatesByIds`
runs them on request, and Duplicate Record Set and Duplicate Record Item hold what was found.
Every org starts with the standard Contact and Account duplicate rules switched on.

Two gaps remain. A duplicate rule only runs when a record is saved, so records already in the
org are never compared with each other, and the platform job that does that (duplicate jobs)
exists only in Performance and Unlimited Edition, which the nonprofits Open Impact is built for
do not have. And nothing records a person's decision that a proposed pair is not a duplicate.

An earlier, unmerged draft of this feature shipped its own matching and duplicate rules keyed
to the import framework's matching (exact email, or last name with postal code). The platform
deploys a packaged matching rule inactive, and activating one is a Setup action an installed
app cannot perform, so that draft needed four Setup steps before anything worked.

## Decision

- **Open Impact ships no matching rule and no duplicate rule.** Detection is whatever
  duplicate rules for Contact and Account are active in the org: the standard ones by default,
  or the administrator's own.
- **A scan fills the first gap.** Started by a person from the Duplicates panel of Nonprofit
  Settings, it runs `FindDuplicatesByIds` over existing contacts and households fifty at a
  time and writes the pairs it gets back as standard Duplicate Record Sets. It is not
  scheduled. It refuses to start when no rule for either object is active, and the panel says
  so and links to Duplicate Rules in Setup.
- **One object fills the second gap.** `Duplicate_Dismissal__c` holds a pair a person said is
  not a duplicate, so the next scan passes over it.
- **Merges are the ones that already exist.** Households through the household merge (R-H13),
  one pair at a time from the panel. People through the platform's own merge, reached from the
  Potential Duplicates card, which the packaged Contact record page now carries. The Account
  record page does not carry the card, so a household is never merged past R-H13.
- **Scope is people and households.** A pair where an account side is an organization or a
  person stored as an account is not proposed.

## Alternatives considered

- **Ship Open Impact matching and duplicate rules** (the earlier draft). Rejected: four Setup
  steps before first use (Principle 1), a second set of active rules beside the standard ones
  that would alert twice on every save, and rules an upgrade may not change once an
  administrator has edited them. What it bought, an import and a scan that agree on "the same
  person", matters less than it looks: the scan only proposes, a person decides.
- **A matching engine of Open Impact's own.** Rejected: Principle 8, and the platform's
  matching (fuzzy names, normalized addresses) is better than a packaged one would be.
- **Schedule the scan nightly.** Deferred: duplicate rules already catch new records on save,
  so a schedule would mostly re-scan unchanged records. Rerunning after a large import is in
  the admin guide. Revisit if reviewers report missed duplicates between scans.
- **Merge two people in the app** with `Database.merge`. Rejected for now: the platform merge
  already carries related records, and an in-app one would have to repair household
  membership and rollups the platform merge handles through the existing delete triggers.

## Consequences

- An org whose administrator switched the standard rules off sees an explanation and a Setup
  link instead of suggestions. That is one Setup step, only in that org.
- What counts as a duplicate varies by org. The admin guide describes the standard rules and
  says how an administrator narrows or widens them.
- The platform refuses a `FindDuplicatesByIds` call that includes a person account when no
  person account rule is active, so the scan sends accounts of the Household record type only.
- `DuplicateRule`, `DuplicateRecordSet` and `DuplicateRecordItem` join the standard object
  allowlist. They exist in every edition that has duplicate management.

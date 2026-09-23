# ADR-0044: The household's Primary Contact mirrors the primary member, person accounts included

**Status:** Accepted (provisional: delegated by the product owner on 2026-09-23 and confirmed after he tests it)
**Date:** 2026-09-23
**Source:** product-plan Section 11.2 item 8, feature C-22; canonical model R-M3, R-H5, R-H10; constrained by ADR-0009, ADR-0013 and ADR-0021

## Context

R-M3 says at most one current member of a household is marked primary, and that the primary
member is mirrored to the household's Primary Contact (`Account.Primary_Contact__c`). The
second half was never built, and was recorded as a known gap in canonical model Section 30,
because the field is a lookup to Contact and junction membership exists for orgs that store
people as person accounts. A household made only of person accounts therefore had no primary
contact at all, and anything that reads the field (the Giving acknowledgment recipient for a
household donor, reports, compact layouts) had nothing to read.

Three options were on the table (plan Section 11.2 item 8): a second lookup to Account beside
the existing one; make the primary a question only `HouseholdService` answers, with no field in
junction mode; or drop the mirror. The owner chose a fourth on 2026-09-23: keep the one field
and fill it with the person account's own person contact.

That choice rests on one platform fact, verified before anything was built on it. In the shared
test org `oi-test`, which has person accounts enabled, an anonymous Apex run inside a savepoint
(rolled back) created a person account, read its `PersonContactId` (an `003` id whose
`getSObjectType()` is Contact), and then both updated and inserted a household with
`Primary_Contact__c` set to that id. Both saves succeeded, the stored value equalled the person
contact id, and `Primary_Contact__r.AccountId` read back as the person account. A Contact
lookup on Account accepts a person account's person contact.

## Decision

**`Account.Primary_Contact__c` stays the one field that names a household's primary person, in
both membership modes, and `HouseholdService` keeps it consistent with membership.**

- **Contact mode.** The field is the mark itself: there is no membership row to carry a flag.
  Make primary on the members panel, or an edit of the field, sets it. Household upkeep keeps it
  valid under R-H10: when the person it names is no longer a current member, it is cleared and
  nobody is promoted in their place.
- **Junction mode.** The field is a mirror of the current membership marked Is Primary, written
  only by `HouseholdService`. A member stored as a Contact is mirrored as that Contact. A member
  stored as a person account is mirrored as that account's person contact, read as
  `PersonContactId` only through dynamic SOQL, only when the Account describe has that field, and
  never named at compile time, so Core keeps no dependency on person accounts (ADR-0009,
  ADR-0013). With no current primary member the field is empty (R-H10: proposed, not assigned).
- **Where it is settled.** In `HouseholdService.afterMembershipChange`, the one upkeep path every
  membership change already reaches: a membership row inserted, updated (including Is Primary
  and End Date), deleted or restored; a person deleted or restored; a move, a merge and a split.
  It runs before naming, so the naming pass reads the settled value. A merge that keeps a custom
  name, which settles only the member count, settles the primary as well. The read is upkeep
  under ADR-0021 and runs in system mode; the write goes through `HouseholdWriter`.
- **Only one writer in junction mode.** A save that sets or changes Primary Contact on a
  household by hand in junction mode is refused with a message that says to use Make primary on
  the household's members panel. Organizations are never affected: they share the field (R-O3)
  and set it by hand in both modes.
- **More than one current primary.** R-M3 allows one, but a data load can leave two. The mirror
  names the first of them in R-H5 order and changes no membership row: which person is right is
  a decision somebody makes.
- **Ordering (R-H5).** Within a role the primary member sorts first. That tiebreak reads the
  source of truth for the mode: the Primary Contact field in contact mode, the Is Primary flag on
  the membership rows in junction mode. The mirrored field is never read back into the ordering
  in junction mode, so a stale value cannot give a household two primaries.
- **Merge.** In junction mode Primary Contact is not one of the values a merge offers a choice
  about, because the rows decide it: the survivor keeps its primary member, and the other
  household's primary member keeps the flag only when the survivor has none (unchanged since
  C-09). The field then follows.

## Alternatives considered

- **A second lookup to Account beside the existing one.** Rejected by the owner: two fields for
  one idea, and every report, formula and email recipient would have to ask which one to read.
- **The primary as a service answer only, with no field in junction mode.** Rejected by the owner:
  a service method is not reportable, and a report or formula that names the primary person would
  have nothing in junction mode.
- **Drop the mirror from R-M3.** Rejected: the Giving acknowledgment path already reads the field
  for a household donor, and a household of person accounts would get no thank you.
- **Overwrite a hand edit silently in junction mode.** Rejected: the person who typed the value
  would see it changed back with no reason. Refusing the save says why and where to go instead.
- **Leave a hand edit alone until the next membership change.** Rejected: the field and the rows
  would disagree for an unbounded time, which is the silent disagreement this decision closes.

## Consequences

- The R-M3 row leaves the known-gaps table in canonical model Section 30.
- A report on Primary Contact in a person account org shows the person contact, whose name is
  the person's name. Its Account is the person account itself, not the household.
- Junction mode now refuses a hand edit of Primary Contact on a household, from the record page,
  a list view or a data load. The admin guide says so; the members panel is the way.
- A membership whose End Date is in the future stops being current on that date with no save to
  react to, so the field follows at that household's next membership change. Member Count behaves
  the same way today; neither is new with this decision.
- One more dynamic query per upkeep pass that has a person account marked primary, and none on an
  org without person accounts.
- Provisional: if the owner reverses it after testing, the change is contained in
  `HouseholdService` (the settle step and the hand-edit guard), `PersonRecordSelector` (the person
  contact read), and two lines in `HouseholdNamingService` and `HouseholdMergeService`.

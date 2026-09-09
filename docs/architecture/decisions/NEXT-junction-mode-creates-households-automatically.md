# ADR-NEXT: Junction mode creates a household for a new person, under the one setting that already says so

**Status:** Accepted
**Date:** 2026-09-09
**Source:** ADR-0005 (household as an Account record type with two membership modes), canonical model R-H1 and R-H2, defect found in C-01

## Context

An administrator in a Nonprofit Cloud org gets no households at all, silently, and the
product tells them the opposite while it happens.

Three pieces combine into that. `CoexistenceService.setMode` writes
`Household_Membership_Mode__c = Junction` whenever the mode is Agentforce Nonprofit, which
is what the Setup Assistant's first step does in such an org and what Health Check offers
as a one-click fix. `HouseholdService.ensureHouseholds` then returned as soon as it saw
junction mode, before it ever read `Auto_Create_Households__c`, so a new Contact got
nothing. The only remaining creation path was `AccountTriggerHandler`, which required
`Create_Households_For_Person_Accounts__c`, a setting that ships false by declaration. The
importer writes no `Household_Member__c` row at all, so it did not fill the gap either.

The result was a state with no error, no Error Log entry and no Health Check finding, while
`docs/admin-guide/households.md` said "Open Impact creates a household for every new person
you add" and the settings console said "when you save a new person with no household, one
is created for them". Both were false in the configuration the product itself recommends.

R-H2 read, until this decision:

> **R-H2 Person Accounts.** In junction mode with Person Accounts enabled, creating a
> Person Account does not create a Household unless
> `Create_Households_For_Person_Accounts__c` is on. When it is on, a Household is created
> and a Household Member record links the Person Account to it.

That rule was written for one org shape (people stored as accounts) and was read by the
code as the rule for a whole mode. Junction mode is also available to an org that stores
people as contacts, and it is the mode a Nonprofit Cloud org is put into on its first day,
so "no automatic creation unless a second, off-by-default setting is on" became the answer
for everybody in that mode.

## Decision

Junction mode creates households automatically, on the same terms contact mode does, and
`Auto_Create_Households__c` is the only setting that governs it.

- Saving a new person who belongs to no household creates a Household Account named from
  the org's patterns and a `Household_Member__c` record joining them to it, with the role
  Head and the primary flag set. This holds whether the person is stored as a Contact or,
  in an org shaped that way, as a person record on Account.
- A person a membership record already joins to a household is left alone, which is the
  junction-mode form of the contact-mode test "the Contact arrived with an Account".
- Contact-mode behavior is unchanged: the household id is assigned before insert, as it
  was, because there is no membership record to write.
- `Create_Households_For_Person_Accounts__c` is retired: the field, its
  `Setting_Definition` row, and every read of it are removed.
- Health Check gains an error-severity finding, `household_creation_disabled`, for the
  state where membership is junction and automatic creation is off, with a one-click fix
  that turns `Auto_Create_Households__c` on. The state stays reachable on purpose, because
  an org that groups its people some other way may want it, but it can no longer be
  arrived at silently.

R-H1 and R-H2 in `docs/architecture/canonical-model.md` are amended to match, and R-C1 now
names both modes.

## Alternatives considered

- **Keep `Create_Households_For_Person_Accounts__c` as a narrowing switch for people stored
  as accounts, and add contact-side creation under `Auto_Create_Households__c`.** Rejected.
  It leaves two settings that can disagree, and the disagreement has no answer an
  administrator can predict: with automatic creation on and the person account switch off,
  a Nonprofit Cloud org, where nearly every person is stored as an account, would still get
  no households, which is the defect this decision exists to close, only harder to see. The
  distinction it draws (people on Contact yes, people on Account no) is not one any
  nonprofit has asked for, and in the orgs where it applies almost every person is on the
  side that would be switched off.
- **Keep the field as a deprecated no-op.** Rejected. A setting an administrator can see
  and change, that changes nothing, is worse than either answer. Nothing is packaged yet
  (no namespace, no 2GP versions, ADR-0001), so retiring the field costs no upgrade path.
- **Fix only `ensureHouseholds`, so junction mode reads `Auto_Create_Households__c` and
  assigns the Contact's Account.** Rejected. It writes the contact-mode mechanism in
  junction mode, which R-H3 forbids, and it leaves people stored as accounts on the second
  setting, so the two halves of one mode would answer differently.
- **Make Health Check the whole fix.** Rejected. It converts a silent defect into a loud
  one and still ships a recommended configuration that does nothing until the administrator
  acts on a finding.
- **Do nothing until the importer writes membership rows.** Rejected. The importer is one
  way in; a person typed onto the Contacts tab is the other, and the admin guide promises
  the household for both.

## Consequences

Junction mode now writes on the insert path, which contact mode does not: the household and
its membership row are created after insert, because a membership record needs the person's
id. That is one extra insert of households and one of memberships per transaction, both
bulked, plus one query that asks which of the new people already have a household. The
recursion hazard `AccountTriggerHandler` guards with its `running` flag now exists on the
contact side too, because creating a household Account fires the Account trigger and the
membership insert fires the Household Member trigger. `HouseholdService` carries one guard
for both automatic creation paths.

An org that deliberately wants no automatic households turns `Auto_Create_Households__c`
off, and Health Check then reports that state rather than leaving it silent. An org that
had `Create_Households_For_Person_Accounts__c` on gets the same behavior it had, from the
setting that ships on.

`Auto_Create_Households__c` remains a known gap in
`scripts/ci/check-setting-defaults.py`: it declares a shipped default of true that Apex does
not see on an org that has never saved its settings (ADR-0035), so a fresh org reads it
false and creates no households in either mode. This decision does not close that, because
registering it in `SHIPPED_DEFAULTS` changes the behavior of every test class that never
saves settings and only an org run can measure it. The new Health Check finding is what
makes the junction half of it visible in the meantime, and closing the gap is the next step
for the household cluster.

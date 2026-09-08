# ADR-0028: A donor level labels an existing rollup, and follows that total down

**Status:** Accepted
**Date:** 2026-09-08
**Source:** feature G-14 (plan Section 5.2, roadmap v0.4); canonical model Sections 14, 25A and 26;
ADR-0015, ADR-0017, ADR-0021, ADR-0022

## Context

G-14 is the NPSP Levels successor: configurable tiers, automatic assignment, the previous level
retained, movement between levels visible. Four questions have to be answered before any of it is
built, and none of them is settled by the plan.

**Which number a level is measured on.** A level is a threshold on giving, and this project
already has an aggregation engine with 38 shipped definitions (ADR-0015, canonical model
Section 26) that maintains lifetime and fiscal year giving totals on Account and Contact under the
status filter ADR-0022 fixed. Anything that recomputes those totals privately would be a second
aggregation mechanism, and worse, it would disagree with the donor's own total on the same screen
the moment the two filters drifted apart. NPSP's Levels made the source field configurable across
any rollup field, which is where the useful part of that design is.

**What window the level measures.** Lifetime, a fiscal year, a rolling twelve months, or the
admin's choice. The available windows are not open ended: they are exactly the totals the rollup
engine already keeps, because building a new one would be the second mechanism again. A rolling
twelve months is not among them.

**What happens when a refund lowers the total.** The feature description says the previous level is
retained, which can be read two ways: the donor keeps the higher level, or the record keeps a note
of where the donor came from. R-G3 and ADR-0022 make this a real case rather than a rare one, since
a refund lowers Total Giving as soon as it is entered.

**Whose level it is, and when assignment runs.** Section 26 writes giving totals to three kinds of
record (Household Account, other Account, Contact), and the household membership modes mean a
person's giving can sit on a household rather than on the person. The rollup engine offers real
time, scheduled, and both (R-R4), and a fourth answer here would be one more thing to explain.

## Decision

1. **A level is a label on a rollup, never its own aggregation.** Assignment reads one currency
   attribute already on the record being assigned, named by the `Donor_Level_Source_Field__c`
   setting. The shipped choices are the four Section 26 totals a ladder can sensibly be built on:
   `Total_Giving__c` (the default), `Giving_This_Year__c`, `Giving_Last_Year__c` and
   `Largest_Gift__c`. No Gift is queried, summed or filtered by G-14 code, so a level is
   automatically consistent with ADR-0022: it inherits that filter by construction rather than by
   restating it.
2. **The window is therefore the window of the rollup chosen, and the default is lifetime.**
   Lifetime giving is the default because it never resets: a fiscal year source empties every
   donor's ladder position on the first day of the new year, which is right for an annual
   recognition society and alarming for anyone who did not choose it deliberately. An organization
   that runs an annual society changes one setting. A rolling twelve month window is not offered,
   because there is no rollup for it; if one is wanted, the answer is a new
   `Rollup_Definition__c`, not new code here (parking lot, plan Section 11.3).
3. **The level always states what the current total earns, and the previous level is a record of
   movement, not a floor.** A refund that drops a donor below their threshold moves them down in
   the same save, and the level they held moves to Previous Donor Level with Donor Level Changed
   Date set to that day (R-DL4, R-DL5). Nothing is written when assignment produces the level
   already held, so the changed date says when the donor last moved rather than when the job last
   ran. An organization that awards a level permanently records that on the donor; the package
   does not silently hold a number above the total printed next to it.
4. **All three scopes carry a level, and the membership modes never enter into it.** Household
   Accounts, other Accounts, and Contacts each get the same three fields, because each of them
   already carries the total the level is read from. Since the total was written by the rollup
   engine, which resolved contact mode or junction mode when it calculated it (R-R1), G-14
   resolves no membership at all. A household and its members can hold different levels because
   they hold different totals, which is the same answer Section 26 already gives.
5. **Assignment matches the rollup engine's modes rather than inventing a fourth.** Real time, in
   a before insert and before update handler on Account and Contact, which is also the save the
   rollup engine makes when a gift lands, so the level is right in the same transaction and costs
   no second DML. Scheduled, in a nightly batch that catches the two changes no record save
   announces: a fiscal year turning over and a ladder edited by an administrator. On demand, from
   the Recalculate button on the Donor Levels page, which is the same batch run now. The batch
   writes through a dedicated writer under ADR-0021, for the same reason the rollup engine does:
   computed, package owned values, no user input, and correctness that must not depend on the
   scheduling user's sharing.
6. **The ladder is one ladder for the organization, and its rungs are ordinary records.** Tiers are
   `Donor_Level__c` records created and edited through the platform's own record pages, reached
   from a Donor Levels page in the settings console that shows the ladder, how many donors sit on
   each rung, when levels were last recalculated, and the Recalculate button. Several independent
   ladders are not built: each would need its own level attribute on Account and Contact, which
   means either Setup field creation, which Principle 1 forbids Maria, or a fixed number of
   shipped attributes nobody asked for.

## Alternatives considered

- **Give Donor Level its own aggregation over Gift**, so a ladder can filter gifts its own way
  (only cash, only one fund). Rejected: it is a second aggregation mechanism, it would restate the
  ADR-0022 status filter in a second place where it can drift, and the same result is available by
  adding a rollup definition and pointing the setting at it.
- **Ship a "levels never decrease" option**, so a refund cannot demote a donor. Rejected for now:
  it makes the level disagree with the total beside it, which Principle 2 puts above convenience,
  and no evidence says the case is common. Parked; if it returns, it is one boolean and one branch
  in `DonorLevelService`.
- **Store the level as text rather than a lookup.** Rejected: renaming a rung would leave the old
  name on every donor, and reporting by level would group on a string. The cost of the lookup is
  R-DL8: deleting a rung clears it everywhere, which is why levels are deactivated instead.
- **A rolling twelve months as the default window.** Rejected: no such rollup exists, so it would
  require the mechanism this ADR exists to avoid.
- **Assign in an after trigger with an update.** Rejected: it doubles the DML on every rollup write
  and would need a recursion guard, where a before context needs neither.
- **Levels on Contacts only, as NPSP effectively encouraged.** Rejected: in this model the
  household is where a couple's giving is totalled, so a household would be the one record with no
  level, and the number and the label would sit on different records.

## Consequences

- **The ladder can only be measured on a total that exists.** An organization wanting a window we
  do not ship has to add a rollup definition first. That is a real limitation and it is the price
  of not building a second engine; the admin guide says it in those words.
- **A donor can move down.** Fundraising staff will see it happen after a refund or a corrected
  gift, and the previous level plus the changed date are what make it explainable. Reports that
  need a permanent recognition record cannot use this attribute for it.
- **Deleting a rung erases it from history.** The platform's lookup behavior cannot be softened, so
  the page and the guide push deactivation, and the object ships an Active attribute for it.
- **The nightly pass touches every Account and Contact with a giving total.** It writes only the
  records whose level actually changes, so on a normal night it writes very little, but it reads
  broadly. If that becomes a cost at the v0.10 scale test, the batch gains a filter on
  `Rollups_Last_Calculated__c` rather than a new design.
- **Two settings and one page are added to the console**, all in the Giving section, with the page
  reached by navigation under ADR-0020 because Core cannot import a Giving component.

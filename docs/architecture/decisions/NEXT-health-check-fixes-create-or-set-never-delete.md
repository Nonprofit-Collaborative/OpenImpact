# ADR-NEXT: Health Check fix buttons create or set, never delete, and ask first

**Status:** Accepted (builder decision, conservative; confirm on review)
**Date:** 2026-09-23
**Source:** plan Section 4.8 ("each finding has a fix action where possible") and Section 5.1,
feature C-21; builder decision under Section 9.3; extends ADR-0006, ADR-0021 and ADR-0039

## Context

Health Check v1 (C-11) reports what is wrong and, for three findings, fixes it with one click:
use the recommended coexistence mode, switch to junction membership, turn on automatic
households. C-21 adds fix actions. The code is small; the decision is which findings may carry
a button, because a button on a finding whose remedy is ambiguous turns a report the
administrator reads into an action she trusts, and the trust is spent the first time it does
something she did not mean.

Several states Health Check can see have exactly one correct end state. Package defaults are
materialized rather than shipped as records (ADR-0006): rollup definitions and automation switch
rows are created from custom metadata by each package's post-install script (ADR-0029), and
import templates when the Import page first opens with none. An org can still be missing rows
it is meant to have: an install step that failed and logged instead, a shipped row deleted by
hand, a module installed before this change. Before C-21 nothing created the switch rows at all,
so the Automation page of every org was empty; C-21 adds them to Core's and Giving's
post-install scripts, through `AutomationSettingsWriter` (ADR-0021), because every row carries
`Always_Runs__c`, which no packaged permission set may edit. And the nightly rollup run is
started by a button nobody is obliged to press, so scheduled totals can silently never
recalculate.

An earlier, unmerged draft (`feature/c-21-health-check-v2`) wrote the same rule and built a
generic preview and apply framework around it, about 700 lines before tests.

## Decision

A finding gets a fix button only when all of these hold. Otherwise it keeps a link to the page
where a person decides.

1. **One right answer, and Health Check can name it.** The end state follows from the finding,
   not from what the organization meant.
2. **Package owned configuration only.** A fix writes rows materialized from this package's own
   shipped metadata, settings this package defines, or this package's scheduled job. Never a
   constituent, a gift or an address, and never an amount typed on a record. A restored shipped
   total is the one fix that changes amounts afterwards: it starts calculating as soon as it is
   created, as it would have from install, and the finding says so. It is not restored when one
   of the administrator's own active totals already writes the same field, because the two would
   overwrite each other; the finding and the result name it as skipped.
3. **Create or set, never delete, never overwrite.** No fix deletes a record, whatever the
   finding says, and none replaces a value an administrator chose.
4. **Pressing it twice is pressing it once.** Every fix calls a service that is already
   idempotent: it creates only what is missing, or schedules only when nothing is scheduled.
5. **It says what it will do, counted from this org, and asks first.** The finding names the
   rows or the people the fix touches. The panel shows that text again in a dialog that takes
   focus, with a Confirm button, before any fix that changes something runs. The finding carries
   its fix scope (the names it would create, or the job it would schedule), the panel sends it
   back, and the fix is refused with a sentence if what it would change now is different; the
   panel then re-runs Health Check. Afterwards the report is re-run underneath it and says what
   the fix did.
6. **All or nothing, and a failure is visible.** One fix runs inside a savepoint, a failure is
   written to the Error Log and returned as a sentence.
7. **Recorded.** A fix that ran writes one entry to the settings change history
   (`Setting_Change__c`), naming what it created or scheduled, as every other change made on the
   console does.

C-21 adds four findings with fixes: shipped rollups missing (create them), automation switches
missing (create them), shipped import templates missing (create them), and nightly rollups not
scheduled while an active definition needs them (schedule the run). The three v1 fixes already
meet the rule and now ask first as well. The four new checks run only for a viewer who may
manage settings, like the Error Log check, since only that viewer can act on them.

Three of the four fixes can be undone from the app: a restored total is switched off on the
Rollups page (a total is never deleted there, since a deleted shipped total comes back on the
next restore or upgrade), a restored switch is set on the Automation page, and the nightly run
is stopped on the Rollups page. A restored import template has no in-app undo: the Import page
offers no delete or deactivate, and none is built for this. A template is inert until somebody
picks it, so an unwanted one costs a line in a list. Health Check itself never undoes anything.

The generic framework is not built. A fix is a controller method that calls an existing service
inside a savepoint; the finding's own text is the preview. What breaks without the framework:
nothing named. The finding already counts from the org on every run, and a second preview call
adds a round trip and a second copy of each check's logic.

## Alternatives considered

- **The generic preview and apply framework** (the earlier draft). Rejected on size: its
  guarantees are kept here by the rule, the existing idempotent services and one savepoint.
- **A fix that removes Automation Setting rows an upgrade stopped shipping.** Refused by
  condition 3. Such rows are inert: nothing runs an automation with no registry entry behind it.
- **Give the Nonprofit Admin role to somebody when nobody holds it.** Refused by condition 1:
  who administers the app is the organization's choice. That finding keeps its Access link.
- **Give the role to people who hold the Nonprofit Admin permission set directly** (in the
  earlier draft). Not built: the role contains exactly that permission set, so the fix changes
  nothing anybody can do, and Health Check already counts those people as administrators.
- **No confirmation step.** Rejected: the plan asks for fixes that are explicit, and a second
  click on the finding's own text costs the administrator nothing.

## Consequences

- Scheduling the nightly run is the one fix that is not a record: it creates the scheduled job
  the Rollups page creates, under the same name, so the Rollups page sees and stops it.
- A restored automation switch takes the registry's `Enabled_By_Default__c`. Every shipped
  automation is on by default today, so restoring a switch never stops an automation that is
  running (a missing switch means it runs). An automation that always runs (ADR-0024) gets a row
  that the page shows locked. A registry row shipped off by default would break condition 3 for
  this fix, and is re-examined before it ships.
- The skip rule for totals lives in `RollupService.ensureDefaults`, so the install scripts and
  the Rollups page's Restore button follow it too. Only the administrator's own definitions
  count: shipped pairs such as the household and the organization total write the same field
  for different accounts by design.
- Plan Section 4.8 also names orphaned records. No orphan check is added here: finding one is a
  data question, not a configuration one, and C-28 (data hygiene console) owns it.
- A new fix is added by passing the seven conditions in review, one at a time.

# ADR-NEXT: Mirror depends on Core only; the gift parts move to Mirror for Giving, and the Case status check runs hourly while Cases are open

**Status:** Accepted
**Date:** 2026-11-14
**Source:** Owner decisions 2026-11-14 on ADR-0221's open questions. N-09: "No, using nonprofit
modules should never be required". N-10: "Hourly if cases exist". Amends ADR-0013
`0013-platform-only-org-shape-verification.md` (which packages may name standard objects),
ADR-0126 `0126-rename-connect-to-mirror.md` (Mirror as one package), ADR-0194
`0194-simpler-permission-sets.md` (the Salesforce Records Sync set) and ADR-0221
`0221-projects-requests-and-issues.md` decision 7 and open questions 1 and 2. Notes D-99 (Mirror's
editions).

## Context

Mirror held two kinds of work. The gift parts (Campaign Sync, Opportunity Mirror, Gift
Transaction Mirror, Accounting Export, the Inbound Gift API, the NPSP and Nonprofit Cloud gift
migration kits and their import templates) read and write Giving's Gift, Appeal and Fund, so
Mirror depended on Core, Rollup Builder and Giving. The rest (the Case bridge to a service
provider, Nonprofit Cloud households and relationships) needs Core alone. An org that only wants
to send its Cases to a provider had to install two nonprofit modules first, which the owner
ruled out.

The Case status pull ran once a night at 01:40, so a requester waited up to a day to see the
provider's answer.

## Decision

### 1. Two packages

- **Mirror** (`packages/mirror`, module key `Mirror`) depends on Core only. It keeps the Case
  bridge (`CaseProviderRequests`, `CaseProviderRequestAction`, `CaseProviderRequestsHourly`,
  `Provider_Request__c` and its tab), the Nonprofit Cloud households and relationships kits and
  their two import templates, the household drift Health Check finding, and
  `Mirror_Settings__c` with every field. Offered in both editions (Standard and Nonprofit).
- **Mirror for Giving** (`packages/mirrorgiving`, module key `MirrorGiving`, package "BarnCRM
  Mirror for Giving") depends on Core, Rollup Builder, Giving and Mirror. It holds every gift
  part listed above, their pages, tabs, labels, custom permissions, Automation Registry rows,
  Setting Definitions, the fields and list views on Gift, Appeal and Fund, its own help catalog
  (`BarnHelp_MirrorGiving.json`), its post-install class, its nightly step provider (the
  Opportunity and Gift Transaction mirror runs) and its Health Check extension (the stale run
  findings). Nonprofit Edition, as Mirror was.
- `Mirror_Settings__c` stays in Mirror with the gift fields. A custom setting's fields cannot be
  split across packages reliably, and moving them would lose the values orgs have stored. Mirror
  for Giving reads and writes them through its dependency on Mirror.
- No capability is removed: every class, page, setting and permission moves whole. An org that
  had Mirror installs Mirror for Giving next to it to keep the gift parts.

### 2. Standard objects (amends ADR-0013)

Mechanism 1's rule is unchanged: standard objects (Opportunity, Campaign, Case, Lead) are named
only by string, through describe, and only in the Mirror packages. `check-standard-objects.sh`
now treats `packages/mirrorgiving` exactly as `packages/mirror`: excluded from the reference
scan by path, included in the walk that forbids declaring fields or objects on a standard
object. No other package gains the exception.

### 3. Permission sets (amends ADR-0194)

`Salesforce_Records_Sync` (the sync pages) moves to Mirror for Giving, without its
`Provider_Request__c` grants. Mirror ships a new set, `Provider_Requests` (read on Provider
Request and its fields, and the tab), offered on the Access page as an add-on. Holders of
Salesforce Records Sync who read Provider Requests need the new set as well; no automatic
migration is built, because an org that uses the Case bridge has a handful of such users.

### 4. Case status check: hourly, only while Cases are open (amends ADR-0221 decision 7)

- One scheduled job, `BarnCRM Mirror: Case requests hourly` (`CaseProviderRequestsHourly`, cron
  `0 15 * * * ?`), runs at 15 minutes past each hour.
- It first runs a cheap guard: one `LIMIT 1` query for a Provider Request not yet Resolved,
  Closed or Cancelled, and one for an open Case of the chosen Type. When neither exists it does
  nothing: no queueable, no callout, no Error Log entry.
- When either exists it queues the same `CaseProviderRequests` pass the nightly step ran (send,
  then pull status).
- The Mirror step on the Nightly Jobs card keeps its switch, Run Now and summary; the summary
  says whether the hourly check is scheduled. The nightly run itself only makes sure the job is
  scheduled (`ScheduledJobSelector.ensure`, the Tab Access Check pattern): safe to re-run, a job
  on another cron under the same name is replaced, and the job removes itself when the setting
  or the step switch is off. Post-install schedules nothing.

### 5. Editions (notes D-99)

Mirror's `BarnCRM_Module__mdt` row now lists Standard and Nonprofit, since it no longer needs
Giving. Mirror for Giving keeps Nonprofit only. Reversible by editing the row.

## Alternatives considered

- **A small package for the Case bridge only**, leaving Mirror as it was (ADR-0221 open
  question 2). Rejected: Nonprofit Cloud households and relationships also need no nonprofit
  module, and the owner's rule is about Mirror as a whole.
- **Keep the nightly pull and add a Run Now.** Rejected by the owner's decision.
- **A schedule every 15 minutes.** Rejected: four times the scheduled job executions for little
  gain; hourly is what the owner asked for.

## Consequences

- One more package directory (`sfdx-project.json`, deploy order after Mirror), one more
  `BarnCRM_Module__mdt` row (`MirrorGiving`) and every package list updated (deploy, apex budget,
  help text, tests run as, OpenAPI check path, async starter allowlist, API surface).
- Apex budget: Mirror's cap of 225,600 becomes 32,100 (Mirror) and 199,900 (Mirror for Giving);
  the extra classes (post-install, nightly provider, Health Check extension and their tests) add
  about 6,400 characters together.
- One label added (`Mirror_Access_AddOnProviderRequests`); the label budget rises by 1.
- Core's Health Check marker for the gift mirror names `MirrorGivingHealthCheckExtension`.

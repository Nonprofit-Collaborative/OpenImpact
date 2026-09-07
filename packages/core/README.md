# Open Impact Core

Core is the foundation package. Every other Open Impact module depends on it, and it depends on
nothing else. It contains no Opportunity, Campaign, Case, Lead, Person Account, or Industries
object references: those live only in the Connect module, behind dynamic Apex.

## What Core contains

- **Constituent model**: Contacts, Accounts (Household and Organization record types),
  Household membership (contact mode and junction mode via `HouseholdService`),
  Relationships, Affiliations, and Addresses (`Address__c`).
- **Nonprofit Hub app**: the Lightning app and its tabs (Home, Households, Contacts,
  Organizations, Import, Reports, Nonprofit Settings). Module-specific tabs (Gifts, Volunteers,
  Programs, Funders) are added by those packages when installed.
- **Settings framework**: the Nonprofit Settings console (LWC-based), protected hierarchy
  Custom Settings for simple toggles, custom objects for structured configuration, and Custom
  Metadata Types for package-shipped defaults.
- **Trigger framework**: one trigger per object, bypassable handlers, a pause-all switch.
- **Error Log** (`Error_Log__c`): every caught exception with context, user, record, and a
  plain-language message.
- **Rollup engine**: `Rollup_Definition__c` and the governor-limit-safe engine used by every
  module for household, contact, organization, fund, appeal, and commitment rollups.
- **Import framework**: `Import_Template__c`, `Import_Batch__c`, `Import_Row__c`, and the
  wizard that lets an admin load a spreadsheet without a consultant.
- **Health Check**: org shape and license detection, missing permission assignments, rollup
  schedule staleness, orphaned records, coexistence conflicts.

## Vendored code

Core carries one third party dependency, as source rather than as a package: the
[apex-rollup](https://github.com/jamessimone/apex-rollup) aggregation engine (MIT, James Simone),
under `packages/core/vendor/apex-rollup/`. It is driven through an adapter Open Impact owns, and
`Rollup_Definition__c` stays the only rollup configuration an administrator ever sees.

- **What was taken, what was changed, and how to take a newer version:**
  [`packages/core/vendor/apex-rollup/VENDOR.md`](vendor/apex-rollup/VENDOR.md). Read it before
  touching anything under `vendor/`, and update it in the same pull request that changes the
  vendored tree.
- **Why it was vendored rather than written or depended on:**
  [ADR-0015](../../docs/architecture/decisions/0015-vendor-apex-rollup-behind-adapter.md), with the
  source level comparison of the three candidates in
  [rollup-library-evaluation.md](../../docs/architecture/reference/rollup-library-evaluation.md).
- The upstream MIT licence text travels with the code, in
  [`packages/core/vendor/apex-rollup/LICENSE`](vendor/apex-rollup/LICENSE), and must stay there in
  every build that ships it.
- `packages/core/vendor/` is excluded from Prettier so that upstream diffs stay readable. Everything
  else under `packages/core` is formatted normally.

## Iteration

Core first ships in **v0.1** and is required by every later iteration; it is the only package
present in v0.1.

## Testing Core alone

Core has no dependencies, so it can be deployed and tested by itself in an empty scratch org:

```bash
sf org create scratch --definition-file config/scratch-defs/platform-only.json \
  --alias core-dev --set-default --wait 15
sf project deploy start --source-dir packages/core --wait 30
```

Run Apex tests scoped to Core only:

```bash
sf apex run test --test-level RunLocalTests --code-coverage --result-format human
```

Run LWC Jest tests for Core's components only:

```bash
npx sfdx-lwc-jest --config-path packages/core/main/default/lwc
```

Because Core has no hard reference to Sales Cloud objects, it must deploy and pass its tests on
the **Platform-only** scratch org shape (`config/scratch-defs/platform-only.json`), which is the
strictest of the four shapes and the one CI treats as the floor.

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

## Post-install script

`CorePostInstall` implements `InstallHandler`. It runs after the package is installed and
after every upgrade, and it makes sure the installing user can open Nonprofit Settings.
Without it, a fresh install leaves the console read only for everybody, including the
System Administrator who installed it, because a custom permission is not implied by Modify
All Data.

It does that in two steps, because the platform makes the obvious one unreliable:

1. **Assign the `Nonprofit_Admin` permission set.** A permission set has no calculation
   status, so this works the moment the install finishes. This is the step that matters:
   after it, the installer can use the app.
2. **Assign the `Nonprofit_Admin_Group` permission set group**, which is the role the
   Access page shows. Salesforce recalculates packaged groups in the background after an
   install and refuses to assign one while that is running, which is the usual state in the
   first minutes, so this is attempted and, if the group is not ready,
   `CorePostInstallRetryQueueable` waits and looks again up to five times, one chained job
   at a time. If it runs out of attempts it writes a warning to the Error Log naming the
   one manual step left, and stops.

Both steps are safe to run twice: a person who already holds a permission set or a role is
left alone, so an upgrade is a no-op for an org that is already set up. Nothing throws: an
install must never fail because of a bootstrap step, so every failure goes to the Error Log
instead.

Once package versions exist, `sfdx-project.json` names it for the Core package directory:

```json
"postInstallScript": "CorePostInstall"
```

That line is not in `sfdx-project.json` yet, because no package version has been created
(the namespace is deferred, plan Section 4.3). Whoever creates the first Core package
version adds it then. Until then the same effect is achieved by the scratch org script,
which assigns the permission sets after deploying.

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

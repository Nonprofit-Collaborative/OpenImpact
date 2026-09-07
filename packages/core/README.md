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
  plain-language message, published as a platform event so the entry survives the rollback it
  documents.
- **Rollup engine**: `Rollup_Definition__c` and the governor-limit-safe engine used by every
  module for household, contact, organization, fund, appeal, and commitment rollups.
- **Import framework**: `Import_Template__c`, `Import_Batch__c`, `Import_Row__c`, and the
  wizard that lets an admin load a spreadsheet without a consultant.
- **Health Check**: org shape and license detection, missing permission assignments, rollup
  schedule staleness, orphaned records, coexistence conflicts.

## Trigger framework

One trigger per object, one line in it, and every automation switchable from the app.

```apex
trigger ContactTrigger on Contact(
    before insert,
    after insert,
    before update,
    after update,
    before delete,
    after delete,
    after undelete
) {
    TriggerDispatcher.run('Contact');
}
```

That is the whole trigger. The dispatcher reads `Automation_Registry__mdt` for that object, in
`Execution_Order__c` order, builds each `Handler_Class__c` with `Type.forName` (qualified with the
running package's namespace, falling back to the bare name when there is none), and runs each one
(ADR-0017). A module ships its handler class and its registry record and never edits another
feature's trigger or handler. A handler that cannot be built is skipped with a warning in the
Error Log: one broken automation does not stop a person saving a record.

`TriggerDispatcher.run(new ContactTriggerHandler())` remains, for tests and for an object with
exactly one handler.

A handler extends `TriggerHandler` and overrides only the contexts it needs. The dispatcher works
out which context it is in, then checks three things before it invokes anything: a per transaction
bypass (`AutomationControl.bypass(name)`), the org wide pause
(`Nonprofit_Settings__c.Automation_Paused_Until__c`), and the automation's own switch (a row on
`Automation_Setting__c`, keyed by the registry's developer name). Anything a handler throws is
written to the Error Log first, then reported to the person saving the record: `addError` with a
plain language message in a before context, a rethrow in an after context.

A handler guards itself against recursion with `claimRunFor(phase, recordIds)`, which hands back
the records this handler has not already processed in this transaction. The guard is per record on
purpose: one DML of 400 records fires the trigger twice with statics preserved, so a guard that
claimed the whole phase would process 200 records and silently skip the rest.

Whatever a handler throws reaches the Error Log through an `Error_Log_Event__e` platform event
published immediately, not through an insert. Almost every failure worth recording ends in a
rollback, and an insert in that transaction would be rolled back with it: the entry that says what
went wrong would disappear exactly when it is needed. `ErrorLogWriter` publishes,
`ErrorLogEventTrigger` and `ErrorLogEventHandler` write the row, and a direct system mode insert
remains only as the fallback for when publishing itself fails.

A handler another package ships must be `public`, annotated `@NamespaceAccessible`, and have a
no-argument constructor, so that `Type.forName` can build it. Core's own shared classes
(`TriggerDispatcher`, `TriggerHandler`, `AutomationControl`, `ErrorLogger`, `SettingsService`,
`TestDataFactory`) are `public` and `@NamespaceAccessible` for the same reason, and never `global`
(ADR-0017): `global` is a permanent API commitment, and this is internal plumbing.

An automation with no `Automation_Setting__c` row still runs, so a newly shipped automation works
the moment it is installed. `AutomationControl.ensureDefaults()` materializes the missing rows
from `Automation_Registry__mdt` and never touches a row the administrator already has.

**v0.1 ships the framework with no triggers and an empty registry.** Feature C-01 adds the first
two handlers, their triggers, and their `Automation_Registry__mdt` records in one change.

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

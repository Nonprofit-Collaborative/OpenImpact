# Vendored: apex-rollup

Open Impact Core carries a patched copy of the apex-rollup aggregation engine as source. This file
records what was taken, from where, what was changed, and how to take a newer upstream version.
The decision and its reasoning are in
[ADR-0015](../../../../docs/architecture/decisions/0015-vendor-apex-rollup-behind-adapter.md);
the source-level evaluation that preceded it is in
[rollup-library-evaluation.md](../../../../docs/architecture/reference/rollup-library-evaluation.md).

> **A note on wording.** `scripts/ci/check-standard-objects.sh` fails the build if any file under
> `packages/core` names one of the Sales Cloud standard objects Core may not depend on. This file
> lives under `packages/core`, so it does not spell those names out either. Where it says "the
> upstream sales object" or "the upstream marketing object", ADR-0015 and the evaluation document,
> both of which live under `docs/` where the names are allowed, say which object is meant.

## Upstream

| | |
| --- | --- |
| Repository | https://github.com/jamessimone/apex-rollup |
| Author | James Simone |
| License | MIT (`LICENSE` in this directory, copied verbatim) |
| Vendored commit | `6dc353c670fc381a56ac29968be2d1fbf7f60527` |
| Version tag | v1.7.44 |
| Upstream release date | 2026-07-30 |
| Date vendored | 2026-09-07 |
| Vendored into | `packages/core/vendor/apex-rollup/main/default/` |

The commit hash above is the one named in ADR-0015. It exists upstream and is the tip of the
v1.7.44 release, so no substitution was needed.

## License and attribution

apex-rollup is MIT licensed, `Copyright (c) 2019 James Simone`. MIT permits redistribution in
source and binary form, including inside a managed package, on one condition: the copyright notice
and the permission notice must travel with the copies. That is what `LICENSE` in this directory is
for, and it must stay next to the vendored source in every build that ships it.

The vendored code is redistributed inside Open Impact Core under the Open Impact project license,
with the upstream MIT notice preserved unchanged. Open Impact claims no copyright over the upstream
code; the local patches below are Open Impact's and are offered under the same terms.

## What was copied

| Upstream path | Vendored path | Contents |
| --- | --- | --- |
| `rollup/core/classes` | `main/default/classes` | 32 Apex classes, the engine |
| `rollup/core/objects` | `main/default/objects` | `Rollup__mdt`, `RollupControl__mdt`, `RollupGrouping__mdt`, `RollupOrderBy__mdt`, `RollupPlugin__mdt`, `RollupPluginParameter__mdt`, `RollupSettings__c`, `RollupState__c` |
| `rollup/core/customMetadata` | `main/default/customMetadata` | 4 default records (`RollupControl.Org_Defaults` and the three plugin rows) |
| `rollup/tests/classes` | `main/default/classes` | 20 test classes |
| `rollup/tests/testSuites` | `main/default/testSuites` | `ApexRollupBaseTestSuite` |

Upstream keeps core and tests in sibling directories. Both land in one source-format
`main/default` tree here because the Salesforce source format has one `classes` folder per package
directory and the class names do not collide.

## What was excluded, and why

| Upstream path | Why not vendored |
| --- | --- |
| `rollup/app` | The upstream administrator surface: Lightning app, tab, LWC, content assets, permission sets, profiles. ADR-0015 rules it out. The Open Impact console is the only rollup UI, and `Rollup__mdt` is never shown to an administrator. |
| `rollup-namespaced` | A second copy of the same source built under the `please__` namespace. Useful upstream as proof that the library survives a namespace; nothing to vendor. |
| `plugins/` | Optional logger and callback packages with their own package dependencies (including Nebula Logger). Out of scope, and ADR-0003 keeps Core's dependency graph empty. |
| `extra-tests/` | Upstream's unpackaged test scaffolding, including custom objects and standard object field extensions used only in a scratch org. Not packageable and not needed. |
| `rollup/core/profiles/Admin.profile-meta.xml` | An org shape, not package content. Profiles are not shipped by Open Impact. |
| `rollup/core/layouts/` | Page layouts for the upstream custom metadata types. The administrator never opens those records, so the layouts are dead weight in the package. Custom metadata types deploy without them. |
| `rollup/core/flexipages/Rollup_State.flexipage-meta.xml` | Upstream admin UI for `RollupState__c`. Same reason as the layouts. |
| `rollup/core/invocableactionextensions/` | Flow action extensions that surface the upstream invocable actions to Flow Builder. Open Impact drives the engine from Apex through `RollupAdapter`; no upstream invocable action is offered to administrators. |
| `rollup/core/dw/jsonToRollupState.dwl` | Removed by patch D below; the JSON serialization fallback replaces it. |
| Repository root files (`README.md`, `media/`, `package.json`, `sfdx-project.json`, CI workflows) | Upstream project scaffolding and documentation images. Not package content. |

## Project configuration

`sfdx-project.json` needs no change. `packages/core` is already a package directory, the Salesforce
source format resolves metadata at any depth beneath one, and `packages/core/vendor/apex-rollup` is
beneath it. No new entry was added to `packageDirectories`, and none should be: a second entry for
the vendor path would make it a separate package.

If a future tool insists on an explicit path (some `sf project deploy validate` and static analysis
invocations take an explicit source directory), pass `packages/core` and let it walk down, rather
than adding a package directory entry.

## Local patches

Five patches are applied on top of the vendored commit. Four are the patches ADR-0015 names. The
fifth (patch E) is a port the ADR did not anticipate: the ADR counted the forbidden standard object
references in upstream's non-test source and missed the far larger count in upstream's tests.

Every patch is a separate commit on `feature/c-13-vendor-apex-rollup`, so `git log` on any vendored
file shows exactly what Open Impact changed.

### Patch A: no static references to forbidden standard objects

**Files:** `main/default/classes/Rollup.cls`, `main/default/classes/RollupCurrencyInfo.cls`,
`main/default/objects/Rollup__mdt/fields/GrandparentRelationshipFieldPath__c.field-meta.xml`,
`main/default/objects/Rollup__mdt/fields/LimitAmount__c.field-meta.xml`

**What changed.** `Rollup.cls` decided whether a merge could have happened by comparing the calc
item's `SObjectType` against the four standard objects that support record merge, named statically
as `Schema` references. That is now a describe-driven check: `Rollup.MERGEABLE_SOBJECT_NAMES` holds
the same four API names as strings, and each is resolved through the global describe at runtime, so
an object that does not exist in the org is simply absent from the set. That is the behavior a
Platform-only org needs, and an adapter can add to the set.

`RollupCurrencyInfo.cls` held two string literals naming Sales Cloud objects in its dated
multicurrency date-field map. The map is now built from a new vendored custom metadata field,
`RollupControl__mdt.DatedMultiCurrencyFieldMapping__c`, which is empty by default. Dated
multicurrency is a Sales Cloud feature; Core ships no default row for it, and the Connect module can
supply one.

Two `Rollup__mdt` field descriptions used Sales Cloud examples in their help text. They now use
generic parent and child wording.

**Why.** `scripts/ci/check-standard-objects.sh` forbids these names anywhere under `packages/core`,
because Core must deploy and pass its tests on a Platform-only org where those objects do not exist
(ADR-0013, plan Section 4.2). This is not a lint preference: the unpatched code does not compile on
that org shape.

**Re-applying on the next pull.** Look for the `Schema` merge check in the upstream `Rollup.cls` and
for the two string literals in the dated multicurrency map in `RollupCurrencyInfo.cls`. If upstream
has made either configurable in the meantime, take theirs and drop ours. Otherwise re-apply.
`npm run check:standard-objects` is the acceptance test.

### Patch B: `global` narrowed to `public`

**Files:** `Rollup.cls`, `RollupAsyncProcessor.cls`, `RollupFlowBulkProcessor.cls`,
`RollupFlowBulkSaver.cls`, `RollupFlowFullRecalcDispatcher.cls`, `RollupFlowRecalculator.cls`,
`RollupFullRecalcProcessor.cls`, `RollupLogger.cls`, `RollupSObjectUpdater.cls`

**What changed.** Every `global` declaration became `public`. Count: see "Counts" below.

**Why.** In a 2GP managed package a `global` member is a permanent, unremovable API commitment to
subscribers. Open Impact ships none of upstream's invocable actions or extension points to
subscribers; `RollupAdapter`, the only caller, lives in the same package, where `public` is enough.

**Notes on what stays `public` rather than being removed.** `Database.Batchable`,
`Database.Stateful`, `Database.RaisesPlatformEvents`, `System.Queueable`, `System.Finalizer` and
`System.Schedulable` are all satisfied by `public` implementations, so the async machinery needed
nothing else. The `@InvocableMethod` and `@AuraEnabled` members in the vendored classes are kept and
left `public`. An `@InvocableMethod` on a `public` class is invisible to Flow Builder in a
subscriber org, which is the intent: those entry points exist for upstream's own tests and for
in-package callers, not for administrators. If Open Impact ever wants a Flow-callable rollup action
it will be ours, on our own class, over `RollupAdapter`.

**Re-applying on the next pull.** `grep -rn '\bglobal\b' main/default/classes` should return
nothing. Re-run the same substitution on any new upstream file.

### Patch C: documented sharing exception

**Files:** `RollupSObjectUpdater.cls`, `RollupState.cls`, `RollupRepository.cls`

**What changed.** No behavior change. A header comment block was added to the classes that write
records, recording the documented exception required by plan Section 4.13.

**Why.** Plan Section 4.13 requires all Apex to run `with sharing` unless a documented reason
exists. The vendored engine is `without sharing` and does `System.AccessLevel.SYSTEM_MODE` DML. The
documented reason: a rollup total is a property of the whole child record set, so a total computed
under the running user's sharing would be silently wrong for any user who cannot see every child,
and it would then be written to a field every user reads. No user-supplied string reaches these
writes: the object and field names come from `Rollup_Definition__c` rows an administrator created,
and the values are aggregates the engine computed. Upstream's own mitigations remain available,
`RollupControl__mdt.ShouldRunAs__c` and `Rollup__mdt.SharingMode__c`, and `RollupAdapter` sets them.

The `without sharing` declarations and the system-mode DML were deliberately left in place rather
than changed, so that the next upstream pull is a clean rebase. This is a v0.10 security review item
and every remaining system-mode write is in scope there.

**Re-applying on the next pull.** Re-add the comment blocks. They are comments only, so a conflict
here can never be a behavior change.

### Patch D: JSON chained-job state, DataWeave script removed

**Files:** `main/default/dw/` (deleted),
`main/default/objects/RollupControl__mdt/fields/ShouldUseJSONSerializationStrategy__c.field-meta.xml`,
`main/default/customMetadata/RollupControl.Org_Defaults.md-meta.xml`, `RollupState.cls`

**What changed.** The `jsonToRollupState.dwl` DataWeave script resource and its metadata file were
deleted. `RollupControl__mdt.ShouldUseJSONSerializationStrategy__c` now defaults to true and the
shipped `Org_Defaults` record sets it to true, so `RollupState` always takes its JSON
deserialization path. The `RollupState` branch that invoked the DataWeave script was removed with
the resource.

**Why.** ADR-0015 records that the JSON fallback already exists upstream, and that packaging a
`.dwl` resource in a 2GP managed package is unproven. The flag does exist
(`ShouldUseJSONSerializationStrategy__c`, confirmed present on the vendored commit), so the script
is not required for compilation and the risk is removed now rather than deferred to the first
packaging build.

**Re-applying on the next pull.** Delete `rollup/core/dw` again and re-check that
`ShouldUseJSONSerializationStrategy__c` still exists and still gates every DataWeave call site. If
upstream ever makes DataWeave mandatory, this patch becomes a real fork and the decision has to be
re-opened.

### Patch E: vendored tests ported off the Sales Cloud objects

**Files:** `RollupCalcItemSorterTests.cls`, `RollupCalculatorTests.cls`, `RollupEvaluatorTests.cls`,
`RollupFlowBulkProcessorTests.cls`, `RollupParentResetProcessorTests.cls`,
`RollupQueryBuilderTests.cls`, `RollupRelationshipFieldFinderTests.cls`,
`RollupSObjectUpdaterTests.cls`, `RollupStateTests.cls`, `RollupTests.cls`, and a new test-support
custom object `RollupCalcItem__c`.

**What changed.** Upstream's tests use the standard sales object as their calc item throughout, and
the standard marketing object once as a polymorphic activity parent. Neither exists on a
Platform-only org and both are forbidden under `packages/core`. A test-support custom object,
`RollupCalcItem__c`, replaces them field for field:

| Upstream field | Vendored field |
| --- | --- |
| currency amount | `RollupCalcItem__c.Amount__c` (Currency 18,2) |
| account lookup id | `RollupCalcItem__c.Account__c` (Lookup to Account) |
| account relationship | `RollupCalcItem__c.Account__r` |
| close date | `RollupCalcItem__c.CloseDate__c` (Date) |
| stage picklist | `RollupCalcItem__c.StageName__c` (Picklist, ordered as the tests expect) |
| description | `RollupCalcItem__c.Description__c` (Long Text Area) |
| closed flag | `RollupCalcItem__c.IsClosed__c` (Checkbox) |
| `Name`, `Id`, `OwnerId` | unchanged, standard on a custom object |
| marketing object as activity parent | `RollupCalcItem__c`, which has activities enabled |

Nothing else about the tests changed: the same assertions run over the same shapes of data. No
upstream test performed DML on the sales object, which is what made the substitution mechanical.

**Why.** The same reason as patch A, applied to the several hundred further references the ADR did
not count. Without this the vendored tests do not compile on the Platform-only org shape CI treats
as the floor, and `npm run check:standard-objects` fails.

**Cost, honestly stated.** `RollupCalcItem__c` is a test-support object that ships inside the
managed package, because Salesforce has no way to exclude an object from a package while keeping the
tests that need it. It carries no tab, no layout, no permission set entry and no default records, so
no administrator ever sees it, but it is real metadata in a subscriber org and it is the one place
where vendoring cost Open Impact something a subscriber can observe.

**Re-applying on the next pull.** This is the expensive patch. Diff upstream's `rollup/tests`
between the vendored hash and the new tag; only the changed hunks need porting, and the mapping
table above is the whole rule. Run `npm run check:standard-objects` and
`bash scripts/ci/check-apex-offline.sh` afterwards.

### Tooling adjustments (not upstream behavior)

- `packages/core/vendor/` is listed in `.prettierignore`. Upstream formats with its own Prettier
  configuration and reformatting 25,000 lines would destroy every future diff. See "Formatting".
- Em dashes found in vendored comments were replaced, per the repository writing rule.

## Counts on the vendored commit

Filled in by the last commit on this branch.

## Pull procedure for a future upgrade

Upstream is tracked deliberately, not continuously (ADR-0011). Review it on a schedule and whenever
a security advisory names it. To take a new version:

1. `git clone https://github.com/jamessimone/apex-rollup` into a scratch directory and check out the
   new tag.
2. `git diff 6dc353c670fc381a56ac29968be2d1fbf7f60527..<new tag> -- rollup/core rollup/tests` and
   read it. Read the upstream release notes for the range. Decide whether the change is worth taking
   at all: a vendored dependency that works does not need to move.
3. Copy the new `rollup/core` and `rollup/tests` over `main/default/`, keeping the exclusion list
   above. Commit that as an unmodified import, exactly as this branch did, so the patches read as
   diffs.
4. Re-apply patches A through E in order, one commit each. The "Re-applying on the next pull"
   paragraph in each section says what to look for. Where upstream has made a patch unnecessary,
   drop it and say so here.
5. Run, and require all of them to pass:
   - `npm run check:namespace`
   - `npm run check:standard-objects`
   - `bash scripts/ci/check-apex-offline.sh`
   - `sf code-analyzer run --workspace packages/core --rule-selector Recommended --severity-threshold 2`
   - the full Core Apex test suite on the Platform-only scratch org shape
6. Update the commit hash, the tag, the dates, the counts and the patch list in this file in the
   same pull request. A pull that does not update this file is not finished.

## Formatting

`packages/core/vendor/` is excluded from Prettier. Upstream formats its Apex with its own
configuration, and running the Open Impact configuration over the vendored tree would rewrite
roughly 25,000 lines, turning every future upstream diff into noise and making patch re-application
by hand impractical. The exclusion is scoped to the vendor directory; everything else under
`packages/core` is formatted normally.

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

The repository root `LICENSE` names this component and states that its MIT grant is in force and is
not withheld by the project's own license placeholder. Whatever license the owner settles on
(Decision D-08, ADR-0008) applies to Open Impact's own code and cannot narrow James Simone's grant.

**What the first packaging build has to do, because nothing does it automatically.** A plain
`LICENSE` file is not a Salesforce metadata type. It sits in the source tree, it is not deployed by
`sf project deploy start`, and it is not carried into a 2GP package version, so a subscriber org
receives the vendored Apex without the notice next to it. MIT asks that the notice travel with the
copies, so the first packaging build has to place it somewhere the subscriber actually receives it.
Any one of these satisfies that, and one of them must be chosen before the first package version is
promoted:

- an attribution section in the public release notes that ship with the promoted version, naming
  apex-rollup, the copyright line and the MIT text or a link to it;
- the same attribution on a page in the Nonprofit Settings console (an About or Third Party Notices
  entry), which is the surface a subscriber admin can reach without leaving the org;
- a `ContentAsset` or static resource carrying the notice text, deployed with the package.

Until then the obligation is met only for people who read the repository, which is everyone the
project distributes to today, because no package version exists yet (namespace deferred, CLAUDE.md).
This is a packaging-build task, not a blocker on this branch.

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
| `rollup/core/flexipages/Rollup_State.flexipage-meta.xml` | Upstream admin UI for `RollupState__c`. Same reason as the layouts. Excluding the file is not enough on its own: `RollupState__c.object-meta.xml` names it in two `actionOverrides`, and those have to be stripped on every import. See patch F. |
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

Six patches are applied on top of the vendored commit, and the mapping to ADR-0015 is not one to
one. Patch A carries out ADR patches (a) and (b) together. Patch B is ADR patch (c). Patch C is not
ADR patch (d): (d) is an adapter default and is deferred to `RollupAdapter` in C-14, where the
correction below to what those two settings actually do applies to it. Patch D implements an ADR
consequence, which said to settle DataWeave in the first packaging build; it is settled now instead.
Patch E is a port the ADR did not anticipate: the ADR counted the forbidden standard object
references in upstream's non-test source and missed the far larger count in upstream's tests.
Patch F strips the metadata references that point at deliberately excluded files and closes the
packaged visibility of the upstream configuration.

Every patch is a separate commit on `feature/c-13-vendor-apex-rollup`, so `git log` on any vendored
file shows exactly what Open Impact changed.

### Patch A: no static references to forbidden standard objects

**Files:** `main/default/classes/Rollup.cls`, `main/default/classes/RollupCurrencyInfo.cls`,
`main/default/objects/Rollup__mdt/fields/GrandparentRelationshipFieldPath__c.field-meta.xml`,
`main/default/objects/Rollup__mdt/fields/LimitAmount__c.field-meta.xml`

**What changed.** `Rollup.cls` decided whether a merge could have happened by comparing the calc
item's `SObjectType` against the four standard objects the platform supports record merge on, named
statically as `Schema` references. It now asks the describe the same question directly:
`itemType.getDescribe(Schema.SObjectDescribeOptions.DEFERRED).isMergeable()`. No object name appears
in the code at all, the check works on an org where two of those four objects do not exist, and it
is strictly more correct than upstream's list, because any object the org reports as mergeable is
now handled.

`RollupCurrencyInfo.cls` seeded its dated multicurrency date-field map with four Sales Cloud object
names as string literals. The map now starts empty and is populated at runtime through
`RollupCurrencyInfo.overrideDatedMultiCurrency(String objectName, List<String> fieldNames)`, which
is upstream's own public per-object configuration hook and needed no change. Dated multicurrency is
a Sales Cloud feature that Core does not ship; a module that depends on those objects registers them
through the hook. With an empty map `loadProperMinMaxDates` returns before `getCurrencyDate` is
reached, so multicurrency conversion falls back to the undated rate, which is what an org with no
dated conversion rates gets in any case. No new custom metadata field was added.

Two `Rollup__mdt` field descriptions used Sales Cloud examples in their help text. They now use
generic parent and child wording.

**Why.** `scripts/ci/check-standard-objects.sh` forbids these names anywhere under `packages/core`,
because Core must deploy and pass its tests on a Platform-only org where those objects do not exist
(ADR-0013, plan Section 4.2). This is not a lint preference: the unpatched code does not compile on
that org shape.

**Re-applying on the next pull.** Look for the `Schema` merge check in the upstream `Rollup.cls` and
for the seeded string literals in the dated multicurrency map in `RollupCurrencyInfo.cls`. If
upstream has made either configurable in the meantime, take theirs and drop ours. Otherwise
re-apply. Both patches are a handful of lines each.
`npm run check:standard-objects` is the acceptance test.

### Patch B: `global` narrowed to `public`

**Files:** `Rollup.cls`, `RollupAsyncProcessor.cls`, `RollupFlowBulkProcessor.cls`,
`RollupFlowBulkSaver.cls`, `RollupFlowFullRecalcDispatcher.cls`, `RollupFlowRecalculator.cls`,
`RollupFullRecalcProcessor.cls`, `RollupLogger.cls`, `RollupSObjectUpdater.cls`

**What changed.** Every `global` declaration became `public`. Count: see "Counts" below. Two comments
in `Rollup.cls` that described the same members as "global facing" were reworded to "public facing"
in the same pass, and a one line comment was added at the top of `Rollup.cls` recording the patch.

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

**Re-applying on the next pull.** `grep -rnE '^\s*(global|@[A-Za-z]+\s+global)\b'
main/default/classes` should return nothing: no declaration keeps the keyword. A plain
`grep -rn '\bglobal\b'` is not the test, because it also matches the patch comment in `Rollup.cls`
that says the keyword is gone. Re-run the same substitution on any new upstream file.

### Patch C: documented sharing exception

**Files:** `RollupSObjectUpdater.cls`, `RollupState.cls`, `RollupRepository.cls`

**What changed.** No behavior change at all: comment blocks only. A header block was added to the
two classes that write records and to the one that reads them, recording the documented exception
plan Section 4.13 requires.

**The exception, stated once for the whole tree.** The engine writes rollup targets in system mode
by design, because computed totals must be correct regardless of the running user's sharing, and no
user input reaches these writes. A total computed under the running user's sharing would be silently
wrong for anyone who cannot see every child record, and that wrong total would then be written to a
field every other user reads. The values written are aggregates the engine computed from records it
queried; the object and field names come from configuration, which under the planned Open Impact
integration is `Rollup_Definition__c` rows an administrator created and the console validated
(`RollupAdapter` and `Rollup_Definition__c` are C-14 work and do not exist yet).

**Scope: 29 of the 32 engine classes.** The whole vendored tree is `without sharing` by upstream
design. 29 of the 32 engine classes carry the `without sharing` keyword; the remaining three
(`RollupContextFlowPicklistProvider`, `RollupFieldInitializer`, `RollupOperation`) declare no
sharing keyword and so run in the caller's context, which in practice is one of the 29. Plan Section
4.13 asks for a documented reason per class, and this paragraph is that reason for all 29 at once:
they are one engine, they exist only to compute and commit aggregates, and splitting the posture
across them would produce partial totals rather than protection. The three per-class header blocks
mark the classes that actually write (`RollupSObjectUpdater`, `RollupState`) and the one that
queries (`RollupRepository`); the other 26 are covered here. This paragraph is the entry point for
the v0.10 security review item, which treats the vendored tree as in scope and enumerates every
remaining system-mode write.

**What the two upstream settings actually do.** Earlier drafts of this section and of ADR-0015 item
4(d) described them as a sharing mitigation. They are not, and the code says so plainly:

- `RollupControl__mdt.ShouldRunAs__c` selects the execution context only. Its three values are
  Queueable, Batchable and Synchronous Rollup. It has no sharing meaning and no value named User.
- `Rollup__mdt.SharingMode__c` affects queries only. `RollupMetaPicklists` maps it to a
  `RollupRepository.RunAsMode`, which becomes the `System.AccessLevel` on the SOQL that
  `RollupRepository` issues.
- The writes are unconditional system mode. `RollupSObjectUpdater` and `RollupState` pass
  `System.AccessLevel.SYSTEM_MODE` on every DML statement, and no custom metadata setting changes
  that. Setting `SharingMode__c` to User moves the reads, never the writes.

ADR-0015 item 4(d) is corrected in the same pull request.

**Why the posture was left alone.** The `without sharing` declarations and the system-mode DML were
deliberately not changed, so that the next upstream pull is a clean rebase.

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
`RollupFlowBulkProcessorTests.cls`, `RollupFlowTests.cls`, `RollupParentResetProcessorTests.cls`,
`RollupQueryBuilderTests.cls`, `RollupRelationshipFieldFinderTests.cls`,
`RollupSObjectUpdaterTests.cls`, `RollupStateTests.cls`, `RollupTests.cls`, plus a new
test-support custom object `RollupCalcItem__c` and one line in `Rollup.cls`.

**What changed.** Upstream's tests use the standard sales object as their calculation item almost
everywhere, the standard marketing object once as a polymorphic activity parent, the standard
agreement object as a second polymorphic activity parent, the standard support object once as a
concatenation source, and the sales line item object twice as a parent-relationship holder. None of
those exist on a Platform-only org and three of them are forbidden under `packages/core`. One
test-support custom object, `RollupCalcItem__c`, stands in for all of them:

| Upstream field or role | Vendored equivalent |
| --- | --- |
| currency amount | `RollupCalcItem__c.Amount__c` (Currency 18,2, label "Amount") |
| account lookup id | `RollupCalcItem__c.Account__c` (Lookup to Account) |
| account relationship | `RollupCalcItem__c.Account__r` |
| close date | `RollupCalcItem__c.CloseDate__c` (Date) |
| stage picklist | `RollupCalcItem__c.StageName__c` (Picklist, label "Stage", three values) |
| description | `RollupCalcItem__c.Description__c` (Long Text Area) |
| closed flag | `RollupCalcItem__c.IsClosed__c` (Checkbox) |
| forecast category text | `RollupCalcItem__c.Category__c` (Text 255) |
| lead source text | `RollupCalcItem__c.Source__c` (Text 255) |
| agreement activation datetime | `RollupCalcItem__c.ActivatedDate__c` (DateTime) |
| sales line item to sales object relationship | `RollupCalcItem__c.Parent__c` / `Parent__r`, a self lookup |
| `Name`, `Id`, `OwnerId` | unchanged, standard on a custom object |
| marketing or agreement object as activity parent | `RollupCalcItem__c`, which has activities enabled |

Three field labels ("Amount", "Stage", "Name") were chosen to match the labels the group-by table
formatting test asserts on, so that assertion is unchanged rather than rewritten.

Everything else about the tests is unchanged: same assertions, same shapes of data, same counts. No
upstream test performed DML on the sales object, which is what made most of the substitution
mechanical. The changes fall into four kinds, all verified by
`bash scripts/ci/check-apex-offline.sh`, which resolves every field reference against the vendored
object metadata:

1. the type name, in declarations, generics, constructors and `SObjectType` references;
2. field access, both `Type.Field` and `variable.field`;
3. field names inside strings: metadata rows (`RollupFieldOnCalcItem__c`, `LookupFieldOnCalcItem__c`,
   `CalcItemWhereClause__c`, `GroupByFields__c`, `CurrencyFieldMapping__c`, order-by `FieldName__c`),
   Flow input properties, and inline SOQL. These are the ones no compiler checks, so every one was
   read in context first: a literal naming a field on the parent Account, or on a Contact or
   activity calc item, was deliberately left alone;
4. relationship paths, where the standard `Account.` prefix becomes `Account__r.` only where the
   calculation item is the vendored object.

Two further changes in this patch exist only to satisfy the offline checker, and change no behavior:
every `sort` call in `RollupCalcItemSorterTests` now goes through a `List<SObject>` reference,
because `RollupCalcItemSorter` is a `System.Comparator<SObject>` and apex-ls does not model SObject
list covariance; and `Rollup(InvocationPoint)` moved from `protected` to `public`, because apex-ls
does not model an inner class of a subclass reaching a protected superclass constructor, which is
what `RollupAsyncProcessor` does upstream. Both are noted at the site.

**Why.** The same reason as patch A, applied to the several hundred further references ADR-0015 did
not count: it measured the forbidden names in upstream's non-test source (12) and not in its tests
(993 for the sales object alone). Without this patch the vendored tests do not compile on the
Platform-only org shape CI treats as the floor, and `npm run check:standard-objects` fails.

**Cost, honestly stated.** `RollupCalcItem__c` is a test-support object that ships inside the managed
package, because Salesforce offers no way to keep a test and exclude the object it needs. It carries
no tab, no layout, no permission set entry and no default records, so no administrator ever sees it,
but it is real metadata in a subscriber org and it is the one place where vendoring cost Open Impact
something a subscriber can observe.

**Still outstanding.** Two Sales Cloud references survive because they are strings only, never
resolved as types, and neither is a name CI forbids: a `Asset.AssetLevel` where clause in
`RollupEvaluatorTests` (a deliberately invalid relationship for the parent under test) and the
upstream examples in two `Rollup__mdt` field help texts, which patch A already reworded. Nothing
else in the vendored tree names a Sales Cloud object.

**Re-applying on the next pull.** This is the expensive patch. Diff upstream's `rollup/tests` between
the vendored hash and the new tag; only the changed hunks need porting, and the mapping table above
is the whole rule. Run `bash scripts/ci/check-apex-offline.sh` (it catches kinds 1, 2 and 4) and then
read every string literal in the changed hunks by hand, because nothing catches kind 3. Finish with
`npm run check:standard-objects`.

### Patch F: dangling metadata references stripped, upstream configuration made protected

**Files:** `main/default/objects/RollupState__c/RollupState__c.object-meta.xml`,
`main/default/objects/Rollup__mdt/Rollup__mdt.object-meta.xml`,
`main/default/objects/RollupControl__mdt/RollupControl__mdt.object-meta.xml`,
`main/default/objects/RollupGrouping__mdt/RollupGrouping__mdt.object-meta.xml`,
`main/default/objects/RollupOrderBy__mdt/RollupOrderBy__mdt.object-meta.xml`,
`main/default/objects/RollupPlugin__mdt/RollupPlugin__mdt.object-meta.xml`,
`main/default/objects/RollupPluginParameter__mdt/RollupPluginParameter__mdt.object-meta.xml`,
all four files in `main/default/customMetadata/`

**What changed, part one: the dangling FlexiPage reference.** `RollupState__c.object-meta.xml`
carried two `View` `actionOverrides` of `<type>Flexipage</type>` naming `Rollup_State`, the
FlexiPage that is deliberately not vendored. The Metadata API resolves that name at deploy time, so
`sf project deploy start -d packages/core` and `sf package version create` would both have rejected
the object with a missing FlexiPage error. Both blocks were deleted. The three `Tab` overrides and
the final `View` override, all of `<type>Default</type>`, reference nothing and were kept.

The rest of the vendored tree was grepped for references to anything on the exclusion list. Result:
no other reference to a flexipage, a layout, a profile metadata file or an invocable action
extension exists. What the grep does turn up, and what each is:

- `RollupState__c.object-meta.xml` `<compactLayoutAssignment>SYSTEM</compactLayoutAssignment>` and
  `<searchLayouts />`: platform defaults, not references to an excluded layout file. Inert.
- `Profile` in `RollupDateLiteralTests` and `RollupDatetimeTimezoneTests`: SOQL against the standard
  Profile object when building a test user, not the excluded `Admin.profile-meta.xml`.
- DataWeave in comments in `RollupState.cls` and `RollupStateTests.cls`: prose only after patch D.
  No `.dwl` resource and no `DataWeaveScriptResource` call site remains. The comment at
  `RollupStateTests.cls:259` describes an upstream heap limit that no longer applies; it is left as
  upstream wrote it to keep the next diff small.

**What changed, part two: protected visibility.** Every vendored custom metadata type is now
`<visibility>Protected</visibility>` (it was `Public`), and every vendored custom metadata record is
now `<protected>true</protected>` (it was `false`).

**Why.** ADR-0015 says the administrator never sees `Rollup__mdt` or any upstream UI, and CLAUDE.md
says every admin setting lives in the in-app Nonprofit Settings console. Left public, a subscriber
admin would find Rollup Control "Org Defaults" and the six upstream types in Setup and could edit
them, which is a second rollup configuration surface behind the console's back. Protected types and
records are visible and writable only to Apex in the same package, which is exactly the access the
vendored engine and `RollupAdapter` need.

**This cannot be relaxed after the first package version.** Protecting a custom metadata type or
record is a one-way decision at packaging time: once subscribers hold a version, a protected type
cannot be made public, so this has to be right before the first 2GP build, not after it. The reverse
direction is the one that is impossible; deciding protected now keeps the option of never needing to
decide again.

**Still public, and why.** `RollupState__c` and `RollupCalcItem__c` are ordinary custom objects,
which have no protected visibility; `visibility` on them is inert either way. `RollupSettings__c` is
a hierarchy custom setting and does support `Protected` visibility, but it is left `Public` on this
branch because nothing yet reads it in package and the same one-way rule applies: it is called out
here so the first packaging build decides it deliberately rather than by omission.

**Re-applying on the next pull.** Upstream will reintroduce both halves. After the unmodified
import, delete the two Flexipage `actionOverrides` from `RollupState__c.object-meta.xml` again, set
every `*__mdt` object's `<visibility>` back to `Protected`, and set `<protected>true</protected>` on
every file in `customMetadata/`. None of the five checks below catches the FlexiPage reference:
`sf project deploy start -d packages/core` or `sf package version create` is the only thing that
does, and one of them must be run before the import is called finished.

### Tooling adjustments (not upstream behavior)

- `packages/core/vendor/` is listed in `.prettierignore`. Upstream formats with its own Prettier
  configuration and reformatting 25,000 lines would destroy every future diff. See "Formatting".
- Em dashes found in vendored comments were replaced with colons, per the repository writing rule.
  The vendored commit contained exactly two of them, both comment lines in
  `RollupDatetimeTimezoneTests.cls`, which is therefore the one file changed by this rule alone and
  by no lettered patch. Acceptance test: `grep -rnP '\xe2\x80\x94' main/default` returns nothing.
  The pattern is written as the UTF-8 byte sequence so that this file does not itself carry the
  character the rule forbids.

## Counts, and what the checks say

Measured on `packages/core/vendor/apex-rollup/` after all six patches.

| | |
| --- | --- |
| Files vendored | 230 |
| Apex classes, total | 52 |
| Engine classes | 32 (13,359 lines) |
| Test classes | 20 (11,973 lines) |
| Apex lines, total | 25,332 |
| `@IsTest` annotations | 551 (20 class level, 531 method level) |
| Custom metadata types | 6 |
| Custom objects | `RollupState__c`, `RollupSettings__c` (custom setting), `RollupCalcItem__c` (test support, patch E) |
| `global` declarations | 0 (153 before patch B) |

Checks run on the final tree, all from the repository root:

| Check | Result |
| --- | --- |
| `npm run check:namespace` | OK |
| `npm run check:standard-objects` | OK |
| `bash scripts/ci/check-apex-offline.sh` | no compile-level errors |
| `sf code-analyzer run --workspace packages/core --rule-selector Recommended --severity-threshold 2` | exit 0: 0 critical, 0 high, 161 moderate, 1014 low, 50 info |
| `npx prettier --check "packages/core/vendor/**/*.{cls,trigger,xml}"` | passes, because the tree is in `.prettierignore`; see "Formatting" |

No Code Analyzer finding needed a code change, so no patch exists for one. The moderate and low
findings are the shape of a large third party codebase and are dominated by four rules:
`ApexUnitTestClassShouldHaveRunAs` (520), `ApexDoc` (494), `CyclomaticComplexity` (74) and
`CognitiveComplexity` (56), plus 50 copy-paste detections in the test classes. They are upstream's
style, not defects, and rewriting 25,000 lines to satisfy them would cost every future upgrade.
Revisit them only if one is ever promoted to high severity.

What no check here proves: the vendored tests have not been executed. There is no scratch org in
this workspace, `check-apex-offline.sh` does not validate fields inside SOQL, and nothing validates
a field name that lives inside a string. The first scratch org run of the Core suite on the
Platform-only shape is the real acceptance test for patch E, and it should happen before this code
is relied on.

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
4. Re-apply patches A through F in order, one commit each. The "Re-applying on the next pull"
   paragraph in each section says what to look for. Where upstream has made a patch unnecessary,
   drop it and say so here. Patch F is the one that is easy to forget and expensive to miss: strip
   the two Flexipage `actionOverrides` from `RollupState__c.object-meta.xml`, and restore
   `Protected` visibility on the six custom metadata types and `<protected>true</protected>` on the
   four custom metadata records.
5. Run, and require all of them to pass:
   - `npm run check:namespace`
   - `npm run check:standard-objects`
   - `bash scripts/ci/check-apex-offline.sh`
   - `sf code-analyzer run --workspace packages/core --rule-selector Recommended --severity-threshold 2`
   - the full Core Apex test suite on the Platform-only scratch org shape
   - `sf project deploy start -d packages/core` (or `sf package version create`) against a scratch
     org. None of the checks above reads object metadata references, so this is the only one that
     catches a dangling FlexiPage, layout or profile reference reintroduced by the import.
6. Update the commit hash, the tag, the dates, the counts and the patch list in this file in the
   same pull request. A pull that does not update this file is not finished.

## Formatting

`packages/core/vendor/` is excluded from Prettier. Upstream formats its Apex with its own
configuration, and running the Open Impact configuration over the vendored tree would rewrite
roughly 25,000 lines, turning every future upstream diff into noise and making patch re-application
by hand impractical. The exclusion is scoped to the vendor directory; everything else under
`packages/core` is formatted normally.

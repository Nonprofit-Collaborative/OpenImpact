# ADR-0046: Two suites from the same packages, the BarnCRM name, unlocked now and managed at listing

**Status:** Accepted
**Date:** 2026-09-23; amended 2026-09-27 (name settled as BarnCRM, Impact Suite renamed Nonprofit
Suite, owner decision); amended 2026-09-27 (tested as unlocked packages with no namespace before
the namespace and managed packages, owner decision); amended 2026-09-27 (C-30: what the suite
choice in the Setup Assistant does and does not change, builder decision under owner direction)
**Source:** product owner decision (Brandon), plan Section 3 "Suites and packaging", Section 8.3,
Section 11.2 open question 5, and Section 12 decisions D-01 and D-02; amends ADR-0001 (name) and
ADR-0002 (packaging)

## Context

"Open Impact" is not available as a product name (ADR-0001 re-opened the name on 2026-09-06).
Organizations that are not nonprofits want the household and relationship model without gifts,
receipts or nonprofit wording, and the 2026-09-22 parking-lot direction answered that with a
separate CI-built community Households edition. ADR-0002 chose managed 2GP packages, but the
namespace is not registered and pilots need fast iteration. Salesforce documents no conversion
of an installed unlocked package to managed: its Package Migrations feature covers 1GP managed
to 2GP managed only. A package also cannot install another silently; the Tooling API
PackageInstallRequest exists but is not a supported product path.

## Decision

- **The name is BarnCRM** (settled 2026-09-27; tentative from 2026-09-23), written as one word
  with that capitalization, because "barn" alone is unsearchable. barncrm.org and barncrm.com are
  registered. Still open before public use (a listing, a public post, a published package): the
  full trademark search and confirming the namespace in the Dev Hub (plan Section 8.3). The
  namespace stays deferred. This settles the name part of ADR-0001; its namespace deferral stands.
- **The rename is one pass, after C-29 (PRs #163 to #174) merges**, since C-29 changes many of
  the same labels. In order: labels, app, tab and permission set names, help text and
  descriptions, settling plan Section 11.2 questions 23 to 25 at the same time so API names
  change at most once (answered 2026-09-27: one app for both suites, the neutral names accepted
  as BarnCRM names, the `Nonprofit_*` API names renamed `Barn_*`; ADR-0059 records them); then the guides, README, NOTICE and `package.json`; then contributor-typed
  aliases (`oi-test`, `oi-pa`); then the GitHub repository, renamed by the owner. Each pull
  request stays under about 800 changed lines. Accepted ADRs, dated release notes and the
  decision log keep the name that was true when written.
- **Two suites from the same packages.** Nonprofit Suite (named Impact Suite until 2026-09-27) is
  Core plus Giving, with
  Programs, Logic Models, Volunteers, Funders and Connect offered. Community Suite (for-profit
  and other organizations) is Core alone, with the modules that fit (Volunteers, Events later)
  offered; nonprofit-only modules are never offered.
- **One install to start.** An administrator installs Core. The Setup Assistant's first step asks
  which suite; the Nonprofit Edition toggle opens Salesforce's installer for Giving, then offers
  the other modules (C-24, C-30). Each module is one administrator click in Salesforce's installer.
- **Core is neutral (C-29).** Nonprofit wording, the nonprofit app, the giving and receipt settings
  and the nonprofit Setup Assistant steps move to Giving. Core is never split into a base package
  it depends on; ADR-0003 stands. Open question 5 (bundle Core and Giving) is resolved: separate.
- **Unlocked now, managed at listing (amends ADR-0002, does not supersede it).** Packages are
  built and piloted as unlocked packages under the namespace once registered, following
  managed-package rules from the start: anything `global` is permanent, nothing relies on a
  subscriber editing a packaged component, no namespace is hard-coded. The same source becomes
  2GP managed packages for the AppExchange listing with identical API names.
- **Tested first as unlocked packages with no namespace** (owner decision, 2026-09-27). Before
  the namespace is registered, Core, Giving and Connect are built as unlocked package versions
  with an empty namespace and installed in test orgs. Volunteers, Programs and Funders hold no
  metadata yet, so they get no version. The namespace stays deferred and nothing in source
  carries a prefix, so the same source later builds the namespaced packages. What this costs:
  - A namespace cannot be added to a package afterwards. The namespaced unlocked and managed
    packages are new packages, so an org that installed a no-namespace version moves to them
    only by the export, uninstall, install and reimport path of C-31. These versions are for
    test orgs and pilots who accept that in writing, not for production data meant to stay.
  - Without a namespace, BarnCRM's component names are the org's own: an org that already has,
    for example, its own `Fund__c` or `Gift__c` cannot install until the conflict is removed.
    Test orgs are chosen or created clean.
  - `@NamespaceAccessible` has no effect between no-namespace packages (every public class is
    visible to the others), so a cross-package reference that only works without a namespace is
    not caught by these installs. The offline and static checks and review still enforce it.
  - Beta versions install only in scratch and sandbox orgs; a version installed in a Developer
    Edition or production test org must be promoted, which needs 75 percent code coverage.
- **Production pilots on unlocked packages are allowed** (owner decision). Each moves to managed
  through a supported migration: export, uninstall unlocked, install managed, reimport, built and
  rehearsed before listing (C-31).
- **C-30 decision: the suite choice (amended 2026-09-27, builder decision under owner
  direction).** What was built, and what the choice does and does not change:
  - **Stored as a Core setting.** `Suite__c` on `Barn_Settings__c` holds `Nonprofit` or
    `Community`, and is empty until an administrator chooses. It is the Suite row in the
    General section of BarnCRM Settings, audited like every other setting, and the Setup
    Assistant writes it through `SettingsService`.
  - **The first step of the Setup Assistant.** It asks Nonprofit Suite or Community Suite, each
    with one plain line, and then lists the modules that suite offers with their state. It
    takes the place of the module inventory that was step six, keeping that step's key
    (`modules`) so recorded progress carries over: Core alone still has seven steps and Core
    with Giving eight, and an org that marked the inventory done stays finished. The step
    finishes when a suite is saved.
  - **Preselected, never assumed.** The step preselects the Nonprofit Suite when Giving is
    installed and the Community Suite otherwise. An empty setting is never read as a choice, so
    an org that never chose behaves exactly as before.
  - **Which modules a suite lists is data.** Core ships `Suite_Module__mdt`, one row per module
    per suite: the Nonprofit Suite lists Giving (required) then Programs, Logic Models,
    Volunteers, Funders and Connect (optional); the Community Suite lists Volunteers, with
    Events added as a row when it exists. A module with no row for a suite is never listed
    for it, so the Community Suite never shows a module that is only for nonprofits.
  - **No install links yet.** No package version exists and the namespace is not registered,
    so no row carries an installer address and none is invented. A module that is not
    installed shows one sentence and a Learn more link to the admin guide. Each row has an
    empty `Install_Url__c`; a later release fills it in as data and the step shows an Install
    link, with no code change. The Nonprofit Edition toggle that opens Giving's installer is
    therefore that link, once it exists; turning modules on and off stays with the Module
    Manager (C-24).
  - **What the choice changes:** which modules the Setup Assistant lists and offers. Nothing
    else reads it today.
  - **What the choice does not change:** it installs, removes, hides and switches off nothing.
    An installed module's Setup Assistant steps, settings, tabs, permission sets and
    automation are the same whichever suite is chosen: an org with Giving that chooses the
    Community Suite still sees Giving's steps, because installed functionality is never
    hidden. An org that chooses the Nonprofit Suite without Giving is told plainly that the
    suite needs Giving and carries on with the steps every organization answers.
- Supersedes the 2026-09-22 parking-lot direction of a separate CI-built community Households
  edition.

## Alternatives considered

- **One package with hidden modules.** Rejected: Principle 3 says an unused module leaves nothing
  in the org, and Community orgs would carry gift and tax objects.
- **A separate CI-built community edition package.** Superseded: it duplicates Core.
- **Unlocked only.** Rejected: no AppExchange listing and no push upgrades.
- **Managed from day one.** Rejected: blocks fast pilot iteration, and the namespace is not yet
  registered.

## Consequences

- C-29, C-30 and C-31 are added to the plan (Section 5.1, roadmap v0.6, v0.7 and v0.10).
- Pilot orgs must be told in writing, before install, that they will migrate from unlocked to
  managed packages.
- Every review checks managed-package rules now, since unlocked packaging will not enforce them.
- The Setup Assistant's first step (C-30) asks "Nonprofit Suite or Community Suite"; the C-30
  decision above records what the answer does and does not change.
- The trademark search result is recorded here and in plan Section 8.3; a conflict re-opens the
  name under the owner's legal gate.

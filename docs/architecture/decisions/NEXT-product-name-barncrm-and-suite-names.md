# ADR-NEXT: The product is BarnCRM, its suites are the Nonprofit Suite and the Community Suite

**Status:** Accepted
**Date:** 2026-09-27
**Source:** product owner decision (Brandon, 2026-09-27), plan Section 3 "Suites and packaging",
Section 8.3 and Section 12 decision D-01; amends ADR-0001 (name) and ADR-0046 (tentative name,
suite names)

## Context

ADR-0046 recorded BarnCRM as a tentative name, subject to the plan Section 8.3 checks, and kept
"Open Impact" as the working title in the repository, labels and docs until the name was
verified, then to be renamed in one pass. It named the two suites Impact Suite (nonprofits) and
Community Suite (other organizations). Section 8.3 listed the open items before public use: a
full trademark search (USPTO classes 9, 35 and 42, state and common law, with attention to
Barnfox and BARN OWL), registering barncrm.org and barncrm.com, and confirming the namespace in
the Dev Hub.

On 2026-09-27 the owner confirmed that the product is called BarnCRM and that both domains are
registered. The same day the owner renamed the nonprofit suite: "Impact" no longer names
anything in the product.

"Open Impact" appears about 880 times in about 320 tracked files: labels, app and permission set
names, custom setting help text, admin and contributor guides, ADRs, release notes, script
aliases (`oi-test`, `oi-pa`) and the repository name. The unmerged C-29 stack (PRs #163 to #174,
ADR-0059) adds more of them, among them the app label and the permission set labels that plan
Section 11.2 questions 23 and 24 ask about.

## Decision

- **The product name is BarnCRM**, written as one word with that capitalization everywhere,
  because "barn" alone is unsearchable (Section 8.3). "Open Impact" is retired as a working
  title. This settles the name part of ADR-0001 and replaces "tentative" in ADR-0046.
- **The suites are the Nonprofit Suite and the Community Suite.** The Nonprofit Suite is Core
  plus Giving, with Programs, Logic Models, Volunteers, Funders and Connect offered as further
  modules. The Community Suite is Core alone, with the modules that fit. What each suite
  contains is unchanged from ADR-0046; only the nonprofit suite's name changes. The Setup
  Assistant's first step (C-30) asks "Nonprofit Suite or Community Suite".
- **Domains are done.** barncrm.org and barncrm.com are registered (2026-09-27).
- **Still open before public use** of the name (an AppExchange listing, a public post, a
  published package): the full trademark search in Section 8.3, and confirming the namespace in
  the Dev Hub. The namespace stays deferred (ADR-0001), and nothing in source carries a prefix.
  If the search finds a conflict, the owner's legal gate in Section 8.3 applies and a new ADR
  supersedes this one.
- **The rename is one pass, after C-29 merges.** C-29 is approved and already changes many of
  the same labels; renaming first would conflict with all twelve of its pull requests. The
  pass:
  1. Labels, app names, permission set and permission set group labels, tab labels, help text
     and descriptions: "Open Impact" becomes "BarnCRM". This is also where Section 11.2
     questions 23 and 24 are settled, and question 25 (the `Nonprofit_*` API names, permanent
     after the first package version) is decided at the same time so API names change at most
     once.
  2. Admin guide, contributor guide, API docs, README, CONTRIBUTING, NOTICE and `package.json`.
  3. Script and org aliases (`oi-test`, `oi-pa`) only where a contributor types them, with the
     old alias kept working until the orgs are recreated.
  4. The GitHub repository, renamed by the owner (GitHub redirects the old URL).
  Records of the past are not rewritten: accepted ADRs, dated release notes and the plan's
  decision log keep the name that was true when they were written, and gain a pointer here
  where they state the name.
- **The pass is split to stay under about 800 changed lines per pull request**, by area
  (metadata labels, then docs), each squash-merged on its own.

## Alternatives considered

- **Rename now, before C-29 merges.** Rejected: twelve stacked, approved pull requests would
  each need a conflict merge and a fresh org test run, and C-29 itself decides several of the
  labels being renamed.
- **Wait for the trademark search before renaming the repository.** Considered. The owner has
  adopted the name and registered the domains; the search gates public use, not internal
  naming. If the search fails, a second rename costs the same as this one.
- **Keep "Impact Suite".** Rejected by the owner: "Nonprofit Suite" says who it is for, which
  is the plan's plain-English label rule (Section 7.1).

## Consequences

- Plan Sections 3, 5.1 (C-30), 8.3 and 12 (D-01) change in BMemory, then the mirror is
  refreshed. Until then `docs/product-plan.md` still says "tentative" and "Impact Suite"; this
  ADR governs where they differ.
- New work written before the rename pass says BarnCRM in prose and leaves existing labels
  alone, so the pass has one list to change.
- The trademark search remains the owner's; the result is recorded in plan Section 8.3.
- Once the namespace is confirmed, ADR-0001's namespace deferral is superseded by its own ADR.

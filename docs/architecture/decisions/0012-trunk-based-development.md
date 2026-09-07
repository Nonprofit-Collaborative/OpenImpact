# ADR-0012: Trunk-based development with squash merges and an always-releasable main

**Status:** Accepted
**Date:** 2026-09-06
**Source:** plan Section 12, decision D-12

## Context

The team is one architect working with AI sub-agents, plus outside contributors over
time. Work is split by module and layer across several agents at once (plan Section 9.2),
which means many short-lived branches touching a shared set of metadata files.

Git flow, with long-lived develop and release branches, is designed for a different
problem: coordinated releases from a team large enough that integration is a scheduled
event. Applied here it would add merge overhead and long-lived divergence between
branches, which is exactly what hurts when several agents edit permission sets, the
settings console navigation, custom labels, and layouts in the same week (plan Section
9.2 calls those files merge-conflict magnets).

The release process (plan Section 7.5) also assumes a releasable trunk: merge to `main`
with CI green, then create package versions from it.

## Decision

**Trunk-based development.** `main` is always releasable. Feature branches are created
per issue, are short-lived, and are **squash-merged** into `main`. Pull requests are kept
under roughly 800 lines of change; larger ones are split (plan Section 9.3).

**Release branches `release/0.x` exist only when a hotfix is needed on an already
promoted package version.**

Every merge to `main` requires CI green: Apex and Jest tests on the four org shapes, and
Salesforce Code Analyzer with zero high or critical findings.

## Alternatives considered

- **Git flow**: long-lived develop and release branches, more merge overhead, and
  divergence that makes the shared-metadata conflicts worse. Rejected as unnecessary
  ceremony for this team size.
- **Merge commits instead of squash**: preserves each agent's intermediate commits, which
  are numerous and rarely meaningful on their own, and makes the history harder to read
  and to bisect.
- **Direct commits to `main` without pull requests**: removes the review gate, and plan
  Section 7.4 makes review by a second agent or human part of the definition of done.

## Consequences

- One commit per feature on `main`, which makes the history readable and release notes
  straightforward to assemble.
- Short-lived branches keep the shared-metadata conflict surface small, which is what
  plan Section 9.2 asks for by assigning one agent to integrate shared metadata files.
- `main` must actually stay releasable, so a red build is the highest-priority work in
  the repository, not something to route around.
- Versioning is `0.<iteration>.<patch>` until the AppExchange listing, then
  `1.<minor>.<patch>`, and `main` is tagged `v0.N.0` at promotion (plan Sections 4.3 and
  7.5).
- Changing the versioning scheme is an escalation to Brandon (plan Section 11.4).

# ADR-0007: Salesforce CLI plus GitHub Actions, CumulusCI optional later

**Status:** Accepted
**Date:** 2026-09-06
**Source:** plan Section 12, decision D-07

## Context

The project needs a build and release toolchain that creates scratch orgs, deploys source
in SFDX format, runs Apex and Jest tests across four org shapes, runs Salesforce Code
Analyzer as a required gate, and creates and promotes package versions.

NPSP was built with CumulusCI, Salesforce.org's open source build tool. CumulusCI is
capable and handles multi-package orchestration, dependency installation, and org
lifecycle well. It is also an additional tool with its own concepts, its own YAML, and
its own learning curve, and it is not what a Salesforce developer learns first.

Principle 7 and plan Section 8.2 set a contributor experience target: clone to a running
scratch org with sample data in under ten minutes, via one script, for a contributor who
may be an administrator rather than a professional developer. Plan Section 4.3 states the
requirement directly: a contributor who knows only `sf` must be able to work.

## Decision

The toolchain is the **Salesforce CLI (`sf`) with scratch orgs, source-tracked metadata
in SFDX source format, and GitHub Actions for CI**. Org lifecycle is handled by shell
scripts in `scripts/org/` (create scratch org, install dependencies, seed sample data)
and release steps by scripts in `scripts/release/`.

**CumulusCI is not required.** It may be adopted later if multi-package orchestration
becomes painful, and that adoption is itself recorded as a new ADR.

## Alternatives considered

- **CumulusCI from the start**: better multi-package orchestration and a proven path
  (NPSP used it for a decade), but it raises the barrier for the contributors we most
  want, and most of what it provides is not needed until several packages exist.
- **A third-party build tool or a bespoke Node build**: adds a dependency and a
  maintenance burden with no capability the CLI lacks.

## Consequences

- A contributor needs one tool they probably already have, plus git.
- Multi-package orchestration is our own script code. That cost rises as packages are
  added, and the honest trigger for revisiting this decision is the point where those
  scripts start reimplementing CumulusCI. Recording that revisit as an ADR is required.
- CI runs on four scratch org definitions in `config/scratch-defs/`: Platform-only, Sales
  Cloud, Sales Cloud with NPSP installed, and Person Accounts enabled (plan Section 7.3).
  See ADR-0013 for what the Platform-only definition can and cannot actually verify.
- Salesforce Code Analyzer (PMD, ESLint, retire-js, Graph Engine) runs as a required
  check on every pull request with zero high or critical findings allowed. Plan Section
  7.2 identifies this as the single best predictor of passing security review.
- Package versions are created and promoted with `sf package version create` and `sf
  package version promote`, from the Dev Hub that will own the listing (ADR-0002).

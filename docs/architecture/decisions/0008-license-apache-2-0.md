# ADR-0008: License: Apache-2.0

**Status:** Proposed, pending Brandon
**Date:** 2026-09-06
**Source:** plan Section 12, decision D-08

## Context

The project is open source and free, listed on the AppExchange, and intended to be
contributed to by people outside the original author (plan Section 1.4 sets three
external contributors as part of the definition of done for v1.0). It needs a license
before the repository is public.

Two candidates are on the table.

**Apache-2.0** is a permissive license with an explicit patent grant: contributors grant
a patent license covering their contributions, and that grant terminates for anyone who
brings a patent action against the project. It also requires attribution and a NOTICE
file, and states contribution terms explicitly.

**BSD-3-Clause** is the NPSP precedent. NPSP has been BSD-3-Clause on GitHub since 2008,
and the nonprofit Salesforce community is familiar with it. It is shorter and has no
patent language at all.

Both are permissive, both are compatible with commercial reuse, and both are acceptable
for an AppExchange listing. The difference that matters is the patent grant.

Plan Section 11.2 marks this as a blocking question for Brandon, and plan Section 9.1
item 2 tells the builder to confirm it on day one.

## Decision

**Apache-2.0**, proposed. The explicit patent grant protects both adopters (a nonprofit
installing the package) and contributors (a developer whose employer holds patents) in a
way BSD-3-Clause does not.

This ADR stays in **Proposed** status until Brandon confirms. It is one of two blocking
decisions in plan Section 9.1 item 2, alongside the Dev Hub choice. Development proceeds
in the meantime; only making the repository public depends on it.

## Alternatives considered

- **BSD-3-Clause**: the NPSP precedent and familiar to the community, but silent on
  patents. Acceptable if Brandon prefers continuity with NPSP.
- **A copyleft license (GPL or AGPL)**: incompatible with the goal of unrestricted reuse
  by nonprofits, consultancies, and other AppExchange apps, and a poor fit for packaged
  Salesforce metadata. Not considered seriously.
- **A contributor license agreement instead of a license-level patent grant**: rejected
  separately in plan Section 8.2, which chooses Developer Certificate of Origin sign-off
  on commits over a CLA, for lower friction with adequate protection.

## Consequences

- A `LICENSE` file, a `NOTICE` file, and Apache-2.0 headers where the license expects
  them.
- DCO sign-off is required on commits (plan Section 8.2), and the pull request template
  and CI check must reflect that.
- Vendored third-party code must carry a compatible license, which constrains the rollup
  library evaluation in ADR-0011 (MIT and BSD are compatible; copyleft is not).
- If Brandon chooses BSD-3-Clause instead, this ADR is superseded rather than edited, and
  the successor records the reason.

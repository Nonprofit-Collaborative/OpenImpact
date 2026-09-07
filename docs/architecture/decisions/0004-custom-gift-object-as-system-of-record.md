# ADR-0004: Custom Gift object as the gift system of record, with optional mirrors

**Status:** Accepted
**Date:** 2026-09-06
**Source:** plan Section 12, decision D-04

## Context

This is the single most consequential architectural choice in the product (plan Section
3.3 item 5). There are three plausible homes for a received donation:

1. **Opportunity**, as NPSP does. Opportunity is a Sales Cloud object. It is unavailable
   on Salesforce Platform licenses, and it carries sales pipeline semantics (Stage,
   Probability, Close Date, Forecast Category) that confuse nonprofit staff and that
   every nonprofit implementation spends time suppressing.
2. **Gift Transaction**, as Agentforce Nonprofit does. It is an Industries object,
   available only with Nonprofit Cloud licensing, which the target customer cannot
   afford or administer (plan Section 1.2 and ADR-0009).
3. **A custom object we own.**

Plan Section 4.2 makes the Platform-only org shape the floor: Salesforce Platform
licenses are the cheapest path for the target customer beyond their ten free Power of Us
licenses, and everything in Core, Giving, Volunteers, Programs, and Funders must work
there. Options 1 and 2 are both incompatible with that floor.

Against this stands ecosystem compatibility. A large amount of nonprofit Salesforce
tooling, and a large amount of consultant knowledge, assumes donations are Opportunities.
NPSP rollups, NPSP soft credits, and many AppExchange apps read Opportunity.

## Decision

**`Gift__c` is the gift system of record.** It is a custom object in the Giving package,
with nonprofit semantics: donor (a Contact or an Account, one required, never both),
date, amount, type, status, appeal, acknowledgment state, receipt number, and links to
tribute, matching gift, and commitment (plan Section 4.11).

**Opportunity and Gift Transaction are optional one-way mirrors in the Connect package**
(plan Section 4.12), never the source of truth by default. Connect's Opportunity mirror
offers an "Opportunity is source" option for orgs whose online giving tool writes
Opportunities; exactly one direction is active per org, chosen in Settings, with a
reconciliation report.

No hard reference to Opportunity, Campaign, Case, Lead, or any Industries object exists
in Core, Giving, Volunteers, Programs, or Funders. Connect reaches those objects through
dynamic Apex only (plan Section 4.2 and 4.12).

## Alternatives considered

- **Opportunity as the gift**: ties the entire product to Sales Cloud licensing, which
  is the cost the target customer most needs to avoid, and imports sales semantics that
  plan Section 3.3 explicitly rejects.
- **Gift Transaction as the gift**: creates an Industries dependency that contradicts
  Principle 4 and ADR-0009, and inherits batch-only rollups through the Data Processing
  Engine (plan Section 3.5).
- **Both, with a mode setting choosing the source of truth**: doubles the rollup surface,
  the import surface, and the test matrix, for a benefit the mirrors already provide.

## Consequences

- The full product runs on Platform licenses, which is the large cost win for the target
  customer and the hedge against Power of Us terms changing (plan Section 11.1).
- Nonprofit staff see nonprofit fields, with no Stage or Probability to explain away.
- **Risk:** a custom gift object alienates NPSP-dependent apps and consultants. The
  mitigation is the Opportunity mirror (X-01) in v0.6, documented clearly, plus NPSP
  coexistence mode which turns the mirror on by default so existing NPSP rollups and
  dependent apps keep working during a transition (plan Section 4.5).
- Adding a standard-object reference outside Connect is an escalation to Brandon, not a
  builder decision (plan Section 11.4).
- Refunds are new gifts with a negative amount linked to the original, never edits, which
  is only possible because we own the object (ADR-0010).

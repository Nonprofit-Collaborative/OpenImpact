# ADR-0009: No Person Account, Industries, OmniStudio, Data Cloud, or Experience Cloud dependency

**Status:** Accepted
**Date:** 2026-09-06
**Source:** plan Section 12, decision D-09

## Context

Principle 4 states the requirement: compatible by design, dependent on nothing special.
The product runs on Platform licenses, uses no Industries objects, no OmniStudio, no Data
Cloud, and no Person Account requirement, and where standard Salesforce objects exist
their use is optional and configurable, never required (plan Section 1.3).

The reason is the customer. Small and medium nonprofits typically run on ten free Power
of Us licenses plus a handful of paid ones, have no full-time Salesforce administrator,
and cannot buy or administer Industries capability (plan Section 2.1 and 1.2). Agentforce
Nonprofit is architecturally more capable and is also the thing they cannot afford to run
without help. Building on its primitives would reproduce exactly the barrier we exist to
remove.

There is a second reason. Plan Section 11.1 lists "Salesforce changes the platform or
Power of Us terms" as a low-likelihood, high-impact risk, and names the Platform-license
floor as the hedge. Plan Section 4.2 turns this into hard rules, and plan Section 11.4
makes any exception an escalation to Brandon rather than a builder decision.

## Decision

No package depends on Person Accounts, on any Industries object or permission set
license, on OmniStudio, on Data Cloud, on CRM Analytics, on Experience Cloud, or on
Marketing Cloud.

Specifically:

- **No hard reference to Opportunity, Campaign, Case, Lead, or any Industries object in
  Core, Giving, Volunteers, Programs, or Funders.** References live only in Connect, and
  even there behind dynamic Apex (`Schema.getGlobalDescribe`, `Type.forName`, generic
  `sObject` code) so that Connect installs where the objects exist and degrades
  gracefully where they do not (plan Section 4.2 and 4.12).
- **No dependency on Person Accounts, but full support when enabled**, through junction
  membership mode (ADR-0005).
- **Standard reports and dashboards only.** No paid analytics add-on.
- **Multi-currency and Platform Encryption** are not supported in v1 but must not break
  when present; Health Check detects and warns.

Everything in Core, Giving, Volunteers, Programs, and Funders must work on the
Platform-only org shape, which CI verifies (ADR-0013).

## Alternatives considered

- **Building on Nonprofit Cloud primitives** (Gift Transaction, Party Relationship
  Groups, Data Processing Engine rollups): more capability for free, at the price of
  requiring the licensing and the administration burden the target customer cannot bear.
  Rejected; this is the same reasoning that produced ADR-0004 and ADR-0005.
- **Requiring Sales Cloud** so that Opportunity and Campaign are always available:
  cheaper to build, and it prices out the customer. Rejected.
- **Requiring Person Accounts** to get one uniform person model: irreversible once
  enabled in an org, which plan Section 1.2 names as a specific complaint against
  Agentforce Nonprofit. Rejected.

## Consequences

- Some capability is simply unavailable to us and must be built: rollups (ADR-0011) are
  the largest example, because the Data Processing Engine is not an option.
- Connect's dynamic Apex is harder to write and harder to test than direct references,
  and it needs a documented convention (scheduled for v0.6 in plan Section 6).
- The Platform-only CI shape is the enforcement mechanism, and its limits are recorded in
  ADR-0013.
- Adding any package dependency, or a standard-object reference outside Connect, is an
  escalation to Brandon (plan Section 11.4).

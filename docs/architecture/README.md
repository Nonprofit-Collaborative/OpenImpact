# Architecture

This folder holds the durable technical record for Open Impact: the platform-neutral
data specification and the decisions that produced the code. The product plan
(`docs/product-plan.md`) says what we are building and why. This folder says how it is
shaped, and it is the place a contributor or an AI agent reads before writing metadata
or Apex.

## What lives here

| Path | Contents |
|---|---|
| `canonical-model.md` | The platform-neutral specification of every entity: attributes, types, relationships, business rules, and the Salesforce implementation each entity maps to. |
| `decisions/` | Architecture Decision Records (ADRs), one file per decision, numbered `NNNN-kebab-title.md`. |
| `decisions/README.md` | The ADR index and the procedure for adding one. |

Nothing else belongs here. Admin-facing instructions go in `docs/admin-guide/`,
contributor process goes in `docs/contributor-guide/`, and per-iteration reporting goes
in `docs/release-notes/`.

## The ADR rule

From plan Section 0 and Section 12:

1. The architecture decisions in plan Section 4 are settled. **They are not re-opened
   without a new ADR** that supersedes the one recording the original decision. A pull
   request that changes a settled decision without an accompanying ADR is rejected on
   review, not debated on the pull request thread.
2. **When a Salesforce platform limitation blocks the plan, the platform wins**, and the
   builder records an ADR describing the limitation, the workaround adopted, and what
   the workaround costs (plan Section 9.3). The design is never silently changed.
3. Decisions listed in plan Section 11.4 are escalated to Brandon rather than made by
   the builder: adding a package dependency, adding a standard-object reference outside
   Connect, adding a required Setup step, changing the household membership abstraction,
   changing versioning or namespace, and anything touching receipt immutability or gift
   amount mutability.
4. An ADR is never edited to change its Decision after it is Accepted. It is superseded
   by a new ADR, and its Status line is updated to point at the successor.

## ADR file format

One decision per file, named `NNNN-kebab-title.md` with a zero-padded four-digit number.
`0000-adr-template.md` is the blank template to copy.

```
# ADR-NNNN: Title

**Status:** Accepted | Proposed | Superseded by ADR-NNNN
**Date:** YYYY-MM-DD
**Source:** plan Section 12 decision ID, or the section that prompted the decision

## Context
## Decision
## Alternatives considered
## Consequences
```

Keep an ADR between roughly 30 and 70 lines. It records reasoning, not implementation
detail; the implementation lives in the code and the canonical model.

## The canonical model rule

From plan Section 4.4:

> **No field is added to a Salesforce object that is not first added to the canonical
> model with a one-line definition.**

This is a hard gate, and it is the first item in the definition of done (plan Section
7.4). In practice: the canonical-model change is the first commit on a feature branch,
before any `.object-meta.xml` or `.field-meta.xml` file is created. The same rule
applies to picklist values, to custom settings keys, and to custom metadata fields, not
only to custom object fields.

The reason is stated in plan Section 4.4: writing the model once in platform-neutral
terms keeps the far-future standalone option open at near-zero cost, and it is the best
documentation we can give to contributors and to AI agents working on one module without
reading the rest.

## House style for this folder

- No em dashes. Use colons, commas, or parentheses.
- No namespace prefix in any API name. The namespace is deferred (plan Section 4.3) and
  the source is namespace-agnostic; write `Household_Member__c`, never a prefixed form.
- Plain nonprofit language in definitions, so an admin can read the model and recognize
  their own data.

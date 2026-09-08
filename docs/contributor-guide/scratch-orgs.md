# Scratch orgs

Open Impact is verified against five org shapes, matching the license and package
configurations described in the product plan (Section 4.2). Each shape has a scratch org
definition in `config/scratch-defs/`. Four of them any Dev Hub can create; the fifth needs
an entitlement, and is described below.

## The shapes

| Shape           | Definition file                            | What it verifies                                                                                                                             |
| --------------- | ------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Platform only   | `config/scratch-defs/platform-only.json`   | The floor: Core, Giving, Volunteers, Programs, and Funders all work with no Opportunity, Lead, Campaign, Case, or Product objects available. |
| Sales Cloud     | `config/scratch-defs/sales-cloud.json`     | Standard Sales/Service objects present; Connect's Opportunity mirror and Campaign sync have real targets.                                    |
| NPSP installed  | `config/scratch-defs/npsp.json`            | Sales Cloud plus NPSP installed; NPSP coexistence mode (Section 4.5).                                                                        |
| Person Accounts | `config/scratch-defs/person-accounts.json` | Person Accounts enabled, simulating the Agentforce Nonprofit shape; junction household mode is required here.                                |
| Nonprofit Cloud | `config/scratch-defs/nonprofit-cloud.json` | The real Agentforce Nonprofit shape, with the Nonprofit Cloud objects present. Needs an entitled Dev Hub: see below.                          |

### The Nonprofit Cloud shape needs an entitled Dev Hub

Scratch org features that map to a licensed product are granted only when the Dev Hub org
itself carries that entitlement. An ordinary Developer Edition Dev Hub creates the first four
shapes and refuses this one, listing the features it can grant, which is the quickest way to
find the right feature string for your entitlement.

Two things follow from that.

**The `NonprofitCloud` feature string in the definition file is unverified.** Nobody has run
this shape against an entitled Dev Hub yet. If creation fails naming an unknown feature, the
error lists what your Dev Hub can grant: take the right name from that list and correct
`config/scratch-defs/nonprofit-cloud.json`. That is the one line expected to need editing.

**Continuous integration does not run this shape by default.** It runs only when the
`SF_NONPROFIT_CLOUD_SHAPE` repository variable is set to `true`, so an unentitled Dev Hub
reports a skipped shape rather than a failed build. Set it once the shape creates cleanly by
hand.

**Most of what this shape would prove is already covered by Person Accounts**, which any Dev
Hub grants: junction membership, the person account paths through households, naming and
greetings, relationships, the sample data loader in junction mode. Coexistence mode is a
setting rather than something inferred at run time, so it can be set explicitly in the Person
Accounts shape. What genuinely needs this shape is `OrgShapeDetector` answering "is Nonprofit
Cloud installed" against a real org rather than a stub.

## Running the script

```bash
scripts/org/create-scratch-org.sh <shape> [alias] [--days N] [--no-sample-data]
```

Example:

```bash
scripts/org/create-scratch-org.sh platform-only my-dev --days 14
```

This creates the scratch org, deploys `packages/core`, assigns every Core permission set it
finds, and (platform-only shape only) runs the license check described below. It then loads
sample data unless `--no-sample-data` is passed, and prints an `sf org open` hint. Target: under
ten minutes from a clean checkout, per the contributor experience target in Section 8.2 of the
product plan.

To remove a scratch org:

```bash
scripts/org/delete-scratch-org.sh <alias>
```

## The platform-only user check, explained

Salesforce scratch orgs always provision Sales Cloud objects, regardless of the requested
edition or features. There is no scratch-org setting that removes Opportunity, Campaign, Lead,
or Case from a scratch org. That means a scratch org's mere presence of those objects cannot be
used to prove Platform-only compatibility.

Instead, `create-scratch-org.sh` verifies Platform-only compatibility two ways:

1. **A CI static check** (`scripts/ci/check-standard-objects.sh`) fails the build if any file
   under `packages/core`, `packages/giving`, `packages/volunteers`, `packages/programs`, or
   `packages/funders` references a Sales/Service or Industries object at all. Source code, not
   the org, is the thing being checked.
2. **A runtime license check**, for the platform-only shape only: the script creates a user with
   the "Salesforce Platform" user license and the "Standard Platform User" profile (using
   `config/users/platform-user.json`, username
   `platformuser@<alias>.openimpact.test`), then assigns every permission set found under
   `packages/core/main/default/permissionsets` to that user with
   `sf org assign permset --on-behalf-of`. The "Standard Platform User" profile cannot see
   Sales/Service objects at all, so if a Core permission set were to grant field- or
   object-level access to something that license cannot see, the assignment fails loudly. A
   passing assignment is direct evidence that Core's permission sets are Platform-license-safe,
   not just that its source code looks clean.

## NPSP: manual install fallback

`scripts/org/install-npsp.sh` installs NPSP and its five dependency packages, in order
(Contacts & Organizations `npe01`, Households `npo02`, Recurring Donations `npe03`,
Relationships `npe4`, Affiliations `npe5`, then NPSP `npsp` itself), using
`sf package install --package <04t> --wait 30 --no-prompt --security-type AllUsers`.

As of 2026-09-07, this repository does not have verified 04t package version IDs for that
install chain: the NPSP GitHub releases page did not surface a confirmed, current GA version id
for the main package or ids for any of the five dependency packages, and
`install.salesforce.org` was not reachable for direct verification from the environment that
built this scaffold. Per the project's hard rule against inventing package IDs,
`NPSP_PACKAGE_IDS` in `scripts/org/install-npsp.sh` is left empty on purpose, and the script
exits with an explanatory message rather than guessing.

**Manual step, until the script is updated with verified IDs:** use the NPSP installer at
<https://install.salesforce.org/products/npsp>, logged in against the target scratch org, to
install NPSP and its dependencies. Once real, verified 04t ids are available, populate
`NPSP_PACKAGE_IDS` in `scripts/org/install-npsp.sh` in the order above.

## Sample data

`scripts/org/seed-sample-data.sh` loads `data/sample/plan.json` via `sf data import tree` if it
exists. It does not exist yet (tracked as C-10 in the product plan: 200 realistic households),
so until then the script prints `sample data not yet available (C-10)` and exits successfully.

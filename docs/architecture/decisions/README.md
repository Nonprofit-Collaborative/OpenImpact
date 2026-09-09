# Architecture Decision Records

One file per decision, named `NNNN-kebab-title.md`. A settled decision is not re-opened
without a new ADR that supersedes it, and a Salesforce platform limitation that blocks
the plan gets an ADR recording the workaround (see `../README.md` for the full rule).

## Index

| # | Title | Status |
|---|---|---|
| [0000](0000-adr-template.md) | ADR template | Template |
| [0001](0001-product-name-and-namespace.md) | Product name "Open Impact" and deferred namespace | Re-opened (name), Accepted (namespace deferral) |
| [0002](0002-second-generation-managed-packages.md) | Second-generation managed packages with one shared namespace | Accepted |
| [0003](0003-core-plus-module-packages.md) | Core package plus separate module packages, feature flags for minor behavior | Accepted |
| [0004](0004-custom-gift-object-as-system-of-record.md) | Custom Gift object as the gift system of record, with optional mirrors | Accepted |
| [0005](0005-household-as-account-record-type.md) | Household as an Account record type with two membership modes behind one service | Accepted |
| [0006](0006-settings-storage-strategy.md) | Settings storage: custom settings, custom objects, and custom metadata | Accepted |
| [0007](0007-sf-cli-and-github-actions.md) | Salesforce CLI plus GitHub Actions, CumulusCI optional later | Accepted |
| [0008](0008-license-apache-2-0.md) | License: Apache-2.0 | Proposed, pending Brandon |
| [0009](0009-no-industries-or-paid-add-on-dependency.md) | No Person Account, Industries, OmniStudio, Data Cloud, or Experience Cloud dependency | Accepted |
| [0010](0010-receipt-immutability.md) | Receipts are immutable; corrections void and reissue; refunds are negative linked gifts | Accepted |
| [0011](0011-evaluate-vendoring-a-rollup-library.md) | Evaluate vendoring a proven Apex rollup library before building one | Accepted |
| [0012](0012-trunk-based-development.md) | Trunk-based development with squash merges and an always-releasable main | Accepted |
| [0013](0013-platform-only-org-shape-verification.md) | How the Platform-only org shape is provisioned and verified | Accepted |
| [0014](0014-cross-package-references-as-record-identifiers.md) | Core holds Giving record identifiers, not lookups | Accepted |
| [0015](0015-vendor-apex-rollup-behind-adapter.md) | Vendor apex-rollup as the aggregation core, behind an OpenImpact adapter | Accepted |
| [0016](0016-receipt-pdf-rendering.md) | Receipt PDFs are rendered by the Visualforce PDF rendering service, called from Apex | Proposed |
| [0017](0017-cross-package-mechanisms.md) | Cross-package mechanisms under one namespace: NamespaceAccessible, per-package settings objects, registry-driven trigger dispatch | Accepted |
| [0018](0018-module-tabs-and-apps.md) | Each module ships its own Lightning app; the Hub links to the module apps | Accepted |
| [0019](0019-custom-setting-picklist-keys-stored-as-text.md) | Nonprofit Settings picklist keys are stored as text | Accepted |
| [0020](0020-module-settings-pages-reached-by-navigation.md) | Module settings pages reached by navigation, Core pages by literal import | Accepted |
| [0021](0021-system-mode-writes-for-package-owned-data.md) | System-mode writes for package-owned data through dedicated writer classes | Accepted |
| [0022](0022-rollup-status-filter-includes-reversed-gifts.md) | Packaged giving rollups include reversed gifts, and count gifts rather than transactions | Accepted |
| [0023](0023-refunded-gifts-keep-their-soft-credits.md) | A refunded gift keeps its soft credits, and the negative gift reverses them | Accepted |
| [0024](0024-receipt-lock-survives-the-automation-switch.md) | The receipt lock survives the automation switch, and lifting it is a deliberate act in Setup | Accepted |
| [0025](0025-retention-reports-read-the-org-fiscal-year.md) | Retention reports read the org fiscal year, and the two fiscal years have to agree | Accepted |
| [0026](0026-retention-report-definitions.md) | What the retention reports count, and the one attribute they needed | Accepted |
| [0027](0027-seasonal-address-swap-runs-in-system-mode.md) | The seasonal address swap runs in system mode, gated at the controller | Accepted |
| [0028](0028-donor-levels-read-a-rollup-and-follow-the-total-down.md) | A donor level labels an existing rollup, and follows that total down | Accepted |
| [0029](0029-shipped-rollups-are-created-by-each-packages-post-install-script.md) | Shipped rollups are created by each package's post-install script | Accepted |

ADRs 0001 to 0012 correspond to decisions D-01 to D-12 in the product plan's decision log
(Section 12). ADR-0013, ADR-0014, ADR-0018, ADR-0019, ADR-0020 and ADR-0021 are builder decisions
recorded under the platform-limitation rule in plan Section 9.3. ADR-0015 records the ADR-0011
evaluation outcome. ADR-0016 is proposed for the owner's decision at v0.4 (plan Section 11.2
item 6). ADR-0022 is a product owner decision on a defect found in G-02. ADR-0023 resolves the rule
collision ADR-0022 recorded as still open, between R-SC5 and R-SC6 in G-08. ADR-0024 is a product owner decision on the escalation ADR-0010
reserved to him by name, made after an access review found the receipt lock was switchable
from the settings console. ADR-0025 and ADR-0026 are builder decisions made while building
G-16, the retention reports. ADR-0027 is a builder decision made while building C-18.
ADR-0028 is a builder decision for G-14, answering the four questions donor levels cannot
be built without. ADR-0029 is a builder decision on a defect found in C-13 and
G-02: the shipped rollup definitions were never created at install.

## Adding a new ADR

1. **Take the next number.** Look at the highest number in this folder and add one. Zero
   pad to four digits. Numbers are never reused, even if an ADR is superseded.
2. **Copy the template.** `cp 0000-adr-template.md NNNN-your-kebab-title.md` and fill in
   every section. Keep it between roughly 30 and 70 lines.
3. **Set the Status honestly.** `Proposed` when it awaits Brandon's confirmation,
   `Accepted` when it is in force. Never edit an Accepted ADR's Decision: write a
   successor and change the original's Status to `Superseded by ADR-NNNN`.
4. **Add a row to the index above**, in number order.
5. **Link it from the plan if it changes a plan decision.** When the ADR supersedes or
   modifies a decision in `docs/product-plan.md` Section 12, update that row in the plan's
   decision log to point at the ADR, so the plan and this folder never disagree about what
   is in force.
6. **Check the escalation list.** Decisions in plan Section 11.4 go to Brandon before an
   ADR is written, not after.

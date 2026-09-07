# ADR-0001: Product name "Open Impact" and deferred namespace

**Status:** Re-opened (name); Accepted (namespace deferral). On 2026-09-06 the owner found "Open Impact" already in use, including by a foundation funding open source work, too close to this project to share a name. "Open Impact" remains only a placeholder working title until a replacement is chosen and vetted (USPTO, AppExchange, GitHub, npm, domains, social handles, namespace). The fallback "OpenCause" needs the same vetting. A new ADR will record the final name.
**Date:** 2026-09-06
**Source:** plan Section 12, decision D-01

## Context

The project needs a name before a repository, a package, or a listing exists, and a
Salesforce namespace before any package version is created. Both are expensive to
change: a namespace is immutable once used, and a listing name carries reputation and
search history.

The name has to be self-explanatory to a nonprofit administrator who has never heard of
us, has to signal that the software is open source, and has to avoid collision with
existing nonprofit technology products, Salesforce programs, and consultancies. The word
"impact" is heavily used across the sector, so distinctiveness rests on the pair of words
and on a consistent visual identity (plan Section 8.3).

Brandon chose the name on 2026-09-06 after a web search found no Salesforce app,
nonprofit software product, or consultancy of that name. Brandon separately deferred
namespace registration on the same date.

## Decision

The product is named **Open Impact**. The fallback name, if a conflict appears during
formal clearance, is **OpenCause**.

The namespace is **deferred**. The candidate is `openimpact`, and it must be verified as
available before it is registered. Until it is registered, all source is written
namespace-agnostic (plan Section 4.3): no namespace prefix is hard-coded anywhere in
Apex, SOQL, LWC imports, Flow, custom labels, static resource references, or permission
set files; the `namespace` field in `sfdx-project.json` stays empty; packaged directories
stay in source format so the namespace can be added with one field change. A CI check
fails the build if the candidate namespace string appears in source.

No 2GP package version is created until the namespace is set. Scratch orgs and unmanaged
deploys are unaffected and proceed normally.

## Alternatives considered

- **"Nonprofit Commons"**: collides with Salesforce.org's Open Source Commons program.
- **"Next Impact"**: echoes Salesforce's own "next generation of Nonprofit Cloud"
  language and would read as a Salesforce product.
- **"Barnraise"**: a strong metaphor for the community model, but not self-explanatory
  to someone scanning an AppExchange listing.
- **"OpenNPC"**: confusable with the Salesforce product it coexists with.
- **Registering a namespace immediately** to unblock package creation: rejected because
  the namespace is immutable and the trademark and entity clearance (ADR-0008 and plan
  Section 8.2) are not finished.

## Consequences

- Development proceeds at full speed; only package version creation is blocked, which is
  not needed until the end of v0.1.
- The namespace-agnostic discipline is a permanent habit, not a temporary one: it is
  cheaper to keep than to retrofit, and the CI grep enforces it.
- Before any public repository, listing, or announcement, the USPTO, the AppExchange
  directory, GitHub, npm, and domain registries must be searched, and the namespace
  confirmed available (plan Section 8.3).
- If clearance fails, renaming to OpenCause costs documentation and repository churn but
  no schema change, because no API name carries the product name.

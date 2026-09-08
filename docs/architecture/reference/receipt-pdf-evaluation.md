# v0.4 receipt PDF generation: evaluation and draft ADR-0016

Research date 2026-09-07. `developer.salesforce.com`, `help.salesforce.com` and `irs.gov`
are blocked by this session's egress policy, so official text was read through search
summaries. Claims marked **(verify)** must be re-checked against official docs and in a
scratch org before code is written.

## 1. What the platform offers today

### 1.1 Visualforce `renderAs="pdf"` plus `PageReference.getContentAsPDF()`

- Mature, packageable in 2GP, no license beyond Platform, no external callout.
- Rendering limits: no web fonts, only fonts on the rendering service; `Arial Unicode MS`
  is the only font covering multi byte character sets; `@page` margin boxes give page
  headers and footers when the page is API 28.0 or later with `applyBodyTag="false"` and
  real `head`/`body` tags; `apex:pageBlock` and similar components render poorly and lack
  double byte fonts; no JavaScript rendered content; no `data:` URI images; response
  before rendering under 15 MB, PDF under 60 MB, images under 30 MB.
- `getContent()` and `getContentAsPDF()` have been **treated as callouts since API 34.0**
  (Winter '16 critical update). Consequences: they cannot run in a trigger; they throw
  `You have uncommitted work pending` if called after DML in the same transaction; in
  async Apex the class must implement `Database.AllowsCallouts`; and each `execute`
  is capped at the callout limit of 10 **(verify the exact post Winter '16 batch
  support, since older documentation says batch cannot use them at all)**.
- In tests, `getContentAsPDF()` returns blank content or fails, so production code is
  conventionally guarded with `if (!Test.isRunningTest())` and the blob is faked. This
  means the PDF bytes are never asserted by an Apex test.

**Verdict:** works for one receipt at a time from a button. The 10 per `execute` callout
cap and the DML ordering rule make it a poor engine for a 40k statement run.

### 1.2 Apex `Blob.toPdf(...)` with the Visualforce rendering service (Spring '26)

- `Blob.toPdf()` now renders HTML through the **same rendering service as Visualforce
  PDF**, with the extended fonts and multi byte support. Shipped in Spring '26 behind the
  release update "Use Visualforce PDF Rendering Service with Apex Blob.toPdf()",
  **enforced in Summer '26**, so every subscriber org has it before v0.4 ships.
- It is plain Apex, not a callout, and community write ups state it works in service
  classes, batch, scheduled and Flow invoked Apex. **(verify: that it is not metered as
  a callout, and its per transaction limits.)**
- Same styling and font envelope as 1.1, since it is the same engine. Assume the same
  image rules until proven otherwise.

**Verdict:** the same proven renderer, reachable from the one context we actually need
(batch), without the callout semantics. This is the material change since the plan was
written.

### 1.3 LWC print via `window.print()`

Best styling fidelity, but the output exists only in the browser's print dialog. There is
no supported way to capture those bytes back into a `ContentVersion` without either a
user save-and-upload step or an external service. Fails ADR-0010: an immutable stored
document is the whole point.

### 1.4 Salesforce (OmniStudio) Document Generation / Document Builder

Included with Industries products; on a standard or Platform org it requires an
OmniStudio licence, the OmniStudio managed package, and Document Generation permission
set licences. Rejected on ADR-0009 and plan Section 4.2 (no paid add on, no OmniStudio,
must work on Platform licences).

### 1.5 A standard Flow action that makes PDFs

None found in core Flow. The only Flow paths are the legacy Quip export action (needs
Quip) and community invocable actions that wrap `Blob.toPdf`. We ship our own invocable.

### 1.6 Pure Apex PDF libraries

No maintained, permissively licensed, production quality pure Apex PDF writer was found.
Everything credible is a callout wrapper (Api2Pdf) or a paid package (BatchPDF). Writing
PDF bytes in Apex means owning font embedding and text layout: custom code where a
platform feature already exists.

### 1.7 Email templates with attachments

A delivery path, not a generation path. `Messaging.EmailFileAttachment` sends the stored
`ContentVersion`, downstream of generation, so the emailed bytes are the stored bytes.

## 2. Decision matrix

| Option | Platform licence | 2GP packageable | No callout | Works in batch | Stores a file | Styling | Maturity | Verdict |
|---|---|---|---|---|---|---|---|---|
| VF `renderAs="pdf"` + `getContentAsPDF()` | Yes | Yes | Callout semantics | Capped at 10 per execute, DML ordering traps | Yes | Limited | High | Fallback |
| `Blob.toPdf()` on the VF rendering service | Yes | Yes | Yes | Yes | Yes | Same as VF | New, GA Summer '26 | **Chosen** |
| LWC `window.print()` | Yes | Yes | Yes | No | **No** | Best | High | Rejected |
| OmniStudio Document Generation | **No** | No | Yes | Yes | Yes | Good | High | Rejected |
| Standard Flow PDF action | n/a | n/a | n/a | n/a | n/a | n/a | Does not exist | Rejected |
| Pure Apex PDF library | Yes | Yes | Yes | Yes | Yes | Poor | None found | Rejected |
| Email template attachment | Yes | Yes | Yes | Yes | Delivery only | n/a | High | Complementary |

## 3. Receipt content rules

### 3.1 United States, IRS Publication 1771

A contemporaneous written acknowledgment must state:

1. Name of the organization.
2. Amount of the cash contribution.
3. For non cash property, a **description** of the property. The organization does not
   state a value; valuation is the donor's responsibility.
4. A statement of whether goods or services were provided in return, and if so a
   description and a **good faith estimate of their value**.
5. Where applicable, a statement that goods or services consisted **entirely of
   intangible religious benefits**.

Thresholds: the donor needs a written acknowledgment for any single contribution of
**$250 or more**; the organization must provide a written disclosure for a **quid pro quo
contribution over $75**, telling the donor the deductible amount is the excess of the
payment over the value of goods and services received. Contemporaneous means received by
the donor before the earlier of the filing date or the due date of the return.

Model sentence from the publication: "Thank you for your cash contribution of $300 that
(organization's name) received on December 12, 2015. No goods or services were provided
in exchange for your contribution." Note the EIN is not on the IRS required list; it is
convention and donors expect it, so we print it, but a receipt is valid without it.

### 3.2 Year end statements

No IRS requirement to send them; near universal practice, sent between about January 10
and January 31 for the prior calendar year. Convention: itemized list of gifts with date,
amount, fund and payment method; a total; the goods and services statement; separate
treatment for in kind and quid pro quo lines. A consolidated statement satisfies the
$250 rule for each listed gift only if each gift carries the required statement, so the
per line goods and services status must be printed, not just a blanket footer.

### 3.3 Canada, CRA (future localization note only, not designed now)

An official donation receipt must carry: the words "official receipt for income tax
purposes", the charity's registered name and CRA address, the registration number in
`123456789 RR 0001` form, a receipt serial number, place of issue, date of donation,
date of issue, donor name and address, amount of the gift, description and value of any
advantage, the eligible amount, an authorized signature, and the CRA website. Omitting
any element voids the receipt. This confirms three schema choices are worth making now
even for a US only v0.4: a serial number field, an advantage value field pattern
(reusable for quid pro quo), and a place of issue on the org identity settings.

## 4. Draft ADR-0016

```markdown

# ADR-0051: The inbound gift API keeps a small permanent surface, and the accounting export marks nothing

**Status:** Accepted
**Date:** 2026-09-23
**Source:** plan Section 4.12 (inbound gift API, accounting export) and Section 5.6, features X-03, X-04 and X-06; builder decision under plan Section 9.3

## Context

X-03 is the first `global` code in the product. Anything `global` in a managed package is
permanent: it cannot be removed or have its signature changed (ADR-0017). Plan Section 4.12
asks for a REST endpoint and a Flow action that accept "a simple JSON gift with donor
matching", idempotent by external ID, and leaves open what a resend, an unknown donor and a
mismatch should do. X-04 asks for gifts by fund, date range and payment method as CSV, with
"a posting flag per gift". An earlier attempt at X-04 replaced that flag with an Accounting
Export Run object, reasoning that Connect cannot mark a gift. Giving now owns G-20
(accounting posting flag and period lock, plan Section 5.2), which is where that flag lives.

## Decision

1. **Four global classes and no more.** `InboundGiftResource` (`@RestResource`, URL mapping
   `/v1/gifts`, one `@HttpPost` method), `InboundGiftAction` (one `@InvocableMethod`),
   `InboundGift` (the request: ten variables) and `InboundGiftResult` (four variables:
   outcome, gift id, error code, message). The REST body is the same shape as
   `InboundGift` and is read strictly, so a misspelled field is refused rather than
   ignored. One gift per REST call; the Flow action takes many. Every other class is public.
2. **Gifts are made the way Giving makes them.** An ordinary `Gift__c` insert in user mode,
   status Received, then `GiftService.applyChosenFunds` for a chosen fund, the path quick
   entry and gift batches use (ADR-0045). Giving's triggers derive the household and apply the
   default allocation. `GiftService` becomes `@NamespaceAccessible`. Amount is above zero with
   at most two decimals; In-kind is refused, since goods have no amount.
3. **A resend finds, never edits.** External Id is the key (R-G7). A resend with the same
   amount answers `existing` with the gift already recorded. A different amount is refused
   as `external_id_conflict`, because two gifts sharing an identifier is a mistake in the
   sending system that must not be settled silently. The API never changes a recorded gift,
   so it cannot touch a receipted one (ADR-0010). A race between two sends is settled by the
   unique index and answered the same way.
4. **Donors are found, never created.** A request names the donor by record id (a person or
   an account) or by email. Email is matched by Core's `ImportMatcher`, the importer's rule:
   the oldest person with that address, and a person stored as an account is always referenced
   by the account. No match is refused as `donor_not_found`.
5. **Every refusal is logged** to the Error Log at Warning with the external id and the error
   code, and no personal data, so Maria sees a gift that did not arrive.
6. **The export writes nothing and stores nothing.** It reads in user mode, so like every
   report it holds the gifts the person running it can see. One row per allocation; a gift
   with none gets one row with no fund. Received, Refunded and Written off gifts; a refund is
   its own negative row on its own date; In-kind is left out. Over 10,000 rows is refused,
   not truncated. No run object. When G-20 ships, marking gifts posted is a Giving service
   the export calls; the earlier reasoning was half right, since Connect cannot own a field on
   a gift but can ask Giving to write one.
7. **The file is built in Apex, not a packaged report,** so its headers never change with a
   field label, dates are ISO 8601 and amounts plain numbers whatever the user's locale, a
   QuickBooks import mapping saved once keeps working, and Jen needs no report export permission.

## Alternatives considered

- **Update the gift on a resend** (R-G7's earlier wording). Rejected: an integration would
  be able to rewrite a receipted gift, and the unique index already stops duplicates.
- **Create an unknown donor.** Rejected for now: it is how an inbound feed fills a database
  with duplicates, and the import framework exists for that job. Adding it later is an
  additive change; removing it would not be.
- **Match organizations by name.** Rejected: names are not unique. An integration names an
  organization by record id.
- **Lenient JSON.** Rejected: a misspelled `fundCode` would put a restricted gift in the
  default fund with a success response.
- **Accounting Export Run object, and a truncated file.** Rejected: a record of each run does
  not answer "which gifts are posted", and a short file that looks complete reconciles to nothing.
- **A system mode count to prove the export is complete.** Rejected: an elevated read of
  gifts the person cannot see. The page and guide say plainly that the file holds visible gifts.

## Consequences

- The four global classes and their field names are supported for the life of the package.
  New optional fields can be added; none can be removed or renamed.
- Setting up the REST endpoint needs Setup (an integration user and its authentication),
  which the platform owns; the admin guide says so. The Flow action needs none.
- Plan Section 4.12's "posting flag per gift" is delivered by G-20, not X-04.
- The export reads ADR-0022's money statuses (Received, Refunded, Written off), so its net
  agrees with the Fund and donor totals. A Pending gift that is later written off therefore
  enters its own, possibly already exported, period, cancelled by the write-off on the day
  it is recorded. Gifts keep no status history, so the export cannot tell such a gift from a
  Received one that was written off; the admin guide says how to handle it.
- The Error Log line for a refusal names the external id and the error code only. The
  message goes to the caller, not the log, because it can repeat what the caller sent.

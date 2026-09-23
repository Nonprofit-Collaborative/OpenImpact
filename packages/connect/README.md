# Open Impact Connect

## Purpose

Adapters that bridge Open Impact to other systems: Opportunity mirror (NPSP and Sales Cloud),
Campaign sync, Gift Transaction mirror (Agentforce Nonprofit), an inbound gift REST API, and an
accounting export. All references to Opportunity, Campaign, and Industries objects live only
here, and only behind dynamic Apex, so Connect installs cleanly where those objects do not
exist and degrades gracefully.

## First ships in

Iteration **0.6**.

## Depends on

- Open Impact Core
- Open Impact Giving

## Status

Built so far (iteration 0.6):

- **Inbound gift API (X-03).** `InboundGiftResource` (REST, `POST .../v1/gifts`) and
  `InboundGiftAction` (the Record Inbound Gift Flow action), both thin over
  `InboundGiftService`, which checks each gift through `InboundGiftRequest`. `InboundGift` and
  `InboundGiftResult` are the request and result.
  These four are the package's only `global` classes and are permanent (ADR-NEXT). Contract:
  `docs/api/inbound-gift-api.md`. Permission set: `Inbound_Gift_API`.
- **Accounting export (X-04).** See `docs/admin-guide/accounting-export.md`.

## How to test it alone

Deploy Core, Giving and then Connect (`scripts/org/deploy-packages.sh` does all three), then
run the `InboundGift*Test` and `AccountingExport*Test` classes.

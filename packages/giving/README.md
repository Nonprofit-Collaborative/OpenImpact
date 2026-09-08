# Open Impact Giving

## Purpose

Gifts, funds and allocations, commitments (pledges and recurring gifts) and installments, soft
credits, tributes, matching gifts, appeals, acknowledgments and receipts, giving rollups and
dashboards, and gift batches.

## First ships in

Iteration **0.2**.

## Depends on

- Open Impact Core

## What is here now

Features G-01 (gifts, allocations, funds), G-04 (refunds and write-offs) and G-05 (appeals):

- **Objects:** `Gift__c`, `Gift_Allocation__c`, `Fund__c`, `Appeal__c`, plus the giving rollup
  target fields on Account and Contact and the Giving module's settings object
  `Giving_Settings__c` (canonical model Sections 18 to 21A and 26).
- **Services:** `GiftService` (household derivation, default allocations, allocation totals,
  refunds and write-offs), the selectors that hold every query, and `GiftController` for the
  screens that come next.
- **Automation:** one trigger per object, each calling the Core dispatcher, with a handler
  registered in `Automation_Registry__mdt` so an administrator can switch it off from the
  console.

Admin guides: [gifts](../../docs/admin-guide/gifts.md),
[funds](../../docs/admin-guide/funds.md), [appeals](../../docs/admin-guide/appeals.md),
[refunds](../../docs/admin-guide/refunds.md).

Permission set entries this package still needs are listed in
[integration/g-01-g-04-g-05.permissions.md](integration/g-01-g-04-g-05.permissions.md).

## Testing it alone

```bash
npm run check:apex
sf code-analyzer run --workspace packages --rule-selector Recommended --severity-threshold 2
```

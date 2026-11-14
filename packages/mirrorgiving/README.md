# BarnCRM Mirror for Giving

## Purpose

Bridges between BarnCRM Giving and standard Salesforce or Nonprofit Cloud objects and outside
systems: Opportunity mirror (NPSP and Sales Cloud), Campaign sync, Gift Transaction mirror
(Nonprofit Cloud), an inbound gift REST API, an accounting export, and the NPSP and Nonprofit
Cloud gift migration kits. References to Opportunity, Campaign and Industries objects live only
here (and in BarnCRM Mirror), and only behind dynamic Apex, so the package installs cleanly
where those objects do not exist and degrades gracefully.

Split from BarnCRM Mirror in release 1.27 (N-09, ADR-NEXT mirror independence) so Mirror needs
only Core. Every class, page, setting and permission set moved whole; nothing was removed.

## First ships in

Release **1.27** as its own package (the features first shipped in Mirror, iteration 0.6).

## Depends on

- BarnCRM Core
- BarnCRM Rollup Builder
- BarnCRM Giving
- BarnCRM Mirror (it keeps `Mirror_Settings__c`, which holds this package's settings)

Nonprofit Edition.

## Status

- **Inbound gift API (X-03).** `InboundGiftResource` (REST, `POST .../v1/gifts`) and
  `InboundGiftAction` (the Record Inbound Gift Flow action), both thin over
  `InboundGiftService`, which checks each gift through `InboundGiftRequest`. `InboundGift` and
  `InboundGiftResult` are the request and result.
  These four are the package's only `global` classes and are permanent (ADR-0051). Contract:
  `docs/api/inbound-gift-api.md`. Permission set: `Inbound_Gifts` (both classes and every
  record grant).
- **Accounting export (X-04).** Permission set: `Accounting_Export`, which also reads the gift,
  allocation and fund fields the file shows. See `docs/admin-guide/accounting-export.md`.
- **Access (ADR-0194, simpler permission sets, D4).** `Salesforce_Records_Sync` opens the Campaign
  sync, Opportunity mirror and Gift Transaction mirror pages; `Inbound_Gifts` is the integration
  user's set, with the Inbound Gift REST class and flow action. Both are Access Add-On rows. The
  Provider Requests tab is Mirror's own `Provider_Requests` set.
- **Campaign sync (X-02).** The `Campaign_Sync` automation on Appeal (`CampaignSyncTriggerHandler`
  over `CampaignSyncService`) copies each appeal to a Campaign before it is saved, and stores
  the link in `Appeal__c.Campaign_Id__c`, a field this package adds to Giving's object.
  `CampaignSyncBatch` is Sync all appeals, started from the `campaignSync` page. Campaign is
  reached only through describe. Off until `Mirror_Settings__c.Campaign_Sync_Enabled__c` is
  switched on. `MirrorGivingPostInstall` creates the automation switches. Permission set:
  `Salesforce_Records_Sync`. See `docs/admin-guide/campaign-sync.md` and canonical model Section 29B.
- **Opportunity mirror (X-01).** The `Opportunity_Mirror` automation on Gift
  (`OpportunityMirrorTriggerHandler` over `OpportunityMirrorService`) copies each gift to its
  Opportunity before it is saved, in Gifts to Opportunities, and stores the link in
  `Gift__c.Opportunity_Id__c`. `OpportunityMirrorBatch` is Run now and the nightly run
  (`OpportunityMirrorSchedulable`); in Opportunities to Gifts it makes gifts through
  `OpportunityGiftService`. `OpportunityMirrorReconciliation` compares a date range. All are
  started from the `opportunityMirror` page. Off until
  `Mirror_Settings__c.Opportunity_Mirror_Direction__c` is chosen. Shared pieces with Campaign
  sync are in `MirrorSync`. Permission set: `Salesforce_Records_Sync`. See
  `docs/admin-guide/opportunity-mirror.md` and canonical model Section 29C.
- **Gift Transaction mirror (X-07).** Copies each received gift to a Nonprofit Cloud Gift
  Transaction, with designations for funds that carry a `Gift_Designation_Id__c`, in runs only:
  `GiftTransactionMirrorBatch` is Run Now and the nightly run (`GiftTransactionMirrorSchedulable`,
  01:35), over `GiftTransactionMirrorService`. The link is `Gift__c.Gift_Transaction_Id__c`; the
  `Gift_Transaction_Mirror` automation (`GiftTransactionMirrorTriggerHandler`) only checks a
  typed link and reports deleted linked gifts. Every Nonprofit Cloud object is named only in
  `GiftTransactionMirrorSchema` and resolved through describe, so the package installs without
  Nonprofit Cloud and the mirror reports itself unavailable there; tests use its stand-ins.
  `GiftTransactionMirrorReconciliation` compares a date range on the `giftTransactionMirror`
  page. Off until `Mirror_Settings__c.Gift_Transaction_Mirror_Direction__c` is chosen and a
  start date is set. Permission set: `Salesforce_Records_Sync`. See
  `docs/admin-guide/gift-transaction-mirror.md` and canonical model Section 29C1.
- **Gift migration kits (MIG-05).** `NpspGiftsKit` and `NpcGiftsKit` with their Migration Kit
  and Import Template Default rows. See `docs/admin-guide/migrating-from-npsp.md` and
  `docs/admin-guide/migrating-from-nonprofit-cloud.md`.
- **Nightly and Health Check.** `MirrorGivingNightlyJobProvider` adds the two mirror runs to
  BarnCRM Nightly Jobs; `MirrorGivingHealthCheckExtension` reports a stalled run. Help text is
  in `BarnHelp_MirrorGiving.json`.

## How to test it alone

Deploy Core, Rollup Builder, Giving, Mirror and then Mirror for Giving
(`scripts/org/deploy-packages.sh` does all five), then run the `InboundGift*Test`,
`AccountingExport*Test`, `CampaignSync*Test`, `MirrorSyncTest`, `OpportunityMirror*Test`,
`GiftTransactionMirror*Test`, `Npsp*Test`, `Npc*Test` and `MirrorGiving*Test` classes. The
Campaign sync and Opportunity mirror tests check that nothing happens on an org without Campaign
or Opportunity, and exercise the copy where they exist.

# ADR-0033: A receipt number comes only from the sequence, so the field is package written

**Status:** Accepted
**Date:** 2026-09-09
**Source:** builder decision on a defect found by a security review of G-13, under ADR-0010,
ADR-0016, ADR-0021 and ADR-0024

## Context

`Giving_Staff` granted `Gift__c.Receipt_Number__c` as editable, and `GiftService.enforceReceiptLock`
deliberately allowed the first write of a number: it refused a change only when the gift already
carried one. So any staff user could type `R-2026-000042` onto a gift, from a list view, the API or
a data load, and three things followed.

It is an irreversible tamper. The gift's amount, date, donor and in-kind description become
immutable at once, and the number cannot be taken off again, because from the next save
`hadReceipt && receiptNumberChanged` refuses it. Undoing it needs `Override_Receipt_Lock`, which
ships granted to nobody (ADR-0024).

The number never passed through `ReceiptNumberSequence`. `Gift__c.Receipt_Number__c` and
`Receipt__c.Receipt_Number__c` carry separate unique indexes, so a hand-typed number does not stop
the sequence issuing that same number later as a consolidated statement. Two receipts carrying one
number is the outcome ADR-0016 says nobody can recover from.

And `ReceiptService.issueForGift` then refuses that gift forever, because a number is present, so
the gift can never be receipted: no receipt record, no document, and a donor with nothing.

A second, narrower gap sat next to it. `GiftService.recordReceiptNumbers` lifted the number branch
with a private transaction wide flag. The seam is otherwise sound: the flag is `private
@TestVisible` and not `@NamespaceAccessible`, the amount, date and donor comparison runs after the
number branch and still refuses, and the `finally` restores the previous value rather than assigning
false, so nesting is safe. Its fault is scope: while it was true, any `Gift__c` DML in the
transaction had the number branch lifted, including the nested update
`MatchingGiftService.applyLinkChanges` makes from the after-update handler. No path writes a receipt
number there today, so it is hardening rather than a live hole.

## Decision

- **A receipt number comes from `ReceiptNumberSequence` or it does not exist.** The receipt lock
  refuses every write to `Gift__c.Receipt_Number__c`, in both directions and including the first
  one, unless the receipting code is renumbering that gift. The first write is not a special case:
  it is the worst one.
- **A gift is never created carrying a number.** `GiftReceiptLockHandler` gains a before insert
  refusal. Nothing in the package inserts one, so a number on an insert was typed by a person.
- **The field is read only in every packaged permission set,** `Giving_Staff` and `Giving_Admin`
  joining `Giving_Read_Only`. It stays on the Gift layout, already marked read only there: staff
  read the number off the gift constantly, and hiding it would cost them that for no gain.
- **The renumbering allowance names the gifts it is for.** The boolean becomes
  `Set<Id> giftsBeingRenumbered`, checked by Id in `enforceReceiptLock`, so the allowance cannot
  reach a gift saved elsewhere in the same transaction.
- **The write moves to system mode, in `GiftReceiptNumberWriter`, under ADR-0021.** A field nobody
  may edit cannot be written in user mode: `Database.update(..., AccessLevel.USER_MODE)` would be
  refused for the very user issuing the receipt. The class is `with sharing`, unlike `ReceiptWriter`:
  what it needs lifted is field level security on one field, not visibility of records the user
  cannot see.
- **The override still reaches all of it** (ADR-0024): a user holding `Override_Receipt_Lock` may
  set or clear a number, on insert or update, and every such save is written to the Error Log at
  Warning severity. That is how an org recovers a gift numbered by mistake, and how it loads
  historical gifts carrying legacy numbers. The administrator's temporary permission set now also
  needs Edit on Gift Receipt Number, which `gifts.md` says step by step.

## Alternatives considered

- **A validation rule refusing a manual change unless the user holds `Override_Receipt_Lock`.**
  Rejected on the ground ADR-0024 settled: a subscriber can deactivate a packaged validation rule in
  Setup, which is exactly the switch that ADR made the receipt lock immune to, and it would put the
  rule back on a switch next door to the one that is bolted down. It also cannot tell the sequence's
  write from a person's, because a validation rule sees no transaction state, so the package's own
  save would have to be excused by a flag field on the record, which is a worse version of the flag
  this change is removing.
- **Field level security alone, with the first write still allowed in Apex.** Rejected: field level
  security is a grant an administrator can hand out in one click, and orgs that already granted it,
  or that run with a profile carrying it, would stay exposed. Enforcement belongs in the automation
  that always runs.
- **Apex alone, leaving the field editable.** Rejected as a worse experience for the same safety: the
  field would go on presenting itself as editable in list views and integrations, and every staff
  member who tried would get a save error instead of a field that was never theirs to fill in.
- **Removing the field from the Gift layout.** Rejected: it is already read only there, and the
  number is what staff quote to a donor on the phone.
- **Loosening `issueForGift` so it receipts a gift that already carries a number.** Rejected: it
  would mint a second document for a number the sequence never issued, which is the collision, not
  the cure.

## Consequences

- A staff user cannot put a receipt number on a gift by any route: not the record page, not a list
  view, not the API, not a data load, not an insert.
- **Loading historical gifts with legacy receipt numbers now needs the override.** That is a real
  cost to a migrating org, and it is the deliberate, logged act ADR-0024 chose over a quiet one. The
  import guide is unchanged because the importer has never mapped that field.
- `GiftReceiptNumberWriter` is a fourth documented system mode writer (ADR-0021), and the narrowest:
  one field, one caller, no reads.
- Tests that used to receipt a fixture by setting the field and saving now call
  `GiftService.recordReceiptNumbers`, which is the door the product uses.
- **Unverified in an org.** No Apex test in this repository has been executed, so the behaviour above
  is reasoned from the code and enforced by tests that have been written and not run. The field level
  security half of it is deployment metadata and has not been deployed.

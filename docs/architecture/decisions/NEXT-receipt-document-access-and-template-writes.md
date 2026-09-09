# ADR-NEXT: A receipt document is reached only through the records a Giving permission set governs

**Status:** Accepted
**Date:** 2026-09-09
**Source:** security review of G-13; ADR-0016 (storage), ADR-0010 (immutability), ADR-0021
(system-mode writes), ADR-0029 (shipped defaults at install), plan Section 4.13

## Context

ADR-0016 says a receipt's bytes live in one `ContentVersion` "linked by `ContentDocumentLink` to
the `Receipt__c` and, per receipt type, to the `Gift__c` (per gift receipts) and to the donor
`Contact` or `Account` (both types)". That sentence was written about where a person would look
for the file. It is also, and this was not noticed, the file's access control list.

**A `ContentDocumentLink` grants access to a file through the record it names, not through
`Receipt__c`.** The packaged permission sets are correct about `Receipt__c`: read only, in all
three Giving sets, and no role holds Edit or Delete on it (R-RC10). None of that governed the PDF,
because the PDF was also linked to the donor's Contact and Account.

The admin guide says (`access.md`) that a role today carries what Core provides and nothing a
module adds, so the ordinary state of an org is a Program Staff or Volunteer Coordinator user
holding `Nonprofit_Staff` and no Giving permission set at all. That user has Read on Account and
Contact. A donor's year end statement, which is their whole giving history for a year plus the
organization's EIN, address and signer, was in the Files related list of a record they open every
day. Nothing in the guide warned anybody, so nobody could have known to look.

Two further things needed deciding while the file was open, both about the same object graph.

**The shipped letters were created by a cacheable method.** `ReceiptController.getTemplates` is
`@AuraEnabled(cacheable=true)` and called `ReceiptTemplateService.installDefaults()`, which inserts.
Apex cannot perform DML in a cacheable method, so on an org that had never issued a receipt the
Receipts console threw on the first screen an administrator opens. It self healed only because the
non cacheable issuing path called the same method later.

**Nothing checked a permission before writing a letter.** `installDefaults` inserted in
`AccessLevel.SYSTEM_MODE`, so any user who could open the page created those records, and
`saveBody` and `activate` wrote in user mode with no custom permission check. The effect was
correct only by accident, because Giving Admin is the only set with Edit on `Receipt_Template__c`.
The body of that record is the letter a donor's accountant reads.

## Decision

1. **A receipt document is linked only to records whose object permissions a Giving permission set
   governs: the `Receipt__c` always, and the `Gift__c` on a per gift receipt.** The donor `Contact`
   and `Account` links are removed. This supersedes the storage sentence in ADR-0016 and nothing
   else in it.
2. **The rule is enforced in `ReceiptWriter.storeDocument`, which throws on any other linked
   entity**, rather than trusted to each caller. The audience of a stored tax document is one rule,
   and a caller passing one more id is exactly how it was widened the first time.
3. **`ShareType` stays `'V'`.** Viewer is the ceiling a link can grant, which is what an immutable
   document needs (ADR-0010, R-RC1). `Visibility` becomes `'InternalUsers'`, which is not the fix
   and is not claimed as one: it keeps an external user from reaching a receipt through a link this
   package created, and nothing more.
4. **The donor's route to the document is the Receipts related list on their record**, which needs
   a Giving permission set, and the admin guide says so on both the Access page and the Receipts
   page. An administrator must not have to reason about `ContentDocumentLink` semantics to know
   whether their program staff can read donor tax documents.
5. **The shipped letters are materialized by `GivingPostInstall`, not by a page.** This is
   ADR-0029 applied to the other thing this package ships: install is where a shipped default
   arrives, `installDefaultsDuringInstall` never throws so an install is never aborted by it, and
   a **Restore the shipped letters** button on the Receipts page is the documented recovery path
   for an install whose step failed. `getTemplates` keeps `cacheable=true`, which is wanted: the
   list is small, it is read on every visit and again after every save through `refreshApex`, and
   it changes only when somebody on that screen changes it.
6. **The lazy path survives in `activeBodyFor` only, gated by `Issue_Receipts`.** An org issuing a
   receipt with no letter of that kind still gets a document rather than an error, and the
   permission that authorizes the receipt authorizes the letter that prints it.
7. **The insert goes through `ReceiptWriter.insertTemplates` in system mode under ADR-0021**,
   because the post-install user holds no permission set and the user issuing a receipt holds Read
   and not Create on `Receipt_Template__c`. Every value written comes from packaged custom
   metadata, so no user typed text reaches a record on that path.
8. **Writing a letter checks `Manage_Nonprofit_Settings`**, in the service rather than only in the
   controller, and the DML stays in user mode on top of that. This is what every other write the
   settings console makes already does (`AcknowledgmentController`, `DonorLevelController`,
   ADR-0027).

## Alternatives considered

- **Keep the donor links and set `Visibility = 'InternalUsers'` with `ShareType = 'I'`.** This
  does not work, and it is worth saying why in full, because it is the obvious fix.
  `Visibility` separates internal users from external ones: `InternalUsers` excludes Experience
  Cloud users, not Program Staff. `ShareType` governs what the link grants, and the V and I
  distinction is about whether access to the linked record can escalate to editing the file: on a
  standard object an inferred link can confer Collaborator, on a custom object it does not. Neither
  value withholds **view** from a user who can read the linked record, which is the whole of the
  problem here. Program Staff can read the Account either way, so the donor's statement stays
  visible either way. Changing the link targets is the only thing that changes who can read the
  file. `'I'` would also be a small step backwards on the gift: Giving Staff holds Edit on
  `Gift__c`, and Viewer is the ceiling we want on a document that is immutable once issued.
- **Grant nothing and rely on record level sharing of the donor record.** Sharing decides which
  Accounts a user sees, not whether an Account's files include somebody's tax documents. Program
  Staff are supposed to see the household; that is their job.
- **Keep the donor links and add `Receipt__c` read to the Core roles.** It inverts the design: the
  module's data would be governed by Core's roles, the Module Manager in v0.7 would have nothing
  left to join up, and a Read Only board member would gain donor tax documents on a Core role.
- **Leave the file on the donor and accept the exposure until the Module Manager ships (v0.7).**
  Rejected. The exposure is donor tax data in an org that installed the package correctly, and v0.7
  is not a date.
- **Materialize the letters lazily but from a non cacheable method.** It writes records as a side
  effect of reading a page, it does not help an org where nobody opens that page, and ADR-0029
  rejected exactly this for rollups. Kept only on the issuing path, where the alternative is a
  donor not getting a receipt.
- **Gate the letters on `Issue_Receipts` rather than `Manage_Nonprofit_Settings`.** Issuing is
  day to day work for Giving Staff; rewriting the letter every donor receives is configuration.
  The console's own permission is the honest one.

## Consequences

- **A receipt PDF no longer appears in the Files related list of the donor's Contact or Account.**
  That is a visible change to a shipped behaviour, described in the v0.4 draft release note, and
  the two admin guide pages state the new route: the Receipts related list on the donor record,
  then the file on the receipt. Anyone who needs to hand a donor their copy needs a Giving
  permission set, which is what "who can see our giving records" was always supposed to mean.
- **Documents issued before this change keep their old links.** Nothing here deletes a
  `ContentDocumentLink`, because the package does not delete a record it cannot tell from one an
  administrator made, and because a link is not obviously ours to remove. No org has installed
  v0.4, so today this affects nothing; if one has by the time this ships, the release note tells
  the administrator to remove the donor links on existing receipt files, and that is a one time
  action rather than a migration.
- **Editing a receipt letter now needs Nonprofit Admin as well as Giving Admin.** A person holding
  only Giving Admin could rewrite the letter before and cannot now. That is the same rule every
  other settings page follows, and the refusal names the role to ask for.
- **Only a real org can confirm the file access half of this.** No Apex in this repository has ever
  been executed. The link graph is asserted exactly by `ReceiptFileAccessTest` and is offline
  verifiable; what the platform then does with those links, including whether a user with no link
  to a document is refused the query in the way the third test asserts, is platform behaviour an
  offline compiler says nothing about. A scratch org check joins the v0.4 definition of done: sign
  in as a user holding `Nonprofit_Staff` only, open a donor with a year end statement, and confirm
  the Files related list is empty of receipts.
- **Revisit when** the Module Manager (v0.7) joins roles to module permission sets, because the
  question of who holds a Giving set stops being an administrator's manual step then, and when a
  future module wants to store a document of its own: the rule that a file's audience is the
  audience of the records it is linked to is general, and `AcknowledgmentWriter` already follows it
  by linking a merge file only to its run.

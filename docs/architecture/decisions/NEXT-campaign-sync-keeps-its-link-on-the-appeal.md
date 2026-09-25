# ADR-NEXT: Campaign sync keeps its link on the appeal, writes with the saver's access, and is off until switched on

**Status:** Accepted (builder decision)
**Date:** 2026-09-24
**Source:** builder decision under plan Section 9.3, feature X-02 (plan Section 4.12, "Campaign
sync: `Appeal__c` to Campaign one-way, so Campaign Members and marketing tools work"); refines
ADR-0017 and ADR-0021 for Connect; canonical model Section 29B

## Context

Plan Section 4.12 gives X-02 one sentence. It leaves open where the link between an appeal and
its Campaign lives, when the copy runs, whose access it runs with, what it does with a Campaign
that already exists, and whether it is on at install.

Four constraints narrow the answer.

1. **Campaign may be named only in Connect, and only dynamically** (plan Section 4.2,
   ADR-0009, ADR-0013). Giving cannot hold the link: `check-standard-objects.sh` fails a Giving
   file that names Campaign at all. A lookup to Campaign anywhere, including in Connect, is a
   compile-time reference, and Connect must still install on an org without Campaign.
2. **Opportunity mirror (X-01) will need it.** Plan Section 4.12 has the mirrored Opportunity
   take its "Campaign from appeal link". Whatever holds the link is X-01's input, so it has to
   be cheap to read from a gift and, for X-01's "Opportunity is source" direction, cheap to
   read backwards from a Campaign.
3. **Every DML that user input can reach runs in user mode** (plan Section 9.3). An appeal's
   name and description are typed by staff and would be copied onto the Campaign.
4. **Creating a Campaign in Salesforce needs more than an object permission.** The user must
   also carry the Marketing User box on their user record. Most fundraising staff do not.

## Decision

1. **The link is one attribute on Appeal, shipped by Connect.** `Appeal__c.Campaign_Id__c`,
   Text(18), unique, external ID, lives in `packages/connect/main/default/objects/Appeal__c`.
   A dependent package adding a field to its base package's object is the ordinary 2GP
   extension pattern. It holds the identifier as text for constraint 1. It is unique so a
   Campaign mirrors at most one appeal, and an external ID so X-01 finds an appeal from a
   Campaign by an indexed read. There is no link object. X-02 needs one link per appeal and
   nothing else, and a generic mirror link object designed now would guess at X-01's and
   X-07's needs. Those features may still add one; this attribute does not stop them.
2. **The copy runs before the appeal is saved.** A `Campaign_Sync` automation on `Appeal__c`
   (Automation Registry, order 50, after the hierarchy check) creates or updates the Campaign
   in the before-insert and before-update context, then writes the new identifier onto the
   appeal being saved. The link is therefore stored in the same save, and a failed link write
   can never leave an orphan Campaign that the next save duplicates. Values are compared
   first, so a Campaign that already matches is not written.
3. **The Campaign is written in user mode.** Campaign is not package-owned data, so ADR-0021's
   writer pattern does not apply, and constraint 3 settles it. The consequence of constraint 4
   is accepted rather than worked around: a person who cannot create Campaigns still saves
   the appeal, the appeal keeps no Campaign ID, and one Warning goes to the Error Log for the
   save. The Campaign sync page counts the appeals without a Campaign and offers **Sync all
   appeals**, a background batch run as the administrator who starts it (Manage Nonprofit
   Settings, one at a time), which catches them up.
4. **A failure never refuses the appeal.** Every Campaign write uses partial success. Each
   refusal is logged with the appeal and the platform's message. The appeal saves.
5. **Off at install, through a Connect settings object.** Plan Section 4.1 makes a minor
   feature a hierarchy custom setting flag, and ADR-0017 gives each package its own settings
   object, so Connect gains `Connect_Settings__c` with `Campaign_Sync_Enabled__c`, default
   off, shown in the Giving section of Nonprofit Settings. It is off because an org with
   Campaigns of its own (every NPSP org) must decide before Open Impact adds more. The
   automation switch is kept as well, because every packaged automation has one (ADR-0040):
   the setting says whether the feature is wanted, and the switch pauses it.
6. **Connect gains a post-install script.** `ConnectPostInstall` calls
   `AutomationControl.ensureDefaultsDuringInstall`, as `GivingPostInstall` does, so the
   `Campaign_Sync` switch row exists from install. Without it, a fresh Connect install would
   show Health Check a missing switch. It is also where X-01 and X-07 will materialize their
   own switches.
7. **Nothing is deleted, and a stale link is reported, not replaced.** Deleting an appeal
   leaves its Campaign. A linked Campaign that is gone or invisible to the saver is logged.
   A missing Campaign and an invisible one look the same in user mode, and a replacement made
   for an invisible Campaign would be a duplicate. Clearing Campaign ID makes a new Campaign;
   typing an existing Campaign's identifier links to it, and the appeal's values then
   overwrite that Campaign's copied fields.
8. **What is copied** is canonical model R-CS2: name, description, dates, goal to Expected
   Revenue, cost to Actual Cost, active, and the parent appeal's Campaign as Parent Campaign.
   Campaign Type and Status are left to the org's defaults. The Campaign's own Opportunity
   totals are the platform's.

## Alternatives considered

- **A lookup from Appeal to Campaign, or from Campaign to Appeal.** Rejected: either is a
  compile-time reference, so Connect would not install on a Platform-only org.
- **A generic Mirror Link object for X-01, X-02 and X-07.** Rejected for now: one more object
  and one more query for a one-to-one link. X-01 mirrors up to a million gifts and may want
  the link on Gift for the same reasons this ADR puts it on Appeal.
- **System mode Campaign writes, so any appeal saver gets a Campaign.** Rejected: an elevated
  write of typed text onto a standard object the package does not own. It is the case plan
  Section 9.3 and security review exist for.
- **After-save copy with a second appeal update.** Rejected: two saves, recursion to guard
  against, and a failed second save leaves a Campaign that the next save would create again.
- **Copy asynchronously (queueable).** Rejected: the person adding Campaign Members right
  after saving an appeal would find no Campaign, and the job would still run as the same user
  with the same access.
- **A nightly scheduled catch-up.** Not built: plan Section 9.3 says do not invent features.
  If orgs find the manual Sync all appeals button a burden, a nightly job on the Nightly Jobs
  page (ADR-0038) can be added later without a model change.
- **On at install.** Rejected for the NPSP reason in decision 5.

## Consequences

- Connect ships its first field on another package's object, its first settings object, its
  first registry row and its first post-install script. `ConnectPostInstall` must be named as
  the Connect package's `postInstallScript` when package versions are created, as Core's and
  Giving's must.
- Fundraising staff without the Marketing User box get no Campaign from their own saves. The
  admin guide tells the administrator to either give those users Campaign access and Marketing
  User in Setup, or run Sync all appeals after a batch of new appeals.
- A Campaign field edited by hand in one of the copied attributes is overwritten when its
  appeal next changes. The admin guide says so.
- A child appeal saved before its parent has a Campaign gets no Parent Campaign until it is
  saved again or Sync all appeals runs. The batch runs a second pass over child appeals so a
  single run leaves the hierarchy complete.
- X-01 reads `Appeal__c.Campaign_Id__c` to set an Opportunity's Campaign, and reads it
  backwards through the external ID for "Opportunity is source". Both need no change here.

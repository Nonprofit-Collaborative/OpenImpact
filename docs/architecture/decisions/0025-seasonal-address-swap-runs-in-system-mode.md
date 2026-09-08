# ADR-0025: The seasonal address swap runs in system mode

**Status:** Accepted
**Date:** 2026-09-08
**Source:** builder decision under plan Section 9.3; extends ADR-0021, refines plan Section 4.13

## Context

C-18 is a nightly job that moves the `Is_Default__c` flag between an owner's addresses when a
seasonal range starts and ends (canonical model R-AD4). ADR-0021 lists four kinds of write that
may run in system mode and requires every new writer to cite it and to satisfy four conditions.
The first of those conditions is that the write is reached only after a custom permission has
been enforced or after the platform has already authorized the running user's own record save.

A scheduled job meets neither. It runs as whoever pressed the button that scheduled it, weeks
or years earlier, in a transaction no user is in. That leaves a real question the rest of the
address code did not have to answer: whose permissions does the swap run as, and what happens
to an address that user cannot see.

Running it in user mode gives a bad answer. A `WITH USER_MODE` query silently returns fewer
rows rather than failing, so a household whose records the scheduling user cannot see is not
reported as skipped: it is simply not there. The Garcia household would go to Arizona for the
winter and their mail would keep going to their summer address, the Hub would say the job ran
and swapped nothing, and nobody would have anything to look at. The failure is silent, it is
seasonal, and it is discovered by a returned mailing months later. Sharing on the addresses of
a departed or reassigned administrator is enough to cause it.

## Decision

The seasonal swap reads and writes in system mode, as a fifth kind of write under ADR-0021:
**scheduled reconciliation of package owned data**. Two classes carry it and nothing else does.

- `SeasonalAddressSelector` is `without sharing` and queries `WITH SYSTEM_MODE`. It has no
  `@AuraEnabled` caller and no user-supplied input: the batch hands it record identifiers it
  got from its own query locator.
- `SeasonalAddressWriter` is `without sharing` and writes `WITH SYSTEM_MODE`. It writes two
  fields on `Address__c`, `Is_Default__c` and `Replaced_By_Seasonal__c`, both package owned,
  and the two settings keys that record the run. It writes nothing else, and the values it
  writes are computed by `SeasonalAddressService` from the seasonal dates on the records, never
  typed by anyone.

The conditions of ADR-0021 that still apply are met: only package owned fields are written,
inputs are package computed, and nothing else in the transaction is elevated. The condition
that cannot apply, the permission gate at the moment of the write, is replaced by a gate on the
only two ways the job can be started: `SeasonalAddressController` enforces
`Manage_Nonprofit_Settings` before scheduling the job or running it now, exactly as
`RollupController` does. An administrator authorizes the nightly job once, when they schedule
it, and that is the authorization.

Two things stay in user mode on purpose.

- The **propagation to the standard address fields** (R-AD3). The job moves the default flag
  and the address automation copies it onward in the user mode it already used, so an
  administrator who has switched that automation off gets the same behavior from the job as
  from a person pressing "Set as default", and a household whose Contacts the running user
  cannot edit produces a real, logged DML failure rather than an elevated write of standard
  fields the package does not own.
- Everything the **settings console and the Hub** read to display the last run. Those are
  ordinary reads by a person looking at a page.

## Alternatives considered

- **Run in user mode and accept the gap.** Rejected: the gap is invisible, which is the worst
  property a nightly job can have. Plan Principle 2 prefers a correct write of package data to
  a quietly wrong result.
- **Require the job to be scheduled by a System Administrator and say so in the guide.** Not
  sufficient on its own: it is advice, not a mechanism, and it breaks when that administrator
  leaves. It survives here as a recommendation in the admin guide for the propagation step,
  which really does run as the scheduling user.
- **Elevate the propagation as well, so the job never fails on sharing.** Rejected: the
  standard address fields on Account and Contact are not package owned, and elevating writes to
  them would put the package outside ADR-0021's fourth condition for a convenience.

## Consequences

- Two more classes for the security review to read against ADR-0021, both small, both cited in
  their header comments.
- The reviewer checklist question about new `without sharing` or `SYSTEM_MODE` usage (plan
  Section 9.4) is answered by this ADR for these two classes.
- Because the swap sees every address and the propagation does not, a run can move a default
  and then fail to copy it onward. That failure reaches the Error Log per owner and is counted
  in the run summary the Hub shows, which is what R-AD8 exists for.

# ADR-NEXT: A pause ends through a one-time resume job, and the error digest counts and goes only to users

**Status:** Accepted (builder decision)
**Date:** 2026-09-24
**Source:** feature C-23 (plan Section 4.8, "auto-expiring after a set time" and "an optional
daily digest email to the admin"); follows ADR-0021, ADR-0027 and ADR-0038

## Context

The global pause has been a datetime on Nonprofit Settings since C-04. Every reader compares it
with the clock, so automation already starts again on time with nobody present. Two things did
not happen at that moment: nothing cleared the value, and nothing wrote the Setting Change that
every other change to a setting writes (R-N4). The audit trail showed a pause starting and never
ending, and a pause set outside the Automation page, or far in the future, had no end anyone
would notice.

The plan also promises an optional digest email of new Error Log entries. Email leaves the org,
so three questions have to be settled: who can receive it, what it may say, and how it stays
inside the org's email limits. Scheduling it is already settled by ADR-0038: a job an
administrator starts and stops from the settings console, with a visible last run.

## Decision

1. **Lazy evaluation stays the source of truth; a one-time job records the end.** Pausing writes
   the end time as before and schedules a one-time job, `AutomationResumeJob`, for that exact
   moment. The job clears the value in system mode through `AutomationSettingsWriter` (the
   pausing administrator's `Manage_Nonprofit_Settings` check is the authorization, as in
   ADR-0027) and writes the resume as a Setting Change in user mode, then removes its own
   schedule. It clears only a pause whose end has passed, so a job that fires after the
   administrator paused again changes nothing. Resuming by hand, or pausing again, cancels the
   job first. If the job cannot be scheduled, the pause still happens and still ends on time,
   and the failure goes to the Error Log.
2. **Who paused is read, not stored.** The console names the person from the newest Setting
   Change for the pause, which every pause already writes. No field is added.
3. **A pause nothing will end is a Health Check warning.** While automation is paused and no
   resume job is scheduled, or the end lies more than 24 hours ahead (the longest pause the
   console offers), Health Check says so and sends the administrator to the Automation page.
   This is what catches a pause left over from before this feature.
4. **The digest counts and links; it never quotes.** It carries the number of entries created
   since the last digest that are still New, the numbers by Context and by Severity, and the
   newest 25 by record name with a link to each. It never carries Message, Technical Detail or
   Record Reference.
5. **The digest goes only to active users of the org.** The recipients are the active users
   holding `Manage_Nonprofit_Settings`, or the users whose email addresses the administrator
   lists; an address that is not an active user's is refused when the setting is saved. Each
   message is addressed to the user record (`setTargetObjectId`), which the platform does not
   count against the daily limit on email sent to addresses, and at most 50 users receive it.
6. **The digest runs daily and sends only when something is new.** One job runs every morning
   at 07:00, after the nightly jobs. A Weekly setting sends when seven days have passed since
   the last window it covered. A run with nothing new sends nothing and still moves the window
   on; a run that could not send leaves the window where it was, so nothing is lost.

## Alternatives considered

- **Lazy evaluation alone.** Rejected: automation resumes, but the audit trail never says so
  and a stale value is indistinguishable from a live one.
- **A recurring sweep job the administrator schedules.** Rejected: an org that never scheduled
  it would never record a resume, and a sweep that runs hourly is 24 runs a day for an event
  that happens a few times a year. The pause already knows its own end.
- **Store who paused on Nonprofit Settings.** Rejected: the Setting Change already holds it,
  and a second copy can disagree with the first.
- **Send the digest to any address typed in.** Rejected: it would send the org's failures
  outside the org and count against the daily email limit.
- **Put the message text in the digest.** Rejected: messages name records and sometimes people,
  and email is a copy the org cannot recall.

## Consequences

- One more scheduled job may exist while a pause is on, and one while the digest is on. The
  org limit is 100 scheduled jobs; both are named, so they are found by name and never
  duplicated.
- The resume is recorded as changed by the administrator who paused, because the job runs as
  that person. Its time is the pause's own end, which is how the change list tells an automatic
  resume from a manual one.
- An org whose email deliverability is set to system email only receives no digest. The last run
  says why and the failure is in the Error Log; nothing in the package can change that setting.

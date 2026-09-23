# ADR-NEXT: Packaged records use activities, not Chatter

**Status:** Accepted
**Date:** 2026-09-23
**Source:** product owner decision (Brandon), plan Section 6 feature C-08

## Context

The Account and Contact record pages carried the Chatter publisher (`forceChatter:publisher`)
beside the activity panel, and Commitment had feed tracking switched on. Nothing in the
packages reads or writes a feed, and one admin guide told staff to explain a changed pledge
on the commitment's Chatter feed.

Chatter is an org choice. Many nonprofit orgs switch it off, and a record page that places
the publisher, or an object that enables feeds, assumes a feature the installing org may not
use. Two places to write a note about a record (a feed post and an activity) also split the
history staff read.

## Decision

- No packaged record page places a Chatter component (`forceChatter:*`), a feed, or a
  feed-based related list.
- No packaged object enables feeds: `enableFeeds` is false on every packaged object,
  including Commitment, and no field tracks feed history.
- The activity panel (`runtime_sales_activities:activityPanel`) stays, and it is where staff
  record a call, an email, a task or a note about a record. The Commitment record page gains
  it, so a change to a pledge can be explained there.

## Alternatives considered

- **Keep both.** Rejected: two places for the same note, and a dependency on a feature the
  org may have switched off.
- **Keep feeds on Commitment only.** Rejected: nothing reads the feed, and the admin guide
  was its only use.

## Consequences

- An org that uses Chatter adds the publisher or the feed to its own copy of a page, and
  switches feed tracking on in Setup; nothing packaged stands in the way.
- Explaining a change to a record is an activity, which reports can count and filter.

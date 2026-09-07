# ADR-0010: Receipts are immutable; corrections void and reissue; refunds are negative linked gifts

**Status:** Accepted
**Date:** 2026-09-06
**Source:** plan Section 12, decision D-10

## Context

Principle 2 says the numbers must be right, because giving totals, receipts, and fund
balances are the product's reputation. A receipt is not an internal record: in the United
States it is the document a donor uses for tax purposes and it must state the amount, the
date, the organization, and whether goods or services were provided (plan Section 13).

Once that document is in a donor's hands, the amount it reports is a fact about the
world. If the underlying gift can be edited afterward, the organization's records and the
donor's records silently disagree, and neither the finance staff nor the auditor can tell
when it happened. Plan Section 4.11 states the design rule directly: amounts never change
after a receipt is issued.

There is also a bookkeeping question. When a gift is refunded or written off, the naive
approach edits or deletes the gift. That destroys the history of the original
transaction, breaks reconciliation against the bank, and silently changes rollups for
prior periods that have already been reported to a board.

Plan Section 11.1 also lists a year-end receipt bug in December as a low-likelihood,
very-high-impact risk.

## Decision

- **A receipt is immutable once issued.** Its number, amount, date, and stored PDF do not
  change.
- **A correction voids the receipt and issues a new one.** The void is a record, not a
  deletion, and the reissued receipt references what it replaces.
- **A gift's amount does not change after a receipt has been issued against it.**
- **Refunds and write-offs are new gifts with a negative amount, linked to the original
  gift**, never edits to the original and never deletions.
- Receipt numbering is sequential and gapless enough to satisfy an auditor asking what
  happened to a number.

Anything touching receipt immutability or gift amount mutability is an escalation to
Brandon, not a builder decision (plan Section 11.4).

## Alternatives considered

- **Editable gift amounts with an audit trail on the field**: field history is not a
  receipt trail, it is not visible to finance staff in a usable form, and it does not
  answer the question "which document did the donor receive."
- **Deleting and re-entering a refunded gift**: destroys the transaction history the
  bookkeeper reconciles against and silently restates closed periods.
- **Allowing edits before a receipt is issued only, with no negative-gift model for
  refunds**: half the rule, and it leaves refunds unmodeled.

## Consequences

- Rollups must handle negative gifts correctly in every aggregate: totals, counts,
  largest gift, first and last gift, and every fiscal-period window.
- The receipting feature (G-13, v0.4) must implement void and reissue from the start, not
  as a later addition, and the receipt engine is tested with fiscal-year fixtures.
- Staff correcting a typo experience more friction than editing a field. That is the
  intended trade: the correction is visible, and plan Section 6.2 rule 2 puts protecting
  the numbers above convenience.
- Release freeze windows apply: never in the last week of December (year-end giving) or
  the first two weeks of January (year-end receipting) (plan Section 7.5).

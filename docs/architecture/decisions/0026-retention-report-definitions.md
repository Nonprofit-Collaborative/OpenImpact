# ADR-0026: What the retention reports count, and the one attribute they needed

**Status:** Accepted
**Date:** 2026-09-08
**Source:** builder decision under plan Section 9.3, building G-16 ("correct by
construction; definitions documented") against ADR-0022 and canonical model Section 26

## Context

Fundraisers do not trust LYBUNT and SYBUNT reports in other systems, and the reason is not
arithmetic: it is that nobody can say precisely what the report counted. Every system draws
the year boundary somewhere, decides for itself whether a refunded gift was a gift, and
names the donor who skipped a year differently. G-16 exists to answer those questions in
writing and then build to the answers.

ADR-0022 already settled the underlying question for this package. Money rows filter gift
status in Received, Refunded and Written off. Rows that count, and the first and last gift
date rows, add `Amount__c` greater than 0, so a donor who gave once and had it back reads as
one gift and a total of zero.

That distinction decides the two failure modes a retention report has:

- A donor gave this year and the gift was refunded. Their fiscal year total nets to zero. A
  report that asks "is this year's total zero" puts them on the LYBUNT list, soliciting a
  donor who gave.
- A donor gave nothing this year, and a refund of an older gift is dated this year. The
  refund is a negative gift whose own status is Received. A report that asks "are there any
  gift rows this year" drops them off the LYBUNT list, missing a donor who lapsed.

Both are avoided by asking the count question rather than the money question, which is what
`Last_Gift_Date__c`, `First_Gift_Date__c` and `Gift_Count__c` already do.

One question had no attribute to answer it: did this donor give **last fiscal year**, counted
rather than added? `Giving_Last_Year__c` sums, so it reads zero for a donor whose only gift
last year was refunded inside that year, and below zero for a donor whose only activity last
year was a refund of an older gift. Both are the failure modes above, moved one year back,
and they fall exactly on the retained-versus-reactivated split.

## Decision

Four reports, on one new report type, `Donors with Giving`, whose rows are donors rather than
gifts, so a record count is a donor count. A **qualifying gift** throughout means a gift with
status Received, Refunded or Written off, and an amount greater than zero: ADR-0022's count
rule. Fiscal year means the year in ADR-0025.

1. **LYBUNT.** Their most recent qualifying gift falls in the last fiscal year:
   `Last_Gift_Date__c equals LAST_FISCAL_YEAR`. This is one filter because Last Gift Date is
   already the maximum date over qualifying gifts, so "gave last year" and "nothing since"
   are both in it. A donor whose last year gift was refunded this year is still on the list,
   because the refund is negative and did not move the date. A donor whose this year gift was
   refunded is not on the list, because the date moved when they gave.
2. **SYBUNT.** Their most recent qualifying gift falls before this fiscal year began:
   `Last_Gift_Date__c lessThan THIS_FISCAL_YEAR`. "Some year" reaches back to the first gift
   in the org, with no lookback limit, because Last Gift Date is computed over every gift
   ever. The report groups by the fiscal year of that last gift so a lookback can be read off
   rather than imposed. Every LYBUNT donor is a SYBUNT donor.
3. **New versus retained.** The rows are donors with a qualifying gift this fiscal year
   (`Last_Gift_Date__c equals THIS_FISCAL_YEAR`), grouped by the fiscal year of their first
   qualifying gift and then by whether `Gifts_Last_Year__c` is zero.
   - **New:** first qualifying gift falls in this fiscal year, so there is no qualifying gift
     in any earlier year.
   - **Retained:** gave this fiscal year and last fiscal year.
   - **Reactivated:** gave this fiscal year, first gift in an earlier year, no gift last year.
     This is the donor other systems name differently, and this package calls reactivated,
     never new and never retained. The first-gift grouping says how long they were away.
   - A donor who gave last year and not this year is not on this report at all: that is the
     LYBUNT report, and the two together account for every donor of the last two years.
4. **First to second gift conversion.** The rows are donors whose first qualifying gift falls
   in one of the two completed fiscal years, grouped by that cohort year, then by whether
   `Gift_Count__c` has passed one. The window is from the first gift to today, not a fixed
   twelve months: the package holds a first gift date and a gift count, and nothing that
   dates a second gift, so a fixed window would need a new rollup with no aggregate to
   express it. The cohort filter is what keeps the window honest, because every donor in it
   has had at least a full year, and the report says so in its description.

Both bucket fields split at a half, 0.5 and 1.5, rather than at 0 and 1. Gift counts are
whole numbers, so no record can land on the boundary, and the report cannot be read two ways
depending on whether the platform treats a bucket bound as inclusive.

To make the retained test possible, one attribute is added: `Gifts_Last_Year__c` on Account
and Contact, a COUNT of gifts with the ADR-0022 count filter and fiscal year offset -1,
shipped as `Household_Gifts_Last_Year`, `Account_Gifts_Last_Year` and
`Contact_Gifts_Last_Year`. Nothing else in G-16 adds a field.

## Alternatives considered

**Build the retained test on `Giving_Last_Year__c` being non zero.** No new field, and wrong
for exactly the donor this feature exists to protect: a gift refunded inside last year nets
to zero and the donor reads as reactivated when they were retained. Rejected on the feature's
own terms.

**Build LYBUNT and SYBUNT from cross filters over gift rows instead of the date rollups.**
Correct in principle, and the cross filter carries the status and amount conditions
explicitly, which reads well. Rejected for two reasons. A cross filter joins on one lookup,
so a report joined through `Household__c` silently drops organization donors, and one joined
through `Donor_Account__c` silently drops households; and an account with no gifts on the
joined path passes a "without" filter, so the wrong join puts wrong rows on a solicitation
list rather than merely omitting right ones. Reading `Last_Gift_Date__c` covers households,
organizations and person accounts in one filter, because the three rollup scopes fill the
same field on disjoint record sets.

**Ship new versus retained as three reports, one per segment.** Each would be a plain filter
with no bucket field. Rejected because the three numbers are only meaningful together: a
retention rate is a ratio, and three reports invite reading one of them alone.

**Bound SYBUNT at five years, as most systems do.** Rejected: the bound is arbitrary, it is
invisible in the number, and the fiscal year grouping lets a fundraiser stop reading wherever
they like.

## Consequences

- **Three reports depend on rollup freshness, and one does not.** LYBUNT, SYBUNT, new versus
  retained and the conversion report all read rollup fields, so they are as current as the
  last rollup run. Every one of them carries Rollups Last Calculated as a column, and the
  admin guide says to look at it before trusting a list. This is the price of not using cross
  filters, and it is paid visibly.
- **A new gift status that represents money the organization holds** has to reach
  `Gifts_Last_Year__c` along with the 38 rows ADR-0022 already names. It is now 41.
- **`Gifts_Last_Year__c` is a fiscal count with no sibling for this year or two years ago.**
  That asymmetry is deliberate: this year is answered by `Last_Gift_Date__c`, and two years
  ago has no question in G-16. If donor scoring (G-19) needs a per year count series, it
  should add the series rather than treat this field as the start of one.
- **Nothing here is verified against an org.** No report in this repository has been run in
  one. What is verified is that the XML is well formed and that each filter matches the
  definition written above.

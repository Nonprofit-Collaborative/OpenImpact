# ADR-0029: An in-kind gift is a gift type carrying no amount, and its value is rolled up separately from money

**Status:** Accepted
**Date:** 2026-09-09
**Source:** feature G-18 (plan Section 5.2, roadmap v0.4, note "Receipt language differs");
canonical model Sections 18 and 26; ADR-0010, ADR-0016, ADR-0022, ADR-0024, ADR-0028

## Context

G-18 is in-kind gifts: goods and services rather than money, recorded with a description of
what arrived and a fair market value. Four questions have to be answered before any of it
is built, and the plan settles none of them.

**Whether an in-kind gift is a Gift.** `Gift__c.Type__c` has carried the value `In-kind`
since v0.2 and `In_Kind_Description__c` and `Fair_Market_Value__c` have shipped alongside it
under R-G9. The alternative is a second object.

**Where the value lives.** `Amount__c` is the attribute every shipped rollup, every packaged
report, the dashboard, the receipt template's `{{Amount}}` token, the allocation rule R-GA1
and the receipt lock all read. Putting the fair market value there makes an in-kind gift
count as money everywhere, automatically, with no code. That is either exactly right or
exactly wrong, and nothing else in the feature can be decided until it is settled.

**What the receipt says.** ADR-0016 already settled the content rule: an in-kind gift prints
the donor supplied description and never a value asserted by the organization, because under
IRS Publication 1771 and Form 8283 the donor substantiates the value of donated property and
the charity describes what it received. `ReceiptContentBuilder.taxSentencesFor` emits that
sentence today. What the rest of the document does with an in-kind gift, in particular the
amount line on a per gift receipt and the amount column on a year end statement, was never
decided and currently renders `$0.00`.

**What an in-kind gift does to the numbers.** ADR-0022 set the rollup filters: money rows
take `Status` in Received, Refunded, Written off; count, largest gift and first and last gift
date rows add `Amount__c` greater than 0. Its own consequences section flagged the case and
left it open: "An in-kind gift entered at zero shows in the related list and not in the
count. If that turns out to matter for in-kind reporting, the condition becomes not equals 0
on the count rows." Donor levels read one of those totals (ADR-0028) and the retention
reports read `Gifts_Last_Year__c` and the fiscal year totals (ADR-0026), so whatever is
decided here reaches three features.

The forcing constraint is the one a fundraiser feels. A nonprofit's finance team reports
contributed goods and services separately from cash, because that is how the audited
statements present them. A system that adds a donated minibus to a donor's giving total
produces a development report that does not reconcile with the finance report, and the
argument that follows is not settled by explaining the database.

## Decision

1. **An in-kind gift is a `Gift__c` with `Type__c` equal to `In-kind`, not a second object.**
   It has a donor, a date, an appeal, a fund designation, an acknowledgment, a soft credit, a
   tribute and a receipt, and every one of those is behavior the Gift object already has.
2. **`Amount__c` on an in-kind gift is zero, and the value goes in `Fair_Market_Value__c`.**
   Zero rather than blank, because `Amount__c` is a required attribute and because R-GA1
   requires the allocations to total it. The `Amount_Cannot_Be_Zero` validation rule is
   narrowed to gifts that are not in-kind, and three rules are added: an in-kind gift needs a
   description, an in-kind gift may not carry a non zero amount, and a gift that is not
   in-kind may not carry a description or a fair market value.
3. **No packaged money rollup changes, and the count rows keep `Amount__c` greater than 0.**
   An in-kind gift therefore adds nothing to Total Giving, the three fiscal year totals,
   Largest Gift, Gift Count, Gifts Last Year, First and Last Gift Date, Fund and Appeal Total
   Raised, or Commitment Paid To Date. It follows, without any further decision, that an
   in-kind gift moves no donor level (ADR-0028 reads one of those totals), appears in no
   retention report (ADR-0026 reads the fiscal year totals and `Gifts_Last_Year__c`), and
   adds nothing to the giving dashboard, whose components are all money or counts of money.
4. **In-kind giving is rolled up on its own two attributes**, `In_Kind_Value__c` (SUM of
   `Fair_Market_Value__c`) and `In_Kind_Gift_Count__c` (COUNT), on Account and Contact across
   all three scopes of Section 26, under the ADR-0022 status set plus `Type__c` equals
   `In-kind`. The count carries no amount condition, because a donor may give goods whose
   value they never told the organization and that gift still happened. A packaged report,
   In-kind Gifts This Year, lists them with their descriptions.
5. **What the receipt prints for an in-kind gift is the description, the date, the receipt
   number and the issuing organization, and no amount at all.** The `{{Amount}}` token
   resolves to a phrase that states the absence rather than to `$0.00`, and the amount column
   of a year end statement line does the same, so a statement's total is the money total and
   the in-kind lines are visibly outside it. `Fair_Market_Value__c` reaches no rendered
   document, and there is a test that asserts it.
6. **The receipt lock covers `In_Kind_Description__c` and not `Fair_Market_Value__c`
   (ADR-0024).** The description is printed on a document the donor holds, so it is locked
   with the amount, the date and the donor. The fair market value is never printed, so
   correcting it afterwards cannot make the record disagree with the receipt, and locking it
   would force an administrator to void a valid receipt to fix an internal reporting figure.

## Alternatives considered

**A separate `In_Kind_Gift__c` object.** Rejected on right sizing. Name what breaks with the
type: nothing does. Everything an in-kind gift needs already exists on Gift, and a second
object would need its own layouts, permission sets, list views, receipt path, acknowledgment
path, soft credit path, tribute link, import template and sample data, and would put a
donor's gifts on two related lists so that "everything this donor gave" is a question no
screen answers. The only argument for it is keeping fair market value out of a money field,
and item 2 keeps it out of the money field anyway.

**Fair market value in `Amount__c`.** The cheapest option by a wide margin: it needs no
fields, no rollups and no code, and gives in-kind gifts a giving total, a level and a place
in the retention reports for free. Rejected because those numbers would be wrong in a way
nobody could see. Total Giving would stop being a figure a fundraiser can quote next to the
finance report; a donated vehicle would set Largest Gift and crown a top donor list; a donor
level, which is a promise about recognition, would be awarded for goods; and the receipt
would carry the value on a document, which is the thing ADR-0016 forbids. The failure is
silent, which is what makes it disqualifying rather than merely undesirable.

**In `Amount__c`, with every affected rollup filtered to exclude `Type__c` equals In-kind.**
Rejected because it is the same decision as this one with the danger left in: thirty eight
shipped rows would each carry the exclusion, an administrator editing filter JSON by hand
(ADR-0022) could drop it from one row, and every unpackaged report, list view and formula an
organization writes afterwards would have to remember it. The condition that makes the number
right should be a property of the data, not a clause repeated in thirty eight places.

**Leave in-kind out of the rollups entirely (item 4 undone).** Genuinely tempting, and it is
the state ADR-0022 left behind. Rejected because of what breaks: a food bank's largest in-kind
supporter would read as a donor who has never given, with no total, no count and no last gift
date anywhere on the record, and the fundraiser stewarding them would have to open the related
list to find out. Two rollup attributes is a low price for a record that tells the truth.

**Print the fair market value on the receipt in small print, or as "donor stated value".**
Rejected: ADR-0016 settled it, and the reason stands. A number on the charity's letterhead is
a number the charity asserted, whatever the caption says.

## Consequences

- **Two numbers now describe a donor, and every screen that shows one has to show the other.**
  Total Giving is cash; In-kind Value is goods. The admin guide states in those words that
  they do not add up to "what this donor gave", and the Account and Contact layouts put them
  next to each other so that nobody reads one as the whole.
- **A gift is either money or goods, never both.** An event package where the donor paid 500
  and also donated the wine is two gifts. That is a real limitation and the admin guide says
  so, with the two record walkthrough.
- **Six new `Rollup_Definition_Default__mdt` rows and four new fields** (two on Account, two on
  Contact) join the thirty eight of Section 26. They use the same engine, the same filter
  grammar and the same freshness stamp; nothing new is required of the engine.
- **The retention reports and the donor levels are cash instruments, and their pages say so.**
  `Donor_Level_Source_Field__c` offers the four totals ADR-0028 named and is not widened to
  In-kind Value here, because a recognition ladder measured on donated goods is a rarity and
  a setting nobody asked for is a setting to explain forever. An organization that wants one
  says so, and it is then a one entry change to `DonorLevelService.SOURCE_FIELDS` and to the
  console's choices, not a redesign.
- **The sample data changes shape.** Its twenty three in-kind gifts carried the value in
  `amount`, which under this decision was the merge the decision forbids. The generator now
  writes zero to `amount` and the value to `fairMarketValue`, and the giving totals in the
  sample set drop by the in-kind total. That is the point of the change, and
  `docs/admin-guide/sample-data.md` says what the number means.
- **Revisit if the count rows' amount condition is ever relaxed.** If ADR-0022's flagged
  change (`not equals 0` on the count rows) is ever made for another reason, in-kind gifts
  would start appearing in Gift Count and the separation this decision rests on would be gone
  without anyone editing this file. Whoever makes that change reads this consequence first.

# In-kind gifts

## What it does

An in-kind gift is a gift of goods or services rather than money: a donated minibus, twelve
cases of tinned food, an auction lot, a lawyer's time. Open Impact records what was given
and what your organization values it at, and it issues the donor a receipt that describes
the goods and puts no price on them.

That last part is the whole point. In the United States, deciding what a donated item was
worth is the donor's job, not yours. A receipt that states a dollar figure for a gift of
goods reads as a cash contribution of that amount, which is the one thing the document must
not say. So the value you record stays inside Open Impact, for your books and your reports,
and the donor's receipt describes the piano.

## How to turn it on

Nothing to turn on. In-kind is one of the gift types, and the two fields it needs are on the
gift page layout already.

### Recording one

1. Create a gift the way you record any other, from the gift's tab or from **Quick Gift
   Entry**.
2. Set **Type** to **In-kind**.
3. Fill in **In-kind description**: what was given, written the way the donor should read it
   on their receipt. "A used minibus in working order" is a description. "Vehicle" is not.
4. Fill in **Fair market value**: what your organization values it at.
5. Put that same figure in **Amount**. An in-kind gift is one gift with one number, so Open
   Impact refuses a gift whose amount and fair market value disagree. This is the number
   your books and your giving totals count.

Open Impact refuses the two entries that would produce a wrong receipt:

- An in-kind gift with no description, because the receipt would have nothing to print in
  place of an amount.
- A gift of money carrying an in-kind description or a fair market value, because its
  receipt would describe goods nobody gave.

### What the donor sees

Issue the receipt from the gift the usual way (see [Receipts and year-end
statements](receipts.md)). On the document:

- Where your letter asks for the amount, the receipt says "the goods or services described
  below" instead of a figure.
- Below the letter, Open Impact prints the description you typed, followed by the sentence
  that says the organization has not placed a value on the gift and that valuing donated
  property is the donor's responsibility.
- On a year-end statement, the gift is a line with its date, its type and its status, and
  the amount column says "Not valued". The statement's total is the money only, and the
  statement says so in one sentence, so a donor who adds the lines up is not left puzzled.

## A five-minute walkthrough

Start from the sample data, which includes several in-kind gifts.

1. Open the **Gifts** tab and filter or sort on **Type** to find one that is **In-kind**, for
   example "Office furniture for the new wing". Note its amount and its fair market value:
   they are the same number.
2. On that gift, click **Issue receipt**. Open the PDF from the Files list.
3. Read it. Your organization's name is at the top, the description of the goods is in the
   body, and **there is no dollar figure anywhere on it**. That is correct and deliberate.
4. Go back to the gift and change **Fair market value** to a different number from the
   amount. The save is refused with "The amount and the fair market value of an in-kind gift
   are the same number: what your organization values the goods or services at. Enter the
   same figure in both, or change the type if this gift was money."
5. Put it back, and clear **In-kind description** instead. The save is refused with "Describe
   what was given. An in-kind gift needs a description, because that description is what the
   donor's receipt prints instead of an amount."
6. Open a household that has both cash gifts and an in-kind gift in the same year, and issue
   or open its year-end statement. The in-kind line has no amount, and the total at the
   bottom is the cash only.

Steps 3 and 6 are the ones worth reading closely: they are what an auditor or an accountant
would look at.

## Common mistakes

**Putting a value on the receipt anyway, by typing it into your letter.** You cannot type a
donor's number into a packaged letter, but you can write "we valued your gift at" and a merge
token into the template. Do not. The sentence Open Impact adds says the organization has not
placed a value on the gift, and a letter that contradicts it in the paragraph above is worse
than either sentence alone.

**Expecting in-kind gifts to stay out of your giving totals.** They do not. A donor's total
giving, largest gift, and gift count include in-kind gifts at the value you recorded, because
the packaged totals count gifts by status and not by type. If you need cash only, build a
report filtered on Type. Leaving the fair market value blank to keep the total down is not a
workaround: Open Impact refuses the save, and the gift would have counted its amount anyway.

**Recording the value in one field and something else in the other.** The amount and the fair
market value are the same number, and Open Impact enforces it. If they genuinely differ in
your mind, one of them is not a fair market value: decide what your organization values the
goods at and use that figure twice.

**Refunding a gift of goods and expecting to describe them again.** A refund or a write-off is
a negative gift that names the gift it reverses, and it does not carry its own description or
value: the gift that recorded the property still has both. Use the **Refund** or **Write off**
action on the original, exactly as you would for money.

## Fields, for a report builder

| What you want to report on | Object | Field |
|---|---|---|
| Which gifts were goods or services | Gift | Type, value In-kind |
| What was given | Gift | In-kind Description |
| What your organization valued it at | Gift | Fair Market Value, which equals Amount |

# Matching gifts

## What it does

Many employers match the gifts their staff make. The match arrives weeks later, as a check
from the company, and it is easy to lose the connection between the two. Linking them in
Open Impact keeps both facts true at once: the company is the donor of its own gift, and
the employee is recognized for having caused it.

The link is visible from both gifts, so David can open either one and see the other. The
employee gets a soft credit on the company's gift, which is how their real influence on
your income shows up in donor reporting without ever crediting them with money they did
not give.

Open Impact does not tell you which employers match. That information comes from a
matching gift database and is out of scope: this feature records the match you have
received.

## How to turn it on

Nothing to turn on. Linking is available on every gift.

You link a match by opening the company's gift and setting **Matched gift** to the
employee's gift. Open Impact fills in the other side of the link for you, so the employee's
gift shows the match too, and it refuses a link that cannot be right.

One piece of setup makes it safer and faster: fill in **Employer** on the people who work
for companies that match. Open a Contact and set **Employer** to the organization. When
the employer's check arrives, Open Impact checks the link you are making against it and
warns you if the two do not agree.

## A five-minute walkthrough

You are David. Start from the sample data, which includes Ana Garcia and the organization
Riverbend Manufacturing.

1. Open **Ana Garcia** and set **Employer** to **Riverbend Manufacturing**. Save.
2. Click the **Gifts** tab and press **New**. Enter a gift from **Ana Garcia** for **500**,
   dated last month, status **Received**. Save. This is the employee's gift.
3. Press **New** again. Enter a gift from **Riverbend Manufacturing** for **500**, dated
   today, status **Received**. Save. This is the employer's match.
4. On the employer's gift, set **Matched gift** to Ana's gift. Save.
5. Look at what happened on the employer's gift: **Matched gift** names Ana's gift, and in
   **Soft credits** Ana Garcia appears with the role **Matched donor** and the amount 500,
   marked automatic.
6. Open **Ana Garcia's gift**. Its own **Matched gift** now names the Riverbend gift. The
   link reads correctly from both sides, and you only entered it once.
7. Open **Ana Garcia**. Her **Total giving** is 500, the gift she actually made. Her
   **Total soft credits** is 500, the match she caused. Neither number has been inflated by
   the other.
8. Try a link that should fail because of the money. Record a refund against Ana's gift so
   its status is **Refunded**, then try to link it. Open Impact refuses with: **A gift that
   has been refunded or written off cannot be part of a matching gift pair. Unlink the match
   before recording the refund, or link the replacement gift instead.** A link that outlived
   the money would go on crediting Ana for a match you gave back.
9. Try a link that should fail because of the employer. Go back to the employer's gift, clear **Matched gift**, save,
   then set it to a gift from a donor who works somewhere else. Open Impact refuses the save
   with: **That gift is from someone whose employer is a different organization. Check the
   employer on the person's record, or clear it if you are not sure.**

## Common mistakes

- **Linking two gifts that are both from people.** One gift of the pair has to come from an
  organization, because a match is what a company pays. If the save is refused with **The
  matching gift must come from an organization. Open the company's gift and link the
  employee's gift to it.**, neither of the two gifts you chose is the company's.
- **Entering the match as a second gift from the employee.** The company gave the money, so
  the company is the donor. Recording it under the employee inflates their giving total and
  makes your receipts wrong.
- **Leaving Employer blank and linking anyway.** That is allowed: Open Impact only compares
  when an employer is set. Filling it in is what turns a silent mistake into a warning.
- **Refunding one half of a linked pair.** Unlink first, then record the refund. Open
  Impact refuses to create a link involving a refunded or written off gift, and a refund
  recorded against a gift that is already linked leaves a link you should clear by hand.
- **Expecting the soft credit to survive an unlink.** Clearing Matched gift removes the
  matched donor credit that the link created, because it exists only to record the link. A
  credit you entered by hand stays.

## Fields, for report builders

| What you see | Field |
|---|---|
| The other gift in the pair | Matched gift, on both gifts |
| The employee's employer | Employer, on Contact and on Account |
| The recognition the link creates | Soft credit with role Matched donor |

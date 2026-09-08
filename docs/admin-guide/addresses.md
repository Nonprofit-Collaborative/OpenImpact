# Addresses

## What it does

Addresses gives every household, organization, and person one place to keep all of the
places they receive mail, instead of a single set of address boxes that gets overwritten
every time someone moves. One address is marked the default, and Open Impact copies that
one into the standard address boxes on the household, the organization, or the person, so
mail merges, reports, letter templates, and any other app you use keep reading the address
they have always read.

Because the addresses are kept as records, a household can hold a winter address alongside
its year round one, an old address stays on file so a mailing sent last year can still be
explained, and one person can have an address of their own without moving the rest of
their household.

## How to turn it on

Addresses is part of Core and is on as soon as Open Impact is installed. There is nothing
to install and no Setup step. Two things are worth setting once.

1. Open the **Nonprofit Hub** app and choose **Nonprofit Settings**.
2. In the left navigation choose **Addresses**.
3. Set **When a person's address is edited** to the behavior your organization wants:
   - **Update household** (the default): editing one person's address moves the whole
     household, which is what most nonprofits want, because a household shares a mailbox.
   - **Create personal address**: editing one person's address gives that person an
     address of their own and leaves the rest of the household where it is. Choose this if
     you often track students away at school, adult children at a parent's household, or
     staff contacts who move without their family.
4. Choose **Save**. The change applies to the next address you edit.

To let your team see and manage addresses, make sure they have one of the packaged access
levels (Nonprofit Admin, Fundraising Staff, or Program Staff) on the **Access** page in
Nonprofit Settings. Read Only users can see addresses and cannot change them.

Addresses appear in two places once you are set up: an **Addresses** card on every
household, organization, and person record, and an **Addresses** tab in the Nonprofit Hub
app for reporting and list views.

## A five-minute walkthrough

You are Maria. The Garcia household spends January to March in Arizona and the rest of the
year at home, and letters have been going to the wrong place. Start from the sample data.

1. Open the **Nonprofit Hub** app and choose **Households**. Open **The Garcia Family**.
2. Scroll to the **Addresses** card. You will see one address already there, of type
   **Home**, with a **Default** badge on it. Open Impact created it from the address that
   was already in the household's standard address boxes when the household was created,
   so nothing you had was lost.
3. Choose **Add address** on the card. Fill in:
   - **Type**: Seasonal
   - **Street**: 4120 East Camelback Road
   - **City**: Phoenix
   - **State**: AZ
   - **Postal Code**: 85018
   - **Country**: United States
   - **Seasonal Start Month**: 1, **Seasonal Start Day**: 1
   - **Seasonal End Month**: 3, **Seasonal End Day**: 31
   Choose **Save**. The new card appears with its dates shown as "January 1 to March 31".
4. Choose **Set as default** on the Arizona card. The **Default** badge moves to it, and
   the badge disappears from the home address. Scroll up: the household's address boxes at
   the top of the record now read Phoenix. Anything that reads the household's address,
   including a mail merge or a report, now gets Arizona.
5. Choose **Set as default** on the home address card to move the badge back. The
   household's address boxes read the home address again. Nothing was deleted: both
   addresses are still on the card, and you can move the default between them whenever you
   like.
6. Open **Harper Garcia**, one of the household's members, from the household's related
   people. Change her **Mailing Street** to a new street and save.
7. Go back to **The Garcia Family**. Because your setting says **Update household**, the
   household's default address now shows Harper's new street, and every other member of the
   household has the same new mailing address. One edit moved the whole household, which is
   what a household moving actually means.

If you had set **Create personal address** instead, step 7 would look different: Harper
would have her own address card on her own record, marked default for her, and the rest of
the
Garcia household would still be at the old street. Both behaviors are correct; they are
just different organizations.

## Common mistakes

**Editing the standard address boxes directly in a third party app.** Open Impact treats
the address records as the truth and copies the default into the standard address boxes. If
a third party app, a data loader, or an integration writes straight into the standard
boxes, Open Impact will put the default address back the next time that address record is
saved, and the edit will look like it vanished. Make the change
on the address card instead, or mark a new address as the default. This is also why address
verification apps should be pointed at the address records.

**Marking two addresses as default.** You cannot end up with two. Marking a second address
as the default clears the first one automatically. If you expected both to stay marked, you
wanted two addresses with different types (for example Home and Work), not two defaults.

**Filling in a seasonal address with no dates.** A Seasonal address needs all four date
boxes: start month, start day, end month, end day. Saving without them gives you
"A seasonal address needs a start month, a start day, an end month, and an end day so we
know when to use it." Fill in the four boxes, or change the type to Other if the address is
not really seasonal. A range that crosses New Year, such as November 1 to March 31, is one
range: enter it exactly that way, do not split it into two addresses.

**Choosing more than one owner for an address.** An address belongs to a household, to an
organization, or to one person, never to two at once. If you fill in both a household and a
person you get "An address belongs to one household, one organization, or one person.
Choose only one." Clear the one you did not mean. If you want a person to have their own
address inside a household, put the person on it and leave the household blank.

**Deleting the default address.** You can delete it, and Open Impact promotes the most
recently created remaining address to default so the household is never left with no
address in its standard boxes. If the household has only one address, deleting it leaves
the standard address boxes as they were and nothing is promoted. Prefer adding a new
address and marking it default over deleting the old one: the old address is the record of
where a mailing actually went.

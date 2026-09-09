# Acknowledgments

## What it does

Acknowledgment rules are your organization's written answer to "who gets thanked, and
how". You write a short list of rules, top to bottom: thank a first gift with a letter,
say nothing for the gifts under twenty dollars, write to the major donors, email everybody
else. Open Impact reads the list every time a gift is saved and takes the gifts that need
no thank you out of the list of gifts waiting for one.

Beside the rules sit your templates: the letters you write here, and the names of the
standard Salesforce email templates you built with the email editor. A rule points at one
of them.

**Open Impact does not send the thank you.** This release decides and records. It works
out which gifts need thanking and how, and when you mark a gift acknowledged it writes
down the date, the rule that applied, the wording that applied, and, for a letter, the
merged text exactly as it read on the day. Sending the letters and the emails is still
something you do: a mail merge, your email tool, or your own hand. Sending from inside
Open Impact is a later feature.

That division is deliberate and it is why the feature needs no new screen. You export the
gifts waiting to be thanked, send the thank yous however you already send them, and mark
the gifts acknowledged. Open Impact notices the change and records it, whether you made it
on one gift, on forty gifts in a list view, in an import file, or through an integration.

## How to turn it on

Everything is in the app. You never open Setup.

1. Open the **Fundraising** app.
2. Open **Acknowledgment Templates** and write your wording.
   - For a letter: choose **New**, name it (`Major donor letter`), set **Channel** to
     `Letter`, and type the letter in **Body**. Leave **Active** on.
   - For an email: build the email in Salesforce's own email template editor first, where
     you can preview it. Then come back, choose **New**, name it, set **Channel** to
     `Email`, and put that template's **unique name** in **Email Template Developer
     Name**. Leave **Body** empty.
   - You can have as many active templates per channel as you like. Unlike a receipt
     letter, there is no single "the" template: each rule picks its own.
3. Open **Acknowledgment Rules** and write your list. Each rule has:
   - a **name**, in your own words (`First gifts`, `Gifts over 1000`);
   - an **evaluation order**, a number. Rules are tested lowest first and **the first rule
     that matches a gift decides it**. Put your most specific rules at the top. Numbering
     in tens (10, 20, 30) leaves room to slot one in later;
   - the criteria, all optional: **minimum amount**, **maximum amount**, **gift type**,
     **appeal**, and **first gift only**. A criterion you leave empty matches everything,
     so a rule with no criteria at all is your catch-all;
   - a **channel**: `Letter`, `Email`, or `None`. `None` means no thank you is needed, and
     it is how you take small gifts, or an appeal you thank in person, out of the list;
   - a **template**, required unless the channel is `None`.
4. Leave **Active** on for every rule you want tested. Clear it to retire a rule without
   deleting it.

There are no settings for this feature. The rules and the templates are the configuration,
and they are records you edit in the app.

Amount ranges work the same way donor level rungs do: the **minimum is inclusive** and the
**maximum is exclusive**. A gift of exactly the maximum belongs to the next rule up. Set
each rule's maximum to the next rule's minimum and there are no gaps and no overlaps.

## A five-minute walkthrough

Start with the sample data loaded (Nonprofit Settings, then Sample data).

1. Open the **Fundraising** app, then **Acknowledgment Templates**. Choose **New**. Name
   it `Warm letter`, channel `Letter`, and type this in **Body**:

   ```
   Dear {{DonorFirstName}},

   Thank you for your gift of {{GiftAmount}} on {{GiftDate}}. It goes straight to work.

   {{SignerName}}
   {{SignerTitle}}
   {{OrganizationName}}
   ```

   Save.

2. Open **Acknowledgment Rules**. Choose **New**. Name it `No thank you for small gifts`,
   evaluation order `10`, maximum amount `50`, channel `None`, no template. Save.
3. Choose **New** again. Name it `Everything else`, evaluation order `20`, channel
   `Letter`, template `Warm letter`, and leave every criterion empty. Save. You now have a
   two rule list: nothing under fifty, a letter for everything else.
4. Use **Quick gift entry** to enter a gift of `25` from one of the sample households. Open
   the gift. **Acknowledgment status** reads `Not required`. Nobody has to remember to
   ignore it.
5. Enter a second gift of `500` from the same household. Open it. **Acknowledgment status**
   reads `To acknowledge`, and there is no acknowledgment date, because nothing has been
   sent yet.
6. This is the point where you would print the letter and post it. Do that, or imagine it.
7. Back on the gift, set **Acknowledgment status** to `Acknowledged` and save. The
   **acknowledgment date** fills in with today's date on its own.
8. Scroll to the **Acknowledgments** related list on the gift and open the record there. It
   names the rule (`Everything else`), the template (`Warm letter`), the channel
   (`Letter`), the date, and it holds the letter with the donor's name, the amount and the
   date already merged. That text is frozen: editing the template later does not change it.
9. Open the **Gifts** tab and make a list view filtered to acknowledgment status
   `To acknowledge`. That is your thank you list, and it is the thing you export before a
   letter run. When the run is done, select the gifts in the list view and set the status
   to `Acknowledged` for all of them at once. One record is written for each.

## What you can put in a letter

These are the only merge tokens Open Impact replaces. Type them exactly, braces included.
Anything else you type between braces is left alone and appears in the letter as you typed
it, which is how you spot a typo on the first proof rather than on a donor's copy.

| Token | What it becomes |
|---|---|
| `{{DonorFirstName}}` | The donor's first name, or an organization's whole name |
| `{{DonorName}}` | The donor's full name, or the organization's name |
| `{{GiftAmount}}` | The amount of the gift |
| `{{GiftDate}}` | The date of the gift |
| `{{GiftType}}` | How the gift arrived: Check, Card, Stock, and so on |
| `{{AppealName}}` | The appeal the gift responded to, if there is one |
| `{{OrganizationName}}` | Your organization's legal name, from Nonprofit Settings |
| `{{SignerName}}` | The name of the person who signs your letters, from Nonprofit Settings |
| `{{SignerTitle}}` | Their title, from Nonprofit Settings |

A token with nothing behind it, an appeal on a gift that has none, merges to nothing and
leaves a gap. It never stops the save.

The organization name, signer name and signer title come from **Nonprofit Settings**, under
your organization's details, the same three the Setup Assistant asks for when you set up
receipts.

## Common mistakes

**The catch-all rule is at the top of the list.** A rule with no criteria matches every
gift, so if its evaluation order is the lowest number, no other rule is ever reached. Open
**Acknowledgment Rules**, sort by evaluation order, and check that your specific rules
(first gifts, major gifts, one appeal) come before the one with nothing filled in.

**Two rules with the same amounts, and the wrong one wins.** The first match wins and
nothing else is consulted, so overlapping rules are not an error, they are just a
precedence question. Fix it by moving the rule you meant to win to a lower evaluation
order, not by narrowing the other one.

**A gift you expected to be thanked reads `Not required`.** A rule with a channel of
`None` matched it. Look at the rule list in order and find the first one whose criteria the
gift meets. If that rule is right but this gift is an exception, set the gift's
acknowledgment status back by hand: the rules never overwrite a status a person changed.

**"The acknowledgment rule (name) names wording that is missing, switched off, or for the
other channel."** This appears in the **Error Log**. Open that rule and look at its
template: it has been deactivated, deleted, or it is an email template on a letter rule.
The thank you was still recorded against the rule, without the wording. Fix the rule and
future ones will carry it.

**Nothing goes out.** Open Impact does not send. If you are waiting for the letters to
arrive somewhere, they will not: print or export them from the acknowledgment records, or
send from your own tool, then mark the gifts acknowledged.

**The letter on an old acknowledgment does not match the template.** That is correct and
deliberate. The record keeps what the donor actually read on the day. Edit the template and
the next thank you uses the new wording.

## For the report builder

| Thing | Where it is |
|---|---|
| The gifts waiting to be thanked | Gift, acknowledgment status `To acknowledge` |
| When a gift was thanked | Gift, acknowledgment date |
| Which rule and wording applied | Acknowledgment, related to the gift |
| The letter as it was sent | Acknowledgment, letter |
| Which standard email template applied | Acknowledgment, email template developer name |

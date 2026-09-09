# Health Check

## What it does

Health Check looks at your org and tells you, in plain language, whether Open Impact is set
up the way it should be. It reports what it found in your org (what else is installed, which
licenses are in play), whether your coexistence mode matches that, who can and cannot get
into the app, and anything that is currently getting in the way, such as paused automation
or errors nobody has looked at.

Every finding says what is wrong and what to do about it, and most of them have a button
that takes you straight to the place where you fix it.

Run it after you install, after you add people, and any time something feels wrong.

## How to turn it on

Health Check is on as soon as Open Impact is installed. There is nothing to enable and
nothing to configure.

1. Open the **Nonprofit Hub** app.
2. Click the **Nonprofit Settings** tab.
3. Choose **Health** in the left navigation. The report is there.
4. Click **Re-run** whenever you want a fresh look. Health Check reads your org each time;
   it never shows you a saved result.

The Nonprofit Hub home page does not carry a Health Check card today, although the Hub
itself has shipped. The settings console is the way in, and it is the way that always
works.

To act on a finding you need the **Manage Nonprofit Settings** permission, which the
Nonprofit Admin role includes. Without it you can still read most of the report: the page says
so at the top and the Fix buttons are hidden. Three checks are skipped for you rather than
answered wrongly, because Salesforce only lets you see your own access: who holds the
Nonprofit Admin role, who holds the Override Receipt Lock permission, and how many errors
nobody has read. In their place you get one line, **Sign in as a Nonprofit Admin to see the
access checks**.

## A five-minute walkthrough

Maria has just installed Open Impact into her organization's Nonprofit Cloud org. Person
Accounts are on. She has not set anything up yet.

1. Maria opens the **Nonprofit Hub** app, clicks **Nonprofit Settings**, and chooses
   **Health**.
2. The first card is **What we found in your org**. It reads:
   **Person Accounts enabled. Agentforce Nonprofit objects detected.** Under it, the card
   shows the mode this org is in now and the mode Open Impact recommends:
   **Agentforce Nonprofit coexistence**.
3. Below the card, the findings are grouped: **Your org**, **Licenses**, **Access**, and
   **Settings**. Each finding has an icon: a red circle for something that needs fixing, an
   amber triangle for something to be aware of, a blue dot for information.
4. The first finding is blue, **Your org at a glance**, and it repeats what was found in a
   sentence, adds that Open Impact supports this org shape directly, and says that Shield
   Platform Encryption cannot be detected from inside the app. If her org uses it, she should
   say so before she loads data.
5. The next finding is amber: **Coexistence mode is not confirmed yet**. It explains that
   Open Impact is running as Standalone but this org is a Nonprofit Cloud org, and that until
   she confirms, households will be built the wrong way for Person Accounts. There is a
   button, **Use recommended mode**.
6. Maria clicks **Use recommended mode**. The page saves Agentforce Nonprofit coexistence,
   switches household membership to junction mode with it, and re-runs. The amber finding is
   replaced by a blue one: **Coexistence mode matches your org**.
7. Under **Access** there is a red finding: **No one is assigned the Nonprofit Admin role**.
   She clicks **Open the Access page**, which takes her to the Access section of Nonprofit
   Settings, adds herself, and comes back to Health.
8. Another finding is amber: **4 users cannot see the app**. Four active users have a
   Salesforce license but none of the Open Impact roles, so the Nonprofit Hub is invisible to
   them. She clicks **Open the Access page** again and assigns roles.
9. There is a blue finding too: **The Gift Transaction mirror is in the Connect module**.
   Her org has Nonprofit Cloud gift objects and the Connect module is not installed, so if she
   wants Nonprofit Cloud's own donor summaries to keep working, that is what she will install
   in v0.6. Nothing is broken today.
10. She clicks **Re-run**. The red finding is gone, the amber ones are gone, and what is left
    is blue: her org shape, the mode, the Connect note, and **Automation is running normally**.

Total time: about five minutes, most of it assigning roles.

**If your org has the Nonprofit Success Pack instead**, step 2 reads **NPSP detected** and the
recommendation in step 5 is **NPSP coexistence**. Everything else is the same.

## What Health Check looks at

| Group | What it checks |
|---|---|
| Your org | What else is installed: Person Accounts, Nonprofit Cloud objects, the Nonprofit Success Pack, standard Sales and Service Cloud objects. |
| Your org | Whether your coexistence mode matches what was found. |
| Your org | Whether household membership is still set to the person's account while Person Accounts are on, which does not work. |
| Your org | Whether your org has Nonprofit Cloud gift objects while the Connect module is not installed. |
| Licenses | Whether the org uses more than one currency, which Open Impact does not support yet. |
| Access | Whether anyone holds the Nonprofit Admin role. |
| Access | Whether active users with a Salesforce license have no Open Impact role at all. |
| Access | Whether anyone holds the Override Receipt Lock permission, which is meant to be granted for one correction and taken away again. |
| Settings | Whether Open Impact automation is paused, and says so plainly when it is running. |
| Settings | Whether there are new entries in the Error Log that nobody has looked at. |
| Settings | Whether the fiscal year in Setup is the same month as the fiscal year start month in Nonprofit Settings. |
| Settings | Whether receipts have been voided with the reason "Generation failed", which is a receipt run that did not finish. |

Three of those are new: the Override Receipt Lock permission, the two fiscal years, and the
failed receipts. Each one is a quiet problem, where nothing looks broken and the cost arrives
months later, so each is explained in full below.

## The three quiet findings

| Finding | What it means | Why it matters | What to do |
|---|---|---|---|
| **Someone can override the receipt lock** | One or more active people hold the **Override Receipt Lock** permission. Open Impact ships it assigned to nobody. | That permission is the only way to change or delete a gift that carries a receipt number. It is meant to be granted in Setup for one correction and removed the same day. Left assigned, the guarantee that a receipted gift cannot change quietly stops being a guarantee, and nothing in the app will tell you again. | Read the names in the finding. If nobody is in the middle of a correction right now, open **Setup, Custom Permissions, Override Receipt Lock** and take it off the permission set or profile that grants it. Every change made with it is already in the Error Log at Warning severity, so you can see what it was used for. |
| **Your two fiscal years disagree** | The fiscal year in **Setup** starts in a different month from **Fiscal Year Start Month** in Nonprofit Settings. | Open Impact computes Giving This Year, Giving Last Year and Giving Two Years Ago from its own setting, and the packaged retention reports (LYBUNT, SYBUNT, new versus retained, conversion) read the fiscal year from Setup. When the two disagree, every one of those numbers is measured on a different year boundary. Nothing errors: a donor simply appears on the LYBUNT list while their Giving This Year is not zero, and usually nobody asks until a year end number is questioned. | Decide which month is right, then set both to it: **Setup, Company Information, Fiscal Year**, and **Nonprofit Settings, General, Fiscal Year Start Month**. The **Open general settings** button on the finding takes you to the second one. Recalculate rollups afterwards. |
| **Receipts failed to generate** | There are receipts with status **Void** and the reason **Generation failed**. | Every receipt number is used once. When a document fails to generate after its number was handed out, Open Impact records the number as a void receipt so an auditor asking what happened to number 47 gets an answer. One of those is ordinary. A number of them means receipt generation is failing over and over, donors are not getting the documents they are waiting for, and nobody has looked. | Open the Error Log from the finding and read the receipt entries: they say what failed. Fix the cause (most often a missing letter template or a donor with no address), then re-run the receipt or the statement run. The void records stay: they are the audit trail for the numbers that were consumed, and deleting them is not a fix. |

If one check cannot run, the rest still run. The check that failed appears as its own finding
saying so, and the details are written to the Error Log.

## Common mistakes

**Treating an amber finding as a failure.** Amber means "be aware of this", not "broken".
Multi-currency, for example, is amber forever if your org uses more than one currency: Open
Impact will not break, it simply does not do currency conversion yet, and there is nothing
you can do to make the finding go away.

**Ignoring the red membership finding in a Person Accounts org.** "Household membership does
not fit Person Accounts" is red for a reason: in that state, new households are built through
the person's account, which in a Person Accounts org is the person. Click **Switch to junction
membership** and the app fixes it for you. The longer it waits, the more households have to be
sorted out afterward.

**Fixing access by editing profiles.** Health Check counts the packaged roles the Access page
assigns, and the packaged permission sets behind them if you assigned one by hand. A profile
change or a permission set of your own may well let someone in, but Health Check will still
list them, because the packaged roles are what the app relies on.

**Reading the access findings from someone else's screen.** Salesforce only lets a person see
their own access, so for anyone without the Manage Nonprofit Settings permission Health Check
skips the two access counts rather than printing a number it cannot stand behind. If the report
you are looking at says **Sign in as a Nonprofit Admin to see the access checks**, that is why:
run it again as an administrator.

**Treating the Override Receipt Lock finding as a formality.** It is amber rather than red
because the permission may be legitimately assigned for the next ten minutes. It is on the
report because the failure mode is forgetting: nobody notices a permission that is still
assigned six months later, and while it is assigned, an issued receipt no longer means the
gift behind it cannot change.

**Fixing the fiscal year in one place.** Setting Nonprofit Settings and leaving Setup alone
(or the reverse) leaves the finding on the report and the reports wrong. Both values are a
month, and they have to be the same month.

**Deleting the "Generation failed" receipts to clear the finding.** Those records are what
account for the numbers that were used. Deleting them turns an explained gap into an
unexplained one, and the receipts still will not generate. Fix the cause and re-run.

**Leaving automation paused.** Pausing automation for a bulk load is exactly right. Forgetting
to turn it back on means households stop being created and names stop being recomputed, quietly.
That is why the paused finding is always shown, with the time it expires. If you see it and you
are not in the middle of a load, resume automation.

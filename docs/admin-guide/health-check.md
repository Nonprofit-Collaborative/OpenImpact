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
2. On the **Home** tab, find the **Health Check** card and click **Open Health Check**.
3. Click **Re-run** whenever you want a fresh look. Health Check reads your org each time;
   it never shows you a saved result.

To act on a finding you need the **Manage Nonprofit Settings** permission, which the
Nonprofit Admin role includes. Without it you can still read every finding: the page says so
at the top and the Fix buttons are hidden. That is deliberate, so that anyone can look at
the report and tell an administrator what it says.

## A five-minute walkthrough

Maria has just installed Open Impact into her organization's Nonprofit Cloud org. Person
Accounts are on. She has not set anything up yet.

1. Maria opens the **Nonprofit Hub** app and clicks **Home**, then **Open Health Check**.
2. The first card is **What we found in your org**. It reads:
   **Person Accounts enabled. Agentforce Nonprofit objects detected.** Underneath, a sentence
   explains what that means: this is a Nonprofit Cloud org, Open Impact supports it directly,
   and the recommended coexistence mode is **Agentforce Nonprofit coexistence**.
   The card also says that Shield Platform Encryption cannot be detected from inside the app,
   so if her org uses it she should say so to whoever helps her with data loads.
3. Below the card, the findings are grouped: **Your org**, **Licenses**, **Access**, and
   **Settings**. Each finding has an icon: a red circle for something that needs fixing, an
   amber triangle for something to be aware of, a blue dot for information.
4. The first finding is amber: **Coexistence mode is not confirmed yet**. It explains that
   Open Impact is running in Standalone mode but this org is a Nonprofit Cloud org, and that
   until she confirms, households will be built the wrong way for Person Accounts. There is a
   button, **Use recommended mode**.
5. Maria clicks **Use recommended mode**. The page saves Agentforce Nonprofit coexistence,
   switches household membership to junction mode with it, and re-runs. The amber finding is
   replaced by a blue one: **Coexistence mode matches your org**.
6. The next finding is red: **No one is assigned the Nonprofit Admin role**. She clicks
   **Open the Access page**, adds herself, and comes back.
7. Another finding is amber: **4 users cannot see the app**. It explains that four active
   users have a Salesforce license but none of the Open Impact roles, so the Nonprofit Hub is
   invisible to them. She clicks **Open the Access page** and assigns roles.
8. There is a blue finding too: **The Gift Transaction mirror is in the Connect module**.
   Her org has Nonprofit Cloud gift objects and the Connect module is not installed, so if she
   wants Nonprofit Cloud's own donor summaries to keep working, that is what she will install
   in v0.6. Nothing is broken today.
9. She clicks **Re-run**. The red finding is gone, the amber ones are gone, and what is left
   is blue: her org shape, the Connect note, and a note that automation is running normally.

Total time: about five minutes, most of it assigning roles.

**If your org has the Nonprofit Success Pack instead**, step 2 reads **NPSP detected** and
the recommendation in step 4 is **NPSP coexistence**. Everything else is the same.

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
| Settings | Whether Open Impact automation is currently paused. |
| Settings | Whether there are new entries in the Error Log that nobody has looked at. |

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

**Fixing access by editing profiles.** The Access page assigns the packaged roles, and that
is what Health Check counts. Giving someone access another way (a profile change, your own
permission set) may well let them in, but Health Check will still list them, because the
packaged roles are what the app relies on.

**Leaving automation paused.** Pausing automation for a bulk load is exactly right. Forgetting
to turn it back on means households stop being created and names stop being recomputed, quietly.
That is why the paused finding is always shown, with the time it expires. If you see it and you
are not in the middle of a load, resume automation.

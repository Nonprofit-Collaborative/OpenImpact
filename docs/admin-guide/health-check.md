# Health Check

## What it does

Health Check looks at your org and tells you, in plain language, whether Open Impact is set
up the way it should be. It reports what it found in your org (what else is installed, which
licenses are in play), whether your coexistence mode matches that, who can and cannot get
into the app, and anything that is currently getting in the way, such as paused automation
or errors nobody has looked at.

Every finding says what is wrong and what to do about it. Most of them have a button. Some of
those buttons take you to the page where you decide what to do. The rest do the work for you,
and those always show you what they are about to change before they change it.

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
so at the top and the Fix buttons are hidden. Two checks are skipped for you rather than
answered wrongly, because Salesforce only lets you see your own access: who holds the
Nonprofit Admin role, and how many errors nobody has read. In their place you get one line,
**Sign in as a Nonprofit Admin to see the access checks**.

## The buttons that fix things

Six findings can be put right from this page. Every one of them works the same way, and the
sequence is deliberate.

1. **You press the button.** Nothing has happened yet.
2. **Open Impact tells you what it is about to do**, counted from your org, not in general
   terms: how many records it will create, and their names. If the list is long it shows the
   first ten and says how many more there are.
3. **You press "Yes, make this change", or Cancel.** Cancel changes nothing.
4. **It reports what it actually did**, and the report underneath is re-run so you can see the
   finding go.

The six are: use the coexistence mode your org needs, switch household membership to the
junction, add the missing packaged rollups, add the missing automation switches, add the
missing import templates, and finish handing out the Nonprofit Admin role.

Four things are true of all six, and are worth knowing before you press anything.

- **None of them deletes anything.** Not a record, not a row, not ever. If the only way to
  clear a finding is to delete something, Health Check reports it and leaves it to you.
- **None of them touches your data.** They create configuration that this package ships and
  set settings that this package owns. No donor, no gift, no address, and no amount is read,
  changed, or removed by a fix.
- **Pressing one twice is the same as pressing it once.** Before it acts, it looks again. If
  there is nothing left to do it says so and changes nothing, so a stale page or a second
  administrator clicking at the same moment cannot do the work twice.
- **They finish or they do not happen.** If anything fails part way through, everything it did
  in that moment is undone, the details go to the Error Log, and the page tells you.

Some findings have no fix button on purpose, because the right answer depends on what your
organization meant and Health Check will not guess: who should hold the Nonprofit Admin role,
which people should get which role, whether paused automation should be resumed now, and what
to do about errors nobody has read. Those keep the button that takes you to the page where you
decide. The rule the project follows for which findings may have a fix button is written down
in `docs/architecture/decisions/0029-which-health-check-findings-get-a-fix-button.md`.

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
6. Maria clicks **Use recommended mode**. Nothing changes yet. A panel opens at the top of the
   page under the heading **Before Open Impact changes anything**, and it says: Open Impact
   will change the coexistence mode from Standalone to Agentforce Nonprofit coexistence, one
   setting changes, no record of hers is touched, and she can change it back on the General
   page. She clicks **Yes, make this change**. The page saves it, switches household membership
   to junction mode with it, and re-runs. A green line reports **The coexistence mode is now
   Agentforce Nonprofit coexistence**, and the amber finding is replaced by a blue one:
   **Coexistence mode matches your org**.
7. Under **Access** there is an amber finding she was not expecting: **The install did not
   finish giving out the Nonprofit Admin role**, and it says one person is in that state. That
   person is Maria: she installed the package, so Salesforce gave her the Nonprofit Admin
   permission set straight away and was still calculating the role when the install finished.
   She clicks **Finish the role assignment**, reads the preview, which names her and says that
   nobody gains any access they do not have today, and confirms. The finding is gone and her
   name is on the Access page.
8. Another finding is amber: **4 users cannot see the app**. Four active users have a
   Salesforce license but none of the Open Impact roles, so the Nonprofit Hub is invisible to
   them. This one has no fix button, because which role each of those four should get is her
   decision. She clicks **Open the Access page** and assigns roles.
9. Under **Settings** there is an amber finding: **Some of the rollups this package ships are
   missing**, with a count. This org has never opened the Rollups page, so the definitions that
   keep lifetime giving and last gift date were never created. She clicks **Add the missing
   rollups**, reads the list of what will be created, and confirms. The result line says how
   many were added and where to find them.
10. There is a blue finding too: **The Gift Transaction mirror is in the Connect module**.
    Her org has Nonprofit Cloud gift objects and the Connect module is not installed, so if she
    wants Nonprofit Cloud's own donor summaries to keep working, that is what she will install
    in v0.6. Nothing is broken today.
11. She clicks **Re-run**. The red finding is gone, the amber ones are gone, and what is left
    is blue: her org shape, the mode, the Connect note, and **Automation is running normally**.
12. Out of curiosity she clicks **Add the missing rollups** on the finding she has just fixed,
    from a browser tab she left open. The preview says there is nothing left to do, and nothing
    is created a second time.

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
| Access | Whether anyone holds the Nonprofit Admin permission set without the role that carries it, which is how a slow install leaves an org. |
| Settings | Whether Open Impact automation is paused, and says so plainly when it is running. |
| Settings | Whether any of the rollups this package ships were never created in your org. |
| Settings | Whether any packaged automation has no switch on the Automation page. |
| Settings | Whether any of the import templates this package ships were never created. |
| Settings | Whether any automation rows are left over from a version that no longer ships them. |
| Settings | Whether there are new entries in the Error Log that nobody has looked at. |

If one check cannot run, the rest still run. The check that failed appears as its own finding
saying so, and the details are written to the Error Log.

The last six of these count things across the whole org, so like the two access checks they are
only asked for a person holding the Manage Nonprofit Settings permission. A count taken from a
partial view of the org would be wrong, and a wrong count is worse than no count.

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

**Leaving automation paused.** Pausing automation for a bulk load is exactly right. Forgetting
to turn it back on means households stop being created and names stop being recomputed, quietly.
That is why the paused finding is always shown, with the time it expires. If you see it and you
are not in the middle of a load, resume automation.

**Expecting a fix button to clean up.** No fix button deletes anything, and none of them ever
will. The finding **Some automation rows are left over from an earlier version** is the clearest
case: those rows do nothing, because Open Impact runs the automations this version ships rather
than the rows on the page, and removing them is a decision for you rather than for a button.

**Reading a preview as a change.** Pressing a fix button changes nothing on its own. Until you
press **Yes, make this change**, you are reading a description of what would happen. Cancel is
always safe, and so is closing the tab.

**Adding the missing rollups and expecting yesterday's totals.** Creating a rollup definition
does not calculate it. The totals fill in when the rollup next runs, which is the nightly run,
or straight away if you use **Recalculate** on the Rollups page of Nonprofit Settings.

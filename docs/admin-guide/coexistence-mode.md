# Coexistence mode

## What it does

Open Impact can be the only fundraising system in your Salesforce org, or it can sit
alongside something that is already there. Coexistence mode is the one setting that tells
Open Impact which situation you are in, so that it works with the data you already have
instead of against it.

Most organizations arriving at Open Impact are already on Salesforce Nonprofit Cloud
(Agentforce Nonprofit), usually with Person Accounts turned on. That is the case Open Impact
is built to land in, and it has its own mode. Open Impact reads your org the first time you
open the Setup Assistant or the Health Check, proposes the matching mode, and asks you to
confirm it. You can change it later, and nothing about it is permanent.

## The three modes

| Mode | Choose it when | What it changes |
|---|---|---|
| **Agentforce Nonprofit coexistence** | Your org is on Nonprofit Cloud, or Person Accounts are turned on. This is the common case. | Household membership uses membership records rather than the person's account, so Person Accounts work properly and one person can belong to more than one household. Your Nonprofit Cloud objects are left alone. |
| **Standalone** | Your org is new, or it has never had a fundraising package in it. This is the default in a fresh org. | Households group people through the person's account. Nothing is mirrored anywhere else. |
| **NPSP coexistence** | The Nonprofit Success Pack is installed and you still want it working while you move. | Open Impact adopts your existing NPSP household accounts instead of building new ones, and (once the Connect module ships, in v0.6) keeps NPSP's own totals fed. |

If you are not sure, take the mode Open Impact proposes. It reads your org, it does not
guess.

## How to turn it on

Coexistence mode is always on: every org has a mode. What you do is confirm or change it.

1. Open the **Nonprofit Hub** app.
2. Click the **Nonprofit Settings** tab.
3. Choose **General** in the left navigation.
4. Find **Coexistence mode**. It shows the current mode and, underneath, what Open Impact
   detected in your org.
5. Pick a mode and click **Save**.

You need the **Manage Nonprofit Settings** permission to change it. If you do not have it,
the setting is visible but greyed out and the page tells you which permission to ask for.
Everyone with the Nonprofit Admin role has it.

There is nothing to do in Salesforce Setup. Detection happens inside the app.

## A five-minute walkthrough

Maria has just installed Open Impact into her organization's Nonprofit Cloud org. Person
Accounts are on, because that is how the org was set up for her two years ago.

1. Maria opens the **Nonprofit Hub** app, clicks the **Nonprofit Settings** tab, and chooses
   **Health** in the left navigation.
2. Health Check runs. The first card is **What we found in your org**.
3. It reads **Person Accounts enabled. Agentforce Nonprofit objects detected.** Underneath,
   in plain language: this is a Nonprofit Cloud org, Open Impact supports it directly, and
   the recommended mode is **Agentforce Nonprofit coexistence**.
4. Below the card there is a finding titled **Coexistence mode is not confirmed yet**, with
   the button **Use recommended mode**.
5. Maria clicks **Use recommended mode**. The page saves Agentforce Nonprofit coexistence,
   switches household membership to junction mode at the same time (Person Accounts require
   it), re-runs itself, and the finding is replaced by **Coexistence mode matches your org**.
6. She chooses **General** in the left navigation and sees Coexistence mode set to
   **Agentforce Nonprofit coexistence**. The change is in the settings history with her name
   and the time.

Total time: about two minutes. If Maria disagrees with the recommendation, she picks a
different mode in step 6 and saves. Nothing is locked.

**If your org has the Nonprofit Success Pack instead**, the same walkthrough applies with
different words: the card reads **NPSP detected**, the recommendation is **NPSP
coexistence**, and household membership stays on the person's account.

## Common mistakes

**Choosing Standalone in a Person Accounts org.** Standalone uses the person's account to
group a household, and in a Person Accounts org the person *is* an account, so households
stop making sense. Health Check reports this as an error with a one-click fix. Take the fix.

**Changing the mode to fix something else.** Coexistence mode is about what is installed in
your org, not about how you want households named or how gifts are entered. Those are their
own settings. If a household is named wrongly, change the naming settings, not the mode.

**Switching to Standalone in an org that has NPSP.** Open Impact will stop adopting your
existing household accounts and will start creating its own, which gives you two sets of
households for the same families. If you have already switched, switch back and ask for help
before doing anything else: no data is lost by switching back, but any households created in
the meantime are still there and need merging.

**Expecting the mode to move data.** Confirming a mode changes how Open Impact behaves from
that point on. It does not migrate anything, and it does not touch your Nonprofit Cloud
records. Importing your old data is a separate step in the Setup Assistant.

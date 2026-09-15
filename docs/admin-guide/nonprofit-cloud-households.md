# Households you already have in Nonprofit Cloud

## What it does

Salesforce Nonprofit Cloud has its own way of grouping people into a household, and Open
Impact has its own way. If your org is already using the Nonprofit Cloud way, both kinds of
household can end up on the same record, pulling in different directions. Open Impact now
looks for the households Nonprofit Cloud built and tells you what it found, so that you know
which of the two you are looking at before you change anything.

Finding them is all it does today. Open Impact does not move them, rename them, or take them
over.

## How to turn it on

There is nothing to turn on. Open Impact reads your org every time Health Check runs.

1. Open the **Nonprofit Hub** app.
2. Click the **Nonprofit Settings** tab.
3. Choose **Health** in the left navigation.
4. Read the **What we found in your org** card. If your org has households built the
   Nonprofit Cloud way, the card says so and gives you the number it counted.

If Open Impact cannot count them, it says that instead of showing you a number. That happens
when your own permissions do not let you read them, which is common and is not a problem with
your org. When the answer is not certain, Open Impact assumes the households are there and
stays out of their way. It would rather leave your data alone than tidy up something that was
never its to tidy.

## A five-minute walkthrough

Maria has installed Open Impact into an org that has been running Nonprofit Cloud for two
years. Her colleagues have been grouping families there the whole time.

1. Maria opens the **Nonprofit Hub** app, clicks **Nonprofit Settings**, and chooses
   **Health**.
2. The **What we found in your org** card tells her that this org already has households
   built the Nonprofit Cloud way, and how many.
3. She decides which way her organization is going to group families from now on. She picks
   one, and only one.
4. If she keeps using the Nonprofit Cloud households, she leaves Open Impact's household
   features alone and does not create Open Impact households for those families.
5. If she moves to Open Impact households, she does it for families that do not already have a
   Nonprofit Cloud household, and she leaves the ones that do until a migration is available.
6. She writes down which choice she made, so that the next person to enter a family knows
   where it goes.

Total time: about five minutes, and the only real work is step 3.

## Common mistakes

**Expecting Open Impact to take the households over.** It does not. An account that already
carries a Nonprofit Cloud household is left to Nonprofit Cloud. Open Impact will not name it,
will not tidy it up, and will not delete it when it looks empty, because to Open Impact it
always looks empty.

**Waiting for the migration.** A tool to move households from one model to the other is
planned, but it does not exist yet, and there is no date for it. Nothing in this version
moves them. If you need them moved today, that is manual work.

**Running both models on the same family.** This is the one that causes real damage, and it
is easy to do by accident: the family is grouped in Nonprofit Cloud, someone else groups it
again in Open Impact, and now two records disagree about who lives in that house. Reports
double up, letters go out twice, and neither household is wrong enough to be obviously wrong.
Pick one model per household and stay with it.

**Reading a missing number as a zero.** If the card cannot give you a count, that means
nobody could count them, not that there are none. Ask a colleague with fuller access to look,
or ask whoever set up your Nonprofit Cloud org.

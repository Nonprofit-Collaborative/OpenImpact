# Admin Guide

## Purpose

One page per feature, written **before** the Lightning web component that implements it,
for Maria.

Maria is the Operations Manager who installs and configures Open Impact. She is
comfortable with spreadsheets and modern web apps. She has no technical background, no
full-time Salesforce administrator to call, and no budget for a consultant. If she cannot
do the thing by following the page, the feature is not done (Principle 1, plan Section
1.3).

Writing the page first is a design tool, not a documentation chore. Plan Section 9.3 puts
it plainly: **write the admin-guide page before the LWC; if the page is hard to write,
the feature is too complicated.** A page that needs six screenshots and a warning box is
telling you to redesign the feature.

The page is also part of the definition of done (plan Section 7.4) and part of review:
the reviewer must try the feature as Maria with only this page as instructions (plan
Section 9.2).

## Required page structure

Every feature page has these four sections, in this order (plan Section 7.4):

### 1. What it does

Two or three sentences in the language a nonprofit uses. What problem it solves, and for
whom. No architecture, no object names.

### 2. How to turn it on

The exact steps to enable and configure the feature, all of them inside the app. If a
step requires Salesforce Setup, say why it cannot be avoided and link to the Setup
Assistant step that deep-links there. A feature that needs Setup for normal use has not
met the definition of done.

### 3. A five-minute walkthrough

A numbered path from nothing to a working result, with the sample data as the starting
point, that a person can complete in five minutes. This doubles as the manual acceptance
script Brandon runs before an iteration is promoted (plan Section 7.3).

### 4. Common mistakes

The three or four things that actually go wrong, each with how to recognize it and how to
fix it. Write these from what the tests and the walkthrough surfaced, not from
imagination.

## Personas

Use these names, from plan Section 2.2. They appear in user stories, in tests, and in
these pages, so that everyone is talking about the same person.

| Persona | Role |
|---|---|
| **Maria** | Operations Manager: installs and configures the package, the administrator |
| **David** | Development Director: runs fundraising, enters gifts, sends receipts |
| **Priya** | Program Coordinator: runs services and volunteers |
| **Tom** | Executive Director: accountable to the board and to funders |
| **Jen** | Board Treasurer or Bookkeeper: reconciles with accounting |
| **Sam** | Contributor: open source developer or administrator who contributes |

## Style rules

- **Nonprofit language, not Salesforce language.** "Gift" not "Donation Transaction",
  "Fund" not "General Accounting Unit", "Appeal" not "Campaign" (plan Sections 7.1 and
  13).
- **No API names in prose.** Maria never needs to know one (plan Section 2.3). Say "the
  household's formal greeting", not the field's API name. Where a page genuinely must
  name a field for a report builder, put it in a table at the end, not in the
  instructions.
- **No namespace prefixes anywhere**, in prose or in tables.
- **No em dashes.** Use colons, commas, or parentheses.
- **Second person, present tense, active voice.** "Open Nonprofit Settings and choose
  Households."
- **Say what to do, then what you will see.** Every step ends in a result the reader can
  check against.
- **Every error message quoted in the guide matches the message in the product**, word
  for word, so a search finds the page.
- **Screenshots are optional and expensive.** Prefer a clear step. A screenshot that goes
  stale is worse than no screenshot.

## Index

Each feature adds its row here when its page is written.

| Feature | Page | Package | Iteration |
|---|---|---|---|
| C-04 | [Automation control](automation-control.md) | Core | v0.1 |
| C-05 | [Error Log](error-log.md) | Core | v0.1 |

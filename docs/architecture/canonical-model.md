# Canonical Data Model

**Version:** v0.3
**Status:** governing specification for the v0.1, v0.2, and v0.3 builds
**Last updated:** 2026-09-08

## 1. Purpose

This document is the platform-neutral specification of the Open Impact data model. It
defines entities, attributes, relationships, and business rules in ordinary language,
independent of Salesforce. Each entity then cites the Salesforce metadata that
implements it.

It exists for three reasons (plan Section 4.4):

1. It keeps a far-future non-Salesforce runtime possible at near-zero cost today.
2. It is the best documentation a contributor or an AI agent can be given: one file that
   explains the whole shape of the data without reading the code.
3. It forces every schema addition through a moment of definition.

## 2. Rules

1. **No field is added to a Salesforce object that is not first added here with a
   one-line definition.** This is the first checkbox in the definition of done (plan
   Section 7.4). The canonical-model commit comes before the metadata commit.
2. The same rule covers picklist values, custom settings keys, and custom metadata
   fields, not only custom object fields.
3. Where this document and a Salesforce platform constraint disagree, the platform wins
   and the deviation is recorded as an ADR in `decisions/` with the workaround (plan
   Section 9.3).
4. Attribute names here are human names. Salesforce API names appear only in the
   implementation subsection of each entity.
5. Labels use nonprofit language, not Salesforce language: "Gift" not "Donation
   Transaction," "Fund" not "General Accounting Unit" (plan Section 7.1).

## 3. Versioning

This is **v0.3**. It covers three iterations, and each part says which one owns it:

- **Part A and Part B** are v0.1: the constituent entities and the platform configuration
  entities that the v0.1 features require.
- **Part C** is v0.2 in Core: the rollup engine's configuration and the import framework.
- **Part D** is the Giving package, v0.2 for gifts, allocations, funds, and appeals, and
  v0.3 for commitments, installments, soft credits, and tributes.
- **Part E** is v0.3 in Core: relationships, affiliations, and addresses.

Later iterations extend it. Section 30 lists what is deliberately absent and when it
arrives, so no one adds it early, and Section 32 says which package owns each entity.

## 4. Conventions

- **Entity names** are singular PascalCase with spaces where natural: `Household`,
  `Household Member`, `Contact`, `Organization`.
- **Attribute types** are platform-neutral:
  `text`, `long text`, `boolean`, `integer`, `decimal`, `date`, `datetime`,
  `picklist(value, value, ...)`, `reference(Entity)`.
- **Required** means required by our business rules, not necessarily enforced by a
  platform-level required flag. Where a rule is conditional the definition says so.
- **Computed** attributes are marked in the Required column as `computed`. Their inputs
  and formulas are documented in the entity's rules section.
- Every attribute has a one-line definition, written so an admin recognizes their data.
- Every entity cites its **Salesforce implementation**: object, record type, and field
  API names. No namespace prefix appears anywhere (plan Section 4.3).

### Person references

Every attribute that points at a person carries **a pair of references, and exactly one of
them is set**: a Contact reference for orgs where people are Contacts, and an Account
reference for orgs where people are person Accounts. Both are always defined, because the
same package runs in both kinds of org and no feature code branches on which is in use
(ADR-0005).

The pair is named the same way everywhere:

| Entity | Contact side | Account side |
|---|---|---|
| Gift, Commitment | Donor Contact | Donor Account |
| Soft Credit | Contact | Account |
| Relationship | Contact, Related Contact | Person Account, Related Person Account |
| Affiliation | Contact | Person Account |
| Address (personal owner) | Contact | Person Account |
| Tribute | Honoree Contact, Notification Recipient Contact | Honoree Account, Notification Recipient Account |
| Import Row | Contact 1, Contact 2 | Person 1 Account, Person 2 Account |
| Household Member | Contact | Account |

**No packaged metadata references a Person Account field** (plan Section 4.2 and
ADR-0009). The Account side is a plain lookup to Account. Whether a given account is a
person, and any name data held on it, is read dynamically at run time through
`HouseholdService`, so the package installs and behaves correctly in an org where Person
Accounts are not enabled.

Because a person can be an Account, the person attributes that v0.1 defined on Contact
(Deceased, Household Role, Exclude From Household Name, Exclude From Greetings, Preferred
Name) exist on Account as well. The Account copies are specified in Sections 5 and 7 with
the rest of the v0.1 model.

---

# Part A: Constituent entities

These are the four entities the v0.1 iteration builds (plan Section 9.1 step 4).

## 5. Household

### Definition

The unit of relationship and recognition for individual donors: one mailing address, one
greeting, one giving history (plan Section 13). A household groups the people a
nonprofit treats as a single donor for acknowledgment and reporting purposes. It is not
a legal entity and it does not imply a shared residence in every case, though it usually
does.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The household's display name, for example "The Smith Family"; recomputed from members unless Custom Name is set. |
| Formal Greeting | text | computed | The salutation used on formal correspondence, for example "Mr. and Mrs. John Smith". |
| Informal Greeting | text | computed | The salutation used on personal correspondence, for example "John and Jane". |
| Custom Name | boolean | yes (defaults false) | When true, Name, Formal Greeting, and Informal Greeting are never recomputed; the staff member's wording stands. |
| Primary Contact | reference(Contact) | no | The household member who receives correspondence when only one person can be named. |
| Member Count | integer | computed | The number of current (not ended, not deceased-excluded) members of the household. |
| Anniversary | date | no | A household-level date the nonprofit stewards, most often a wedding anniversary. |
| Record Type | picklist(Household, Organization) | yes | Distinguishes a household from an organization; a Household always carries Household. |
| Sample Data | boolean | yes (defaults false) | True when the record was created by the sample data loader so it can be removed in one action. |

### Relationships

- **Household to Contact**, one to many, through membership. The mechanism depends on
  the membership mode (see rules below) and is never referenced directly by callers.
- **Household to Household Member**, one to many, in junction mode only.
- Household is the target of the giving rollups defined from v0.2 onward. Those rollup
  target fields belong to the Giving package and are listed in Section 26, not here.
- **Household to Address**, one to many, from v0.3 (Section 29).

### Rules

Drawn from plan Section 4.6 and the acceptance criteria in Section 10.2.

**R-H1 Automatic creation.** In contact mode, inserting a Contact with no Account
creates a Household Account named per the naming rules, in the same transaction, and
attaches the Contact to it. This is controlled by the `Auto_Create_Households__c`
setting, default on. Bulk safety is required: 200 Contacts inserted in one DML operation
create their households without exceeding platform limits.

**R-H2 Person Accounts.** In junction mode with Person Accounts enabled, creating a
Person Account does not create a Household unless
`Create_Households_For_Person_Accounts__c` is on. When it is on, a Household is created
and a Household Member record links the Person Account to it.

**R-H3 Membership modes.** Membership has two modes, and both sit behind a single Apex
service so that no other code knows which is in use:

- *Contact mode* (default): the Contact's Account reference points at the Household.
  Simple, reportable, NPSP-compatible, and compatible with every AppExchange app that
  assumes a Contact belongs to an Account.
- *Junction mode* (required when Person Accounts are enabled, optional otherwise): a
  Household Member record joins a person to a household. This allows one person in more
  than one household (divorced parents, students) and preserves membership history.

The mode is an org-level setting (`Household_Membership_Mode__c`). Callers use
`HouseholdService`; direct reads of the membership mechanism outside that service are a
review failure.

**R-H4 Naming and greetings computation.** Name, Formal Greeting, and Informal Greeting
are computed from the household's members. Inputs:

- Each member's first name, preferred name (used in place of first name when present),
  last name, and salutation.
- Each member's Household Role, used for ordering.
- Each member's Deceased flag, Exclude From Household Name flag, and Exclude From
  Greetings flag.
- The org's configured patterns: `Household_Name_Pattern__c`,
  `Formal_Greeting_Pattern__c`, `Informal_Greeting_Pattern__c`.
- The org's `Include_Deceased_In_Name__c` setting.

Default patterns (plan Section 4.6 and 10.2):

| Case | Name | Formal Greeting | Informal Greeting |
|---|---|---|---|
| Members share a surname | "The Smith Family" | "Mr. and Mrs. John Smith" | "John and Jane" |
| Members have differing surnames | "Smith and Jones Household" | Both members listed with their own salutations and surnames | Both first names |
| One member | "The Smith Family" | "Mr. John Smith" | "John" |

**R-H5 Member ordering.** Members are ordered by Household Role (Head first, then Spouse
or Partner, then Child, then Other), and alphabetically by first name within a role, so
that a household's name and greetings are stable across recomputations.

**R-H6 Hyphenated and differing surnames.** A hyphenated surname is treated as one
surname and is never split. Two members are treated as sharing a surname only on an
exact match; otherwise the differing-surname pattern applies.

**R-H7 Deceased handling.** A member marked deceased is excluded from greetings. Whether
they remain in the household name is controlled by `Include_Deceased_In_Name__c`. When
the org chooses to keep a deceased member in formal correspondence, the formal greeting
offers a "the late" form, for example "Mrs. Jane Smith and the late Mr. John Smith".

**R-H8 Custom name override.** When Custom Name is true, no automatic recomputation
changes Name, Formal Greeting, or Informal Greeting. This is the mechanism that keeps
"The Reverend and Mrs. Smith" as staff typed it.

**R-H9 Exclusions.** Exclude From Household Name removes a member from the name
computation only; Exclude From Greetings removes them from both greetings only. The two
flags are independent.

**R-H10 Primary contact.** A household has at most one primary contact, and that contact
must be a current member of the household. When the primary contact leaves the
household, the reference is cleared and the next member by ordering is proposed, not
silently assigned.

**R-H11 Member count.** Member Count is recomputed on every membership change (insert,
update, delete, undelete, reparent, merge) and counts current members only. The field
carries no default value: it is written by household upkeep and only ever onto a household,
so an organization, which upkeep skips by record type, is left with an empty Member Count
rather than a count of zero it never earned.

**R-H12 Reparenting and empty households.** Moving a contact to a different household
recalculates both households' member counts and, once Giving is installed, their giving
rollups. The vacated household is deleted when it is empty and
`Delete_Empty_Households__c` is on.

**R-H13 Merge and split.** Two households can be merged (members move to the surviving
household, rollups recalculate, names and greetings recompute unless Custom Name is set)
and a contact can be split out to a new or existing household. Both are front-end
actions on the record page, not Setup operations.

Two households only: an organization is never a merge target, and the two records must
be different. A merge moves membership first, in whichever membership mode is active,
then applies the field values a person chose, then uses the platform's own account merge
so that activities, files, notes, and every lookup from another entity follow the record
that goes away. A merge is not reversible and is audited by the platform's own record
history rather than by a log this model defines. Membership changes made by a merge or a
split settle through one hook (member count and naming in v0.1, giving rollups from v0.2)
so that no caller has to know what settling involves. That settle-up never tidies the
surviving household away: the empty household rule (R-H12) is about the household somebody
was the last to leave, and the survivor of a merge is the record the merge exists to keep,
so two empty households merge into one empty household rather than into nothing.

**R-H14 Recompute action.** Changing a naming pattern in the settings console shows a
preview against five fixed sample households, computed in memory from the patterns being
typed: nothing is read from or written to the org's own households. The console also
offers a "Recompute all households" batch. Starting it confirms that the batch has been
queued; the batch runs in the background and reports neither progress nor completion to
the console, and its counts are written to the debug log only. Recomputation never touches
households with Custom Name set.

### Salesforce implementation

- **Object:** Account, record type `Household`. Organizations use record type
  `Organization`. Both record types ship with packaged page layouts and compact layouts.
- **Standard fields used:** `Name` (the computed household name).
- **Custom fields on Account:**

| Attribute | API name | Type |
|---|---|---|
| Formal Greeting | `Household_Formal_Greeting__c` | Text |
| Informal Greeting | `Household_Informal_Greeting__c` | Text |
| Custom Name | `Custom_Name__c` | Checkbox |
| Primary Contact | `Primary_Contact__c` | Lookup to Contact |
| Member Count | `Member_Count__c` | Number |
| Anniversary | `Anniversary__c` | Date |
| Sample Data | `Sample_Data__c` | Checkbox |
| Sample Data Key | `Sample_Data_Key__c` | Text(20) (v0.4) |

- **Person attributes on Account.** The five person attributes listed under Contact
  (Section 7) are present on Account as well, with the same API names and the same
  definitions: `Deceased__c`, `Household_Role__c`, `Exclude_From_Household_Name__c`,
  `Exclude_From_Greetings__c`, `Preferred_Name__c`. They belong to the person, not to the
  household, and they exist on both objects so that an org that stores people as accounts
  carries them on the person's own record. They are not shown on Household or Organization
  layouts.

- **Service:** `HouseholdService` (membership abstraction), `HouseholdNamingService`
  (R-H4 to R-H9), `HouseholdSelector` (all SOQL).

---

## 6. Household Member

### Definition

A person's membership in a household over a period of time. Used only in junction mode.
It is what allows one person to belong to more than one household and what preserves the
history of who was in a household when.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Contact | reference(Contact) | conditional | The person, when the person is represented as a Contact. |
| Account | reference(Account) | conditional | The person's own account, where the person is represented as an account rather than as a Contact (a Person Account). Never a household: the household side is the Household attribute below. |
| Household | reference(Household) | yes | The household the person belongs to. |
| Role | picklist(Head, Spouse or Partner, Child, Other) | no | The person's role in this household, used for greeting order and reporting. |
| Is Primary | boolean | yes (defaults false) | Marks the member who receives correspondence when only one person can be named. |
| Start Date | date | no | The date the person joined the household. |
| End Date | date | no | The date the person left the household; empty means current. |

### Relationships

- **Household Member to Contact**, many to one.
- **Household Member to Household**, many to one.
- Together these form the many-to-many join between people and households.

### Rules

**R-M1 Mode gating.** Household Member records exist only in junction mode. In contact
mode the object is present in the org (it ships with the package) but carries no records
and no automation writes to it.

**R-M2 Current membership.** A member is current when End Date is empty or in the
future. Only current members count toward Member Count, naming, and greetings.

**R-M3 One primary.** At most one current member of a household has Is Primary true.

The second half of this rule, that the primary member is mirrored to the household's
Primary Contact, is **not implemented and is not implementable as written**:
`Primary_Contact__c` is a lookup to Contact, so it cannot hold a person who is stored as a
Person Account, which is exactly the org shape junction membership exists for. No
automation derives the field from Is Primary; the only value household upkeep writes to it
is null, when the person it names is no longer a current member (R-H10). A merge can carry
an existing value to the survivor, but it never derives one. Recorded as a known gap in
Section 30.

**R-M4 Person representation.** Exactly one of Contact or Account identifies the person:
Contact where the person is a Contact, the person's own Person Account where Person
Accounts are enabled. Both empty, or both pointing at people, is invalid.

**R-M5 No direct callers.** All reads and writes go through `HouseholdService`. Feature
code never branches on membership mode.

### Salesforce implementation

- **Object:** `Household_Member__c` (junction).
- **Fields:** `Contact__c` (Lookup to Contact), `Account__c` (Lookup to Account),
  `Household__c` (Lookup to Account), `Role__c` (Picklist: Head, Spouse or Partner, Child,
  Other), `Is_Primary__c` (Checkbox), `Start_Date__c` (Date), `End_Date__c` (Date).
- `Household__c` is the household side of the junction and `Contact__c` or `Account__c` is
  the person side. `Household__c` is a required lookup with a cascade delete, matching the
  attribute table above: a membership row with no household says nothing, and a household
  that is deleted takes its own membership rows with it rather than leaving rows pointing at
  a record that is gone. Membership history survives everything except the deletion of the
  household it is history of.
- A lookup rather than a master-detail relationship is used so that membership rows are not
  owned by the household record for sharing and roll-up purposes, and so that the same
  object shape works in both membership modes.

---

## 7. Contact

### Definition

A person the nonprofit knows: a donor, a household member, a volunteer, a program
participant, a board member, or a staff contact at an organization. The Contact is the
person; the Household is how the nonprofit addresses and credits them.

### Attributes

Only the attributes v0.1 adds or relies on are listed. Standard name, email, phone, and
address fields are used as the platform provides them.

| Attribute | Type | Required | Definition |
|---|---|---|---|
| First Name | text | no | The person's given name as recorded. |
| Last Name | text | yes | The person's surname; the platform requires it. |
| Salutation | text | no | The title used in formal correspondence, for example Mr., Mrs., Dr. |
| Preferred Name | text | no | The name the person prefers to be called, used in greetings in place of first name when present. |
| Deceased | boolean | yes (defaults false) | Marks a person who has died; excluded from greetings and from most outreach. |
| Household Role | picklist(Head, Spouse or Partner, Child, Other) | no | The person's role in their household, used for greeting order. |
| Exclude From Household Name | boolean | yes (defaults false) | Leaves this person out of the computed household name. |
| Exclude From Greetings | boolean | yes (defaults false) | Leaves this person out of both computed greetings. |
| Employer | reference(Organization) | no | The organization this person works for, used to recognize the employer when a matching gift arrives (G-10). |
| Household | reference(Household) | conditional | The household this person belongs to; in contact mode this is the person's Account. |
| Sample Data | boolean | yes (defaults false) | True when the record was created by the sample data loader so it can be removed in one action. |

### Relationships

- **Contact to Household**, many to one in contact mode (one household per person), many
  to many in junction mode through Household Member.
- **Contact to Organization**, in v0.1 only the platform's own Contact to Account
  reference where an org chooses to relate a person to an organization directly. The
  Affiliation entity that models this properly arrives in v0.3 (Section 28).
- **Contact to Contact**, from v0.3, through Relationship (Section 27).
- Contact is a target of the giving rollups listed in Section 26 from v0.2.

### Rules

**R-C1 Every person has a household.** In contact mode a Contact inserted with no
Account gets one created (R-H1). A Contact is never left without a household unless
automatic creation is turned off.

**R-C2 Naming inputs.** Preferred Name, when present, replaces First Name in the
informal greeting and in any pattern that uses a personal name. Salutation feeds the
formal greeting.

**R-C3 Deceased.** Setting Deceased triggers recomputation of the household's greetings
and, depending on `Include_Deceased_In_Name__c`, its name.

**R-C4 Record type.** The package ships exactly one Contact record type, Household
Contact, so that an org can add its own record types without colliding with ours.

**R-C5 Person Accounts.** Where Person Accounts are enabled, a person may be represented
as a Person Account rather than a Contact. `HouseholdService` presents both uniformly;
no feature code branches on it.

### Salesforce implementation

- **Object:** Contact, record type `Household Contact`.
- **Standard fields used:** `FirstName`, `LastName`, `Salutation`, `AccountId`
  (household membership in contact mode).
- **Custom fields on Contact:**

| Attribute | API name | Type |
|---|---|---|
| Deceased | `Deceased__c` | Checkbox |
| Household Role | `Household_Role__c` | Picklist: Head, Spouse or Partner, Child, Other |
| Exclude From Household Name | `Exclude_From_Household_Name__c` | Checkbox |
| Exclude From Greetings | `Exclude_From_Greetings__c` | Checkbox |
| Preferred Name | `Preferred_Name__c` | Text |
| Sample Data | `Sample_Data__c` | Checkbox |
| Sample Data Key | `Sample_Data_Key__c` | Text(20) (v0.4) |
| Employer | `Employer__c` | Lookup to Account |

The seven above are person attributes, present on both Contact and Account with the same
API names so that Person Accounts carry them (Section 5). `HouseholdService.Person` is the
shape naming and greetings read, so no naming code knows which object a person came from.

- **Employer on the Account side:** in Person Account orgs the same attribute exists on
  Account as `Employer__c`, added there with the other person attributes (Section 4
  "Person references"). Both are plain lookups to Account, and neither is restricted by
  record type in metadata, because record types are the subscriber's to change; the
  matching gift service checks that the employer is an organization at run time (R-G11).

---

## 8. Organization

### Definition

A company, foundation, government agency, congregation, school, or other institution the
nonprofit knows: an organizational donor, an employer whose staff give, a funder, or a
partner. Organizations are not households and never carry household naming or greetings.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | yes | The organization's legal or commonly used name, entered by staff and never computed. |
| Record Type | picklist(Household, Organization) | yes | Always Organization for this entity. |
| Primary Contact | reference(Contact) | no | The person the nonprofit deals with at this organization. |
| Sample Data | boolean | yes (defaults false) | True when the record was created by the sample data loader so it can be removed in one action. |

### Relationships

- **Organization to Contact**, one to many, for people the platform relates to the
  organization. The typed, dated Affiliation entity arrives in v0.3 (Section 28).
- Organizations are donors in their own right from v0.2 onward, where a Gift's donor is
  either a Contact or an Account (Section 18), and they are targets of the giving rollups
  in Section 26.

### Rules

**R-O1 Never renamed by automation.** No naming or greeting computation touches an
Organization. Household automation is gated on record type.

**R-O2 No automatic creation.** Organizations are created by staff or by the importer,
never implicitly from a Contact insert.

**R-O3 Shared fields.** Primary Contact is the same Account field the Household entity
uses; the field is shared across record types and its meaning differs by record type as
defined above. Member Count, Anniversary, the two greeting fields, and Custom Name are
not shown on Organization layouts.

### Salesforce implementation

- **Object:** Account, record type `Organization`.
- **Fields:** standard `Name`; `Primary_Contact__c` (shared with Household, above);
  `Sample_Data__c` (Checkbox, shared field definition with Household, above);
  `Sample_Data_Key__c` (Text(20), shared with Household, holding the key the generated
  sample set knows this organization by).

---

# Part B: Platform configuration entities

These entities are not constituent data. They exist because v0.1 features require them
(plan Sections 4.8 and 10.3), and they are governed by the same rule as everything else:
nothing is added to them in Salesforce before it is added here.

## 9. Error Log

### Definition

One caught exception or handled failure, recorded where an administrator can find it in
the app rather than in debug logs (plan Sections 2.3 and 4.8).

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Timestamp | datetime | yes | When the error occurred. |
| User | reference(User) | no | The user whose action produced the error, where there was one. |
| Context | text | yes | The feature or source that produced the error, in plain language, for example "Household naming". |
| Record Reference | text | no | The identifier of the record involved, so the admin can open it. |
| Object Name | text | no | The kind of record involved, in the platform's name for it, so an admin can group errors by what they affect. |
| Message | long text | yes | A human-readable explanation of what went wrong and what to do about it. |
| Technical Detail | long text | no | Exception type, stack trace, and query or DML detail, for a developer or a support request. |
| Severity | picklist(Info, Warning, Error, Critical) | yes | How badly the failure affects the org's data or operations. |
| Status | picklist(New, Acknowledged, Resolved, Ignored) | yes | Where the admin has got to with this error. |

### Rules

**R-E1** Every caught exception in packaged code writes an Error Log record with a
message an administrator can act on. A silent catch is a review failure.
**R-E2** Error Log writing never itself throws; a failure to log is swallowed rather
than masking the original error.
**R-E3** The Hub shows a tile of unresolved errors, and an optional daily digest email
goes to the admin (feature C-23, v0.6).
**R-E4 The entry outlives the transaction it documents.** Most failures worth recording
end in a rollback: the save is refused and everything written in that transaction is
undone, an Error Log row included. So an entry is not written directly. It is published as
an **Error Log Event**, which the platform delivers whether or not the transaction commits,
and a subscriber writes the row. A direct write remains only as the fallback for when
publishing itself fails. Publishing is governed by Create on the event, so all three
packaged permission sets grant Read and Create on **Error Log Event**, Read Only
included. A user holding none of them falls back to the direct write, and for that user
the entry survives only when the transaction commits.

### Salesforce implementation

- **Object:** `Error_Log__c`, surfaced as an admin-only tab in the Nonprofit Hub app. The
  record name is the auto number `ERR-{000000}`.
- **Fields:** `Timestamp__c` (DateTime), `User__c` (Lookup to User), `Context__c` (Text),
  `Record_Reference__c` (Text), `Object_Name__c` (Text), `Message__c` (Long Text Area),
  `Technical_Detail__c` (Long Text Area), `Severity__c` (Picklist: Info, Warning, Error,
  Critical), `Status__c` (Picklist: New, Acknowledged, Resolved, Ignored).
- **Event:** `Error_Log_Event__e`, a platform event with publish behavior Publish
  Immediately, carrying the same values so that they survive a rollback (rule R-E4):
  `Message__c`, `Technical_Detail__c` (Long Text Area), `Context__c`,
  `Record_Reference__c`, `Object_Name__c`, `Severity__c`, `User_Id__c` (Text). The event
  has no Status: every entry is written as New.
- **Service:** `ErrorLogger`, with `ErrorLogWriter` (publishes the event, and is the only
  class allowed to write the object directly, in system mode, so that a failure is recorded
  even for a user without create access), `ErrorLogEventHandler` (the subscriber that
  writes the rows) and `ErrorLogSelector`.

---

## 10. Automation Setting

### Definition

One packaged automation, with a description an administrator can understand and a switch
to turn it off. This is the NPSP trigger-handler table done on the front end (plan
Sections 3.2 and 4.8), and it is what lets Maria get unstuck during an import without
calling anyone.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Automation Name | text | yes | The stable identifier of the automation, matching its entry in the shipped registry. |
| Description | long text | yes | What this automation does, in the language a nonprofit administrator uses. |
| Enabled | boolean | yes (defaults true) | Whether the automation runs; unchecking it bypasses the handler. |
| Always Runs | boolean | yes (defaults false) | Whether this automation enforces a rule rather than providing a convenience. An automation marked this way runs whatever the switch, the pause and the bypass say, and its switch is shown off and disabled in the console (ADR-0024). |
| Handler Class | text | no | The packaged code the dispatcher runs for this automation, copied from the shipped registry. |
| Object Name | text | no | The kind of record this automation runs on, copied from the shipped registry. |
| Execution Order | integer | no | The order in which this automation runs relative to others on the same kind of record. |
| Package Default | boolean | yes (defaults false) | Whether this record was materialized from the shipped registry rather than created by hand, so that "Restore defaults" knows what it owns. |

### Related org-level control

The global pause is not a property of any single automation. It is held in the org
settings entity (Section 12) as `Automation_Paused_Until__c`: a datetime after which
automation resumes by itself. While it is in the future, no packaged trigger logic runs
and the Hub shows a banner. This satisfies the C-04 acceptance criterion ("Pause all
automation for 2 hours") and the auto-expiry requirement in C-23.

### Rules

**R-A1** Every packaged trigger goes through the trigger framework and is therefore
bypassable (plan Section 7.2).
**R-A2** Records are materialized on install from the shipped registry custom metadata,
and new automations added by an upgrade are materialized without touching the admin's
existing on and off choices (Decision D-06).
**R-A3** Turning an automation off never deletes data and never suppresses error
logging.
**R-A4** An automation marked Always Runs enforces a rule rather than providing a
convenience, so the dispatcher does not consult the bypass, the pause or the switch for it.
The console still lists it, with its switch off and disabled and a line saying why, and a
request to switch it on or off is refused (ADR-0024).

### Salesforce implementation

- **Object:** `Automation_Setting__c` with `Automation_Name__c` (Text, external id,
  unique), `Description__c` (Long Text Area), `Enabled__c` (Checkbox),
  `Always_Runs__c` (Checkbox, default false), `Handler_Class__c` (Text),
  `Object_Name__c` (Text), `Execution_Order__c` (Number),
  `Is_Package_Default__c` (Checkbox). The record name holds the automation's label as the
  admin reads it.
- **Shipped defaults:** `Automation_Registry__mdt` (Section 13).
- **Org-level pause:** `Nonprofit_Settings__c.Automation_Paused_Until__c`.
- **Service:** `AutomationControl`, `TriggerDispatcher`.

---

## 11. Setting Change

### Definition

An audit entry recording that a setting was changed, by whom, when, and from what to
what. Required by the C-03 acceptance criterion that every settings change is logged
(who, when, old, new).

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Setting Name | text | yes | The setting that changed, recorded by its stable key. |
| Old Value | long text | no | The value before the change, blank when the setting had never been set. |
| New Value | long text | no | The value after the change, blank when the setting was cleared. |
| Changed By | reference(User) | yes | The user who made the change. |
| Changed At | datetime | yes | When the change was saved. |

### Rules

**R-S1** Every write through the settings service produces exactly one Setting Change
record per setting actually changed. Saving a page without changing anything writes
nothing.
**R-S2** Setting Change records are never edited or deleted by packaged code.
**R-S3** Values are stored as text so that any setting type can be audited uniformly.
**R-S4** A value that is not set is recorded as nothing, never as empty text. Unset and
cleared are the same state on a hierarchy custom setting, the platform stores empty text
as nothing anyway, and an audit row that claimed otherwise could never read back what it
was written with.
**R-S5** A value arrives at the settings service in whatever Apex type its caller holds,
not only as text. A Datetime handed in as a Datetime is stored as it is: `String.valueOf`
of a Datetime is not the ISO 8601 form the service parses back, so a round trip through
text would refuse the package's own writes.

### Salesforce implementation

- **Object:** `Setting_Change__c` with `Setting_Name__c`, `Old_Value__c`, `New_Value__c`
  (Long Text Area), `Changed_By__c` (Lookup to User), `Changed_At__c` (DateTime). The
  record name is the auto number `SC-{000000}`.
- **Service:** `SettingsService`.

---

## 12. Nonprofit Settings

### Definition

The org's simple, org-wide toggles and values: feature flags, mode selections, and
naming pattern choices. Stored as a protected hierarchy custom setting so that the
settings console can write them synchronously and so that they are cacheable (Decision
D-06).

### v0.1 keys

This is the **starting inventory** for v0.1. It is not closed. Each feature pull request
may add keys, and must add them here first.

| Key | Type | Default | Definition |
|---|---|---|---|
| `Coexistence_Mode__c` | picklist(Standalone, NPSP, AgentforceNonprofit) | Standalone | How this org coexists with what is already installed; set by the Setup Assistant after automatic detection and confirmable later (plan Section 4.5). |
| `Household_Membership_Mode__c` | picklist(Contact, Junction) | Contact | Whether household membership uses the Contact's Account reference or the Household Member junction. |
| `Auto_Create_Households__c` | boolean | true | Whether inserting a Contact with no household creates one automatically. |
| `Delete_Empty_Households__c` | boolean | true | Whether a household left with no members is deleted. |
| `Create_Households_For_Person_Accounts__c` | boolean | false | Whether creating a Person Account also creates a household and a membership record. |
| `Household_Name_Pattern__c` | text | The {LastName} Family | The pattern used to compute a household's name. |
| `Formal_Greeting_Pattern__c` | text | {Salutation} {FirstName} {LastName} | The pattern used to compute the formal greeting. |
| `Informal_Greeting_Pattern__c` | text | {FirstName} | The pattern used to compute the informal greeting. |
| `Include_Deceased_In_Name__c` | boolean | false | Whether a deceased member remains in the computed household name. |
| `Automation_Paused_Until__c` | datetime | empty | While in the future, all packaged automation is paused; it resumes by itself at this time. |
| `Setup_Steps_Completed__c` | text (255) | empty | The comma separated keys of the Setup Assistant steps the administrator has marked done, so the Hub checklist remembers progress across sessions. |
| `Setup_Steps_Skipped__c` | text (255) | empty | The comma separated keys of the Setup Assistant steps the administrator chose to skip for now, so a skipped step moves out of the way without counting as done. |
| `Setup_Started_At__c` | datetime | empty | When the administrator first changed something in the Setup Assistant, so the completion screen can say how long setup took. |
| `Organization_Legal_Name__c` | text (255) | empty | The organization's legal name as it appears on its tax filings, printed on receipts and year-end statements. |
| `Organization_EIN__c` | text (20) | empty | The organization's tax identification number (the EIN in the United States), printed on receipts. |
| `Organization_Address__c` | text (255) | empty | The organization's mailing address as one line, as it is printed on a receipt. Custom settings have no long text field, so a single 255 character line is the format. |
| `Receipt_Logo_Document_Id__c` | text (18) | empty | The Salesforce file identifier of the logo printed on receipts and letters. |
| `Receipt_Signature_Document_Id__c` | text (18) | empty | The Salesforce file identifier of the scanned signature printed on receipt letters. |
| `Receipt_Signer_Name__c` | text (80) | empty | The name of the person who signs receipt letters. |
| `Receipt_Signer_Title__c` | text (80) | empty | The job title of the person who signs receipt letters. |
| `Default_Fund__c` | text (18) | empty | The record identifier of the fund a gift is allocated to when nobody says otherwise. Written by the Setup Assistant only when the Giving module is present; Core never names the Giving objects statically (R-F4, ADR-0014). |
| `Default_Appeal__c` | text (18) | empty | The record identifier of the appeal a gift is credited to when nobody says otherwise, on the same terms as the default fund. |

### v0.2 keys

Added by the v0.2 features: the rollup engine (C-13) and the import framework (C-14). The
Setup Assistant (C-12) keys arrived early and are listed in the table above, where
`Setup_Steps_Completed__c` and `Setup_Steps_Skipped__c` are what was planned here as
`Setup_Assistant_Steps_Complete__c`, and the two default record identifiers ship with the
assistant that writes them.

| Key | Type | Default | Definition |
|---|---|---|---|
| `Fiscal_Year_Start_Month__c` | picklist(1 to 12) | 1 | The month the organization's fiscal year begins, used by every fiscal-year-aware rollup window (R-R3). |
| `Rollup_Mode_Default__c` | picklist(Real-time, Scheduled, Both) | Both | The mode a new rollup definition takes unless the admin changes it. |
| `Import_Chunk_Size__c` | integer | 200 | How many rows an import processes per chunk; lower it on an org with heavy custom automation. |

Custom settings do not support a long text attribute, so each step list holds a comma
separated set of keys within 255 characters, which the eight step checklist fits with
room to spare.

### v0.3 keys

Added by the v0.3 features: commitments (G-07), soft credits (G-08), relationships (C-15),
and addresses (C-17).

Three keys published here in v0.3 are no longer Core keys. ADR-0017 gives each package its
own settings object, so `Automatic_Household_Soft_Credits__c`,
`Installment_Generation_Horizon_Months__c` and `Installment_Overdue_Grace_Days__c` live on
the Giving package's own `Giving_Settings__c` and are specified in Section 21A. Core keeps
`Default_Fund__c` and `Default_Appeal__c`, because the Setup Assistant writes them and Core
must be able to read them with no Giving package installed.

| Key | Type | Default | Definition |
|---|---|---|---|
| `Contact_Address_Change_Behavior__c` | picklist(Update household, Create personal address) | Update household | What happens when a person's address is edited: the household moves, or that person gets an address of their own (R-AD5). |
| `Relationship_Auto_Reciprocal__c` | boolean | true | Whether the package creates and maintains the other side of every relationship (R-RL1). The default is applied in Apex by `SettingsService`, not by the field's own default value (ADR-0035). |
| `Seasonal_Address_Last_Run__c` | datetime | empty | When the seasonal address swap job last completed, shown on the Hub; written by the job (C-18, R-AD4, R-AD8). |
| `Seasonal_Address_Last_Run_Summary__c` | text | empty | What the last seasonal swap run did, in one sentence: how many addresses moved in, how many moved back, and how many failed (R-AD8). |

The four commitment keys (`Installment_Generation_Horizon_Months__c`,
`Installment_Overdue_Grace_Days__c`, `Auto_Apply_Gifts_To_Installments__c`, and
`Installment_Top_Up_Last_Run__c`) and `Automatic_Household_Soft_Credits__c` are Giving
keys and live on `Giving_Settings__c`, the Giving package's own protected hierarchy
custom setting, not on `Nonprofit_Settings__c`: a dependent package cannot add fields to
an object Core owns (ADR-0017). They are listed here because this section is the whole
settings inventory, and the settings console reads every registered settings object
through `Setting_Definition__mdt`, so an admin sees one console whichever object holds
the value.

### Rules

**R-N1 Protected and hierarchical.** The custom setting is protected (invisible to
subscriber Setup as editable configuration) and hierarchical, so the org-level values
are what packaged code reads.
**R-N2 Written from the app.** Values are written synchronously by Apex from the
settings console, never by asking the admin to open Setup (plan Section 2.3).
**R-N3 Cache invalidation.** Values are cached in Platform Cache and the cache is
invalidated on write, so a change takes effect on the next transaction and never appears
stale beyond ten seconds (C-03 acceptance criterion).
**R-N4 Audited.** Every write produces a Setting Change record (Section 11).
**R-N5 Extension procedure.** A feature that needs a new key adds a row to the table
above in the same pull request that adds the field, with its default and its one-line
definition.

### Salesforce implementation

- **Custom setting:** `Nonprofit_Settings__c`, hierarchy, protected.
- **Picklist keys are stored as text.** Custom settings do not support picklist fields on
  the platform, so `Coexistence_Mode__c` and `Household_Membership_Mode__c` are Text
  fields holding one of the values listed above, validated by `SettingsService` rather
  than by the field. The console renders them as a choice list, so Maria never types a
  value. Recorded as ADR-0019.
- **Service:** `SettingsService`, with the console LWCs `settingsConsole`,
  `settingsSearch`, `householdNamingSettings`.
- **Permission:** editing requires the `Manage_Nonprofit_Settings` custom permission;
  users without it see a read-only view naming the permission.

---

## 13. Shipped defaults (custom metadata)

Package-shipped defaults are read-only to admins and are materialized into the
corresponding records by the post-install script on first install and on "Restore
defaults." Upgrades update the shipped defaults without touching the admin's records.
This is how upgrade safety (Principle 6) is achieved (Decision D-06).

### Naming Pattern

`Naming_Pattern__mdt`: the household naming and greeting patterns the package ships, so
that a fresh org has working names on install and so that "Restore defaults" has
something to restore to.

| Field | Type | Definition |
|---|---|---|
| DeveloperName | text | The stable identifier of the shipped pattern. |
| Label | text | The name shown to the admin when choosing a pattern. |
| Description | long text | What this pattern produces, with an example. |
| Default Enabled | boolean | Whether this pattern is the one selected on a fresh install. |
| Pattern Type | picklist(Household Name, Formal Greeting, Informal Greeting) | Which of the three computed values this pattern produces. |
| Pattern | text | The pattern string itself, using the tokens the naming service understands. |

### Setting Definition

`Setting_Definition__mdt`: the catalog of everything the Nonprofit Settings console shows,
one row per setting or per section that a component renders, so that a feature adds its
settings to the console by shipping rows rather than by editing the console.

| Field | Type | Definition |
|---|---|---|
| DeveloperName | text | The stable identifier of this console row. |
| Label | text | The setting's name as the admin sees it in the console. |
| `Setting_Key__c` | text (80) | The API name of the settings field this row edits; blank for rows that render a component instead of a single value. |
| `Settings_Object__c` | text (80), default `Nonprofit_Settings__c` | The protected hierarchy custom setting this row reads and writes, so a module can ship rows against its own settings object (Decision ADR-0017). |
| `Section__c` | text (80) | The left navigation group this row belongs to, for example Households, Automation, Access, Health. |
| `Module__c` | text (40) | The package that ships this row, for example Core or Giving. |
| `Data_Type__c` | picklist(Checkbox, Text, Number, Picklist, DateTime, Component) | How the console renders and validates this row. |
| `Picklist_Values__c` | long text | The choices for a picklist row, as semicolon separated `value:label` pairs. |
| `Component__c` | text (80) | The Lightning web component rendered when the data type is Component. Core components only: the console imports them by name at compile time (Decision ADR-0020). |
| `Navigation_Target__c` | text (80) | The Lightning tab a module's own settings page lives on, used when the data type is Component and no component is named, because Core cannot import a component from a package that depends on it (Decision ADR-0020). |
| `Description__c` | long text | The plain-language help shown under the control. |
| `Help_Path__c` | text (255) | The admin guide path, relative to `docs/admin-guide/`, behind the row's Learn more link. |
| `Sort_Order__c` | number | The order of this row inside its section. |

### Automation Registry

`Automation_Registry__mdt`: the catalog of packaged automations, materialized into
Automation Setting records (Section 10) on install and on upgrade.

| Field | Type | Definition |
|---|---|---|
| DeveloperName | text | The stable identifier of the automation, matched to Automation Setting. |
| Label | text | The automation's name as the admin sees it. |
| Description__c | long text | What the automation does, in nonprofit language. |
| Enabled_By_Default__c | boolean | Whether the automation is on when it is first materialized. |
| `Always_Runs__c` | boolean, default false | Whether this automation enforces a rule rather than providing a convenience, so it cannot be switched off from the console or suppressed by a pause (ADR-0024). Copied to `Automation_Setting__c.Always_Runs__c` when the record is materialized. |
| Handler_Class__c | text | The Apex handler the trigger dispatcher invokes. |
| Object_Name__c | text | The object whose trigger this automation runs on. |
| Execution_Order__c | integer | The order in which handlers run for that object. |

The custom field API names are given here because two of the plain names in the original
draft ("Object" and "Order") are platform reserved words, and because the materialized
`Automation_Setting__c` fields carry the same names (Section 10). v0.1 ships the type with
no records: the first records arrive with feature C-01, which ships the first two trigger
handlers.

### Rollup Definition Default

`Rollup_Definition_Default__mdt` (v0.2): the rollup definitions the package ships,
materialized into `Rollup_Definition__c` records (Section 14) on install and on "Restore
defaults", matched by Definition Key. Both Core and Giving ship rows; the metadata type
itself belongs to Core.

| Field | Type | Definition |
|---|---|---|
| DeveloperName | text | The stable identifier of the shipped definition. |
| Label | text | The rollup's name as the admin sees it. |
| Description | long text | What this number means, in nonprofit language. |
| Definition Key | text | The key written to the materialized record and matched on upgrade. |
| Source Object | text | The entity whose records are aggregated. |
| Target Object | text | The entity that carries the number. |
| Relationship Path | text | The path from source to target, in the notation in R-R1. |
| Aggregate | picklist(SUM, COUNT, MIN, MAX, FIRST, LAST, AVG) | The calculation applied. |
| Source Field | text | The attribute aggregated, empty for COUNT. |
| Order By Field | text | The attribute that decides first and last. |
| Target Field | text | The attribute that receives the result. |
| Filter JSON | long text | The source filter document (R-R2). |
| Target Filter JSON | long text | The target filter document (R-R8). |
| Fiscal Year Aware | boolean | Whether the calculation is limited to a fiscal year window. |
| Fiscal Year Offset | integer | Which window: 0, -1, or -2. |
| Fiscal Date Field | text | The date attribute the window is measured on, written to the materialized definition. |
| Mode | picklist(Real-time, Scheduled, Both) | The mode the materialized definition starts in. |
| Default Active | boolean | Whether the definition is active when it is first materialized. |
| Package | text | The package that ships this row, so Giving's rows are materialized only when Giving is installed. |

### Import Template Default

`Import_Template_Default__mdt` (v0.2): the import templates the package ships,
materialized into `Import_Template__c` records (Section 15) the same way. Its fields
mirror the template's own attributes.

| Field | Type | Definition |
|---|---|---|
| DeveloperName | text | The stable identifier of the shipped template. |
| Label | text | The template's name as the admin sees it. |
| Description | long text | What kind of file this template reads. |
| Template Key | text | The key written to the materialized record and matched on upgrade. |
| Column Mapping JSON | long text | The mapping document (R-IT1). |
| Default Values JSON | long text | The defaults document (R-IT1). |
| Matching Rule | picklist(Email exact, Name plus postal code, External ID) | The matching rule the template starts with. |
| Person Mode | picklist(Contacts, Person Accounts) | Whether the template creates Contacts or person Accounts, overridden from the detected org shape on materialization. |
| Default Active | boolean | Whether the template is offered when it is first materialized. |

### Relationship Type

`Relationship_Type__mdt` (v0.3): the mapping from a relationship type to its reciprocal,
read by the relationship service when it maintains the other side of a connection
(Section 27, R-RL3).

| Field | API name | Type | Definition |
|---|---|---|---|
| DeveloperName | `DeveloperName` | text | The stable identifier of the shipped type. |
| Label | `MasterLabel` | text | The type as the admin sees it, for example Parent. |
| Type | `Type__c` | text | The type as it appears in the Type picklist. |
| Reciprocal Type | `Reciprocal_Type__c` | text | The type the other side takes, for example Child for Parent. |
| Is Gendered | `Is_Gendered__c` | boolean | Whether the reciprocal depends on a person's gender; false on every shipped row, and the package ships no gendered mapping. |
| Active | `Active__c` | boolean | Whether this mapping is applied. |
| Description | `Description__c` | long text | What this relationship means, in nonprofit language. |

The API names are given here, as they are for Automation Registry above, because the
shipped records name fields and a record that names a field its type does not define
refuses the whole deployment.

### Rule

**R-D1** These lists are the **starting inventory** for the iterations covered here and
each feature pull request may extend them. Any new custom metadata field is added to the
tables above before the metadata file is created.

---

# Part C: Core additions for v0.2

These entities are built by the v0.2 iteration in the Core package (features C-12, C-13,
C-14). They are configuration and staging entities, not constituent data, and they follow
the storage split in ADR-0006: the admin manages them as lists, so they are custom
objects, and the defaults the package ships for them are custom metadata materialized on
install (Section 13).

The fourth v0.2 Core feature, the full Setup Assistant (C-12), adds no entity. Its
resumable checklist records step completion in the Nonprofit Settings key
`Setup_Assistant_Steps_Complete__c` (Section 12), and its "pick default fund and appeal"
step writes `Default_Fund__c` and `Default_Appeal__c` in the same place.

## 14. Rollup Definition

### Definition

One calculated number: which records are counted, how they reach the record that shows
the number, what is aggregated, and when it is recalculated. This is the whole
configuration surface of the rollup engine (plan Section 4.10, feature C-13). An
administrator creates and edits these in the settings console with a filter builder, and
never types SOQL (plan Section 2.3).

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | yes | The rollup's name as the admin sees it, for example "Household total giving". |
| Description | long text | no | What this number means, in the language a nonprofit administrator uses. |
| Definition Key | text | yes | The stable identifier of this rollup, matching the shipped default it came from; unique. |
| Source Entity | text | yes | The entity whose records are aggregated, for example Gift. |
| Target Entity | text | yes | The entity that carries the calculated number, for example Household. |
| Relationship Path | text | yes | How a source record reaches its target, written in the path notation below; supports the household membership abstraction. |
| Aggregate | picklist(SUM, COUNT, MIN, MAX, FIRST, LAST, AVG) | yes | The calculation applied to the matching source records. |
| Source Attribute | text | conditional | The attribute aggregated; required for every aggregate except COUNT. |
| Order By Attribute | text | conditional | The attribute that decides which record is first or last; required for FIRST and LAST. |
| Target Attribute | text | yes | The attribute on the target entity that receives the result. |
| Filter | long text | no | Which source records count, held as a filter document (see R-R2); empty means all of them. |
| Target Filter | long text | no | Which target records this definition maintains, held in the same filter format; empty means all of them. |
| Fiscal Year Aware | boolean | yes (defaults false) | Whether the calculation is limited to one fiscal year window. |
| Fiscal Year Offset | integer | conditional | Which window: 0 this fiscal year, -1 last, -2 two years ago; required when Fiscal Year Aware is true. |
| Fiscal Date Attribute | text | conditional | The date attribute the window is measured on, for example the gift date; required when Fiscal Year Aware is true and the attribute being aggregated is not itself the date. |
| Mode | picklist(Real-time, Scheduled, Both) | yes | When the number is recalculated; defaults from the org's rollup mode default. |
| Last Calculated | datetime | computed | When this definition last completed a calculation, of any scope. |
| Is Package Default | boolean | yes (defaults false) | Marks a definition materialized from a shipped default rather than created by the admin. |
| Active | boolean | yes (defaults true) | Whether the engine runs this definition; turning it off never deletes the values already calculated. |

### Relationships

- **Rollup Definition to shipped default**, many to one by Definition Key, for the
  definitions the package ships (Section 13, `Rollup_Definition_Default__mdt`).
- Rollup Definition names its source and target entities as text, not as references, so a
  Core definition can drive a Giving object without Core holding a reference to the
  Giving package (R-R7).

### Rules

**R-R1 Path notation.** Relationship Path is a sequence of segments separated by ` > `.
Each segment is either a reference attribute on the entity reached so far, or one of the
mode-resolved tokens below. Alternatives are separated by ` | ` and are evaluated in
order: the first alternative that resolves to a record is the target for that source
record, and a source record whose alternatives all resolve to nothing is not counted.

| Token | Meaning |
|---|---|
| `{Household}` | The household of the person reached so far, resolved by `HouseholdService`: the Contact's Account reference in contact mode, the current `Household_Member__c` row in junction mode. |
| `{HouseholdMembers}` | Every current member of the household reached so far, resolved the same way and in the same two modes. |

Examples: `Household__c` (a gift to the household it already resolved to),
`Donor_Contact__c > {Household}` (a gift to its contact donor's household),
`Household__c | Donor_Account__c` (a gift to its household when it has one, otherwise to
the account that gave it).

The engine resolves the tokens through `HouseholdService` and never reads
`Contact.AccountId` or `Household_Member__c` directly, so the same packaged definitions
are correct in contact mode and in junction mode, including where the donor is a person
Account (ADR-0005 and Section 4 "Person references"). No packaged definition names a
Person Account field in metadata; where a filter must test one, the field name appears
inside the filter document as text and is resolved dynamically at run time (plan
Section 4.2).

**R-R2 Filter representation.** Filter and Target Filter are stored as one filter
document per definition, in the format below, rather than as child Filter Condition
records.

```
{
  "version": 1,
  "logic": "1 AND (2 OR 3)",
  "conditions": [
    { "id": 1, "field": "Status__c", "operator": "equals", "value": "Received" },
    { "id": 2, "field": "Amount__c", "operator": "greater than", "value": 0 },
    { "id": 3, "field": "Type__c", "operator": "in", "value": ["Grant", "Stock"] }
  ]
}
```

Operators: equals, not equals, less than, less or equal, greater than, greater or equal,
contains, does not contain, starts with, is null, is not null, in, not in. The `logic`
key is optional and defaults to every condition joined by AND.

*Why a document and not child rows.* Nothing the plan requires breaks without child rows.
A filter is never managed as a list in its own right: it is built, saved, and shipped as
part of one definition, so child rows would add parent-child DML ordering, orphan
cleanup, a sort attribute, and a second sharing surface for no gain. Materializing a
shipped default stays one record instead of a parent plus n children, cloning a
definition stays one copy, and a definition exported to a JSON file in the repository
stays one row. The cost is that individual conditions are not reportable and the platform
cannot validate them, so the settings service validates the document on save, the filter
builder is the only writer, and the `version` key exists so the format can change without
anyone having to guess what an older row meant.

**R-R3 Fiscal-year windows.** When Fiscal Year Aware is true, the window is computed at
run time from the org's fiscal year start month (Section 12) and Fiscal Year Offset, and
it is measured on the Fiscal Date Attribute. A definition that sums an amount has no date
of its own to bound, so the attribute that decides which year a record falls in is named
separately; a definition that aggregates a date directly may leave it empty, and the
attribute being aggregated is used.
Windows are never stored on the definition, so changing the fiscal year start month and
recalculating is enough to correct every fiscal rollup in the org.

**R-R4 Modes.** Real-time recalculates in the transaction that changed a source record.
Scheduled recalculates in the nightly batch. Both does the first and reconciles with the
second, and it is the mode the packaged giving definitions ship with, because it is the
combination that keeps the numbers visibly right (Principle 2).

**R-R5 Freshness.** Last Calculated on the definition answers "when was this number last
calculated" for the admin looking at the rollup list. The record page answer comes from
one last-calculated attribute per target entity, not one per target attribute; the
reasoning is in Section 26.

**R-R6 Upgrade safety.** Definitions with Is Package Default true are created from
`Rollup_Definition_Default__mdt` on install and on "Restore defaults", matched by
Definition Key. An upgrade adds newly shipped definitions and never overwrites a
definition the admin has edited (ADR-0006). An admin who does not want a packaged
definition sets Active to false; packaged code never deletes an admin's records.

**R-R7 No cross-package reference.** Source Entity, Target Entity, Source Attribute,
Target Attribute, and Order By Attribute are text. Core therefore drives rollups over
Giving objects without holding a reference to them, which the package dependency
direction forbids (ADR-0014).

**R-R8 Disjoint targets.** Two active definitions may write the same Target Attribute on
the same Target Entity only when their Target Filters make their target record sets
disjoint. This is what lets one total giving attribute on Account serve households
through one definition and organizations and person Accounts through another. The
settings console refuses a save that would overlap.

**R-R9 Idempotency and negative amounts.** Recalculating any set of records produces the
same result as calculating it the first time, and every aggregate is correct in the
presence of the negative gifts that refunds and write-offs create (ADR-0010, ADR-0011). A
definition that sums money therefore has to admit both sides of a reversal: the negative
gift and the original whose status the reversal changed. A status filter that admits only
Received breaks this rule rather than serving it, which is what ADR-0022 corrects in the
packaged defaults of Section 26.

**R-R10 Validation on save.** The target attribute must exist and be writable, the
aggregate must suit the source attribute type, and FIRST and LAST must have an Order By
Attribute. A definition that fails validation is not saved, and the message names the
problem in plain language.

### Salesforce implementation

- **Object:** `Rollup_Definition__c`, listed and edited in the settings console.

| Attribute | API name | Type |
|---|---|---|
| Name | `Name` | Text (standard) |
| Description | `Description__c` | Long Text Area |
| Definition Key | `Definition_Key__c` | Text, External Id, unique |
| Source Entity | `Source_Object__c` | Text |
| Target Entity | `Target_Object__c` | Text |
| Relationship Path | `Relationship_Path__c` | Text |
| Aggregate | `Aggregate__c` | Picklist: SUM, COUNT, MIN, MAX, FIRST, LAST, AVG |
| Source Attribute | `Source_Field__c` | Text |
| Order By Attribute | `Order_By_Field__c` | Text |
| Target Attribute | `Target_Field__c` | Text |
| Filter | `Filter_JSON__c` | Long Text Area |
| Target Filter | `Target_Filter_JSON__c` | Long Text Area |
| Fiscal Year Aware | `Fiscal_Year_Aware__c` | Checkbox |
| Fiscal Year Offset | `Fiscal_Year_Offset__c` | Number (0 decimals) |
| Fiscal Date Attribute | `Fiscal_Date_Field__c` | Text |
| Mode | `Mode__c` | Picklist: Real-time, Scheduled, Both |
| Last Calculated | `Last_Calculated__c` | DateTime |
| Is Package Default | `Is_Package_Default__c` | Checkbox |
| Active | `Active__c` | Checkbox |

- **Shipped defaults:** `Rollup_Definition_Default__mdt` (Section 13).
- **Settings keys:** `Fiscal_Year_Start_Month__c`, `Rollup_Mode_Default__c` (Section 12).
- **Service:** `RollupService`, `RollupSelector`, `RollupFilterParser`, `RollupBatch`,
  `RollupScheduler`, subject to the vendoring evaluation in ADR-0011.

---

## 15. Import Template

### Definition

A reusable mapping from the columns of a spreadsheet to the entities and attributes they
describe, together with the matching rules and default values that decide whether a row
creates a record or updates one (plan Section 4.9, feature C-14). A template is what lets
Maria load the same payment processor export every month without rebuilding the mapping.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | yes | The template's name as the admin sees it, for example "Generic donor list". |
| Description | long text | no | What kind of file this template reads, with an example of its columns. |
| Template Key | text | yes | The stable identifier of this template, matching the shipped default it came from; unique. |
| Column Mapping | long text | yes | The mapping from source column names to canonical targets, held as a mapping document (see R-IT1). |
| Matching Rule | picklist(Email exact, Name plus postal code, External ID) | yes | How an incoming row is matched to an existing person or organization before a new one is created. |
| Default Values | long text | no | Values applied to every row that does not carry its own, held in the same document format. |
| Person Mode | picklist(Contacts, Person Accounts) | yes | Whether a person in this file becomes a Contact or a person Account; defaulted from the detected org shape. |
| Is Package Default | boolean | yes (defaults false) | Marks a template materialized from a shipped default rather than built by the admin. |
| Is Recurring | boolean | yes (defaults false) | Marks a template used for an ongoing feed, so the Hub can show how long it is since the last load. |
| Source Name | text | conditional | The named source of a recurring feed, for example "Monthly processor export"; required when Is Recurring is true. |
| Last Import Date | date | computed | The date a batch using this template last completed, shown on the Hub. |
| Active | boolean | yes (defaults true) | Whether the template is offered in the import wizard. |

### Relationships

- **Import Batch to Import Template**, many to one: every batch records the template it
  ran with, so a result can still be explained after the template changes.

### Rules

**R-IT1 Mapping document.** Column Mapping and Default Values are held as one document
per template, in the format below, for the same reasons the rollup filter is (R-R2): a
mapping is built and saved as one unit in the two-column picker, and is shared as a
single JSON file in `data/import-templates/` so the community can contribute
processor-specific templates (plan Section 4.9).

```
{
  "version": 1,
  "columns": [
    { "source": "Donor Email", "target": "Contact1.Email" },
    { "source": "Gift Amount", "target": "Gift.Amount__c" },
    { "source": "Fund", "target": "Allocation.Fund" }
  ],
  "defaults": [
    { "target": "Gift.Type__c", "value": "Check" }
  ]
}
```

Targets are written as `Entity.Attribute` using the row entity names in R-IR1, so a
template can be read without knowing the object model.

**R-IT2 Matching rules in plain language.** The wizard states what each matching rule
does and what it risks, for example that "Name plus postal code" merges two people who
share a name at one address. No rule is offered without that sentence (plan Section 2.3).

**R-IT3 Person mode.** Person Mode is proposed from the org shape detected by the Setup
Assistant: Person Accounts where the org uses them, Contacts otherwise. The admin can
override it per template, and the processor resolves the person references in R-IR1
accordingly.

**R-IT4 Upgrade safety.** Templates with Is Package Default true are materialized from
`Import_Template_Default__mdt` on install and on "Restore defaults", matched by Template
Key, and are never overwritten once the admin has edited them (ADR-0006).

**R-IT5 What v0.2 ships.** v0.2 ships a generic donor list template and a generic gift
list template. The NPSP template set is v0.3 engineering work and the Agentforce
Nonprofit set is v0.5 (plan Section 6); both are new shipped-default rows, not new
attributes.

### Salesforce implementation

- **Object:** `Import_Template__c`.

| Attribute | API name | Type |
|---|---|---|
| Name | `Name` | Text (standard) |
| Description | `Description__c` | Long Text Area |
| Template Key | `Template_Key__c` | Text, External Id, unique |
| Column Mapping | `Column_Mapping_JSON__c` | Long Text Area |
| Matching Rule | `Matching_Rule__c` | Picklist: Email exact, Name plus postal code, External ID |
| Default Values | `Default_Values_JSON__c` | Long Text Area |
| Person Mode | `Person_Mode__c` | Picklist: Contacts, Person Accounts |
| Is Package Default | `Is_Package_Default__c` | Checkbox |
| Is Recurring | `Is_Recurring__c` | Checkbox |
| Source Name | `Source_Name__c` | Text |
| Last Import Date | `Last_Import_Date__c` | Date |
| Active | `Active__c` | Checkbox |

- **Shipped defaults:** `Import_Template_Default__mdt` (Section 13).
- **Service:** `ImportTemplateService` (materialization and save), `ImportTemplateSelector`,
  `ImportMapping` (the mapping document in R-IT1), `ImportColumnLibrary` (the known column
  names automatic mapping suggests from), LWC `importWizard`.

---

## 16. Import Batch

### Definition

One upload: the file, the template it was read with, what happened, and the log of it
(plan Section 4.9). A batch is the unit an administrator dry-runs, commits, and in v0.5
undoes.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The batch's identifier, assigned automatically. |
| Import Template | reference(Import Template) | yes | The mapping this batch was read with. |
| File Reference | text | yes | The identifier of the uploaded file stored as a Salesforce File, so the original can be downloaded again. |
| File Name | text | yes | The name of the file as the admin uploaded it. |
| Status | picklist(Draft, Parsing, Dry run, Dry run complete, Committing, Complete, Failed, Undone) | yes | Where this batch has got to. |
| Is Dry Run | boolean | yes (defaults true) | Whether this pass only previewed what would happen; a committed batch has run at least one dry run first. |
| Row Count | integer | computed | How many rows the file contained. |
| Rows Created | integer | computed | How many rows created at least one new record. |
| Rows Updated | integer | computed | How many rows updated an existing record. |
| Rows Matched | integer | computed | How many rows matched an existing record and changed nothing. |
| Rows Rejected | integer | computed | How many rows failed and appear in the exceptions file. |
| Run Log | long text | no | The plain-language log of the run, including the reason for a failure. |
| Started At | datetime | computed | When processing began. |
| Completed At | datetime | computed | When processing finished, successfully or not. |
| Chunk Size | integer | yes | Rows per chunk for this run, defaulted from the org's import chunk size. |
| Undo Deadline | datetime | no | The end of the window in which this batch can be undone; set on commit, used by v0.5 (C-19). |
| Committed By | reference(User) | no | The user who committed the batch, empty while it is a dry run. |

### Relationships

- **Import Batch to Import Row**, one to many, and the rows are deleted with the batch.
- **Import Batch to the records it created**, one to many, through the Created By Import
  Batch reference that Household, Contact, Organization, and Gift each carry (R-IB3).

### Rules

**R-IB1 Dry run first.** A batch is committed only after a dry run has completed against
the same file and template, and the dry run makes the same resolution decisions the
commit will make. The preview counts and the downloadable exceptions file come from the
Import Row records the dry run wrote.

**R-IB2 Chunked and asynchronous.** Rows are processed in chunks of Chunk Size in Batch
Apex, with progress visible on the batch record, so a file of hundreds of thousands of
rows completes without the admin watching a spinner (plan Section 4.9).

**R-IB3 Batch tagging.** Every record a batch creates carries a Created By Import Batch
reference to it. This is what makes undo possible in v0.5 without journaling creations,
and it is what lets an admin answer "where did these 400 households come from" today. The
reference exists on Household and Organization (both Account record types), on Contact,
and on Gift.

**R-IB4 Idempotence per row.** Re-running the same file with the same template matches
rather than duplicates, given the same matching rule. The External ID matching rule is
the one that guarantees this for gift feeds.

**R-IB5 Failure is partial, not silent.** A row that fails does not roll back the batch.
It is recorded on its Import Row with a message an administrator can act on, counted in
Rows Rejected, and written to the Error Log where the cause was an exception (R-E1).

**R-IB6 Undo is v0.5.** Undo Deadline is written from v0.2 so that the window is known
from the first batch. The undo action itself, and the journaling of updates that undo
needs, are C-19 in v0.5.

### Salesforce implementation

- **Object:** `Import_Batch__c`, auto-number Name with format `IB-{000000}`.

| Attribute | API name | Type |
|---|---|---|
| Import Template | `Import_Template__c` | Lookup to `Import_Template__c` |
| File Reference | `File_Id__c` | Text (18) |
| File Name | `File_Name__c` | Text |
| Status | `Status__c` | Picklist: Draft, Parsing, Dry run, Dry run complete, Committing, Complete, Failed, Undone |
| Is Dry Run | `Is_Dry_Run__c` | Checkbox |
| Row Count | `Row_Count__c` | Number |
| Rows Created | `Rows_Created__c` | Number |
| Rows Updated | `Rows_Updated__c` | Number |
| Rows Matched | `Rows_Matched__c` | Number |
| Rows Rejected | `Rows_Rejected__c` | Number |
| Run Log | `Run_Log__c` | Long Text Area |
| Started At | `Started_At__c` | DateTime |
| Completed At | `Completed_At__c` | DateTime |
| Chunk Size | `Chunk_Size__c` | Number |
| Undo Deadline | `Undo_Deadline__c` | DateTime |
| Committed By | `Committed_By__c` | Lookup to User |

- **Batch tag on other objects:** `Created_By_Import_Batch__c`, a Lookup to
  `Import_Batch__c`, on Account (households and organizations), on Contact, and on
  `Gift__c`. The Account and Contact fields ship in Core with the import framework; the
  `Gift__c` field ships in Giving (Section 18).
- **Settings key:** `Import_Chunk_Size__c` (Section 12).
- **Service:** `ImportBatchService`, `ImportBatchSelector`, `ImportProcessorBatch`,
  `ImportController` (the one Aura-enabled entry point both screens call), LWC
  `importWizard`, `importResults`.

---

## 17. Import Row

### Definition

One row of the uploaded file, staged so that it can be previewed, explained, corrected,
and reprocessed (plan Section 4.9). A row is not one record: it can describe a household,
up to two people, an organization, a gift with allocations, and a soft credit, and the
processor resolves those in dependency order.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Import Batch | reference(Import Batch) | yes | The upload this row came from. |
| Row Number | integer | yes | The row's position in the file, so a message can name it. |
| Raw Values | long text | yes | The row's original column values exactly as uploaded, held as a document keyed by column name. |
| Status | picklist(Pending, Matched, Created, Updated, Rejected, Skipped) | yes | What the processor did with this row, or would do in a dry run. |
| Error Message | long text | no | Why the row was rejected, in language an administrator can act on. |
| Household | reference(Household) | computed | The household this row resolved to. |
| Contact 1 | reference(Contact) | computed | The first person, where people are Contacts. |
| Person 1 Account | reference(Organization) | computed | The first person, where people are person Accounts. |
| Contact 2 | reference(Contact) | computed | The second person, where people are Contacts. |
| Person 2 Account | reference(Organization) | computed | The second person, where people are person Accounts. |
| Organization | reference(Organization) | computed | The organization this row resolved to. |
| Gift | text | computed | The gift this row resolved to, held as a record identifier (R-IR2). |
| Soft Credit | text | computed | The soft credit this row resolved to, held as a record identifier (R-IR2). |

### Relationships

- **Import Row to Import Batch**, many to one, and rows are deleted with their batch.
- Import Row to the records it resolved: to Core records by reference, to Giving records
  by identifier (R-IR2).

### Rules

**R-IR1 Row entities and resolution order.** A row is read as up to eight entities named
`Household`, `Contact1`, `Contact2`, `Organization`, `Affiliation`, `Gift`, `Allocation`,
and `SoftCredit` in the template's mapping document, and they are resolved in dependency
order: organization, household, people, membership and affiliation, gift, allocations,
soft credit. Resolution is idempotent per row (R-IB4).

**R-IR2 Giving links are identifiers, not references.** Gift and Soft Credit are stored
as record identifiers rather than lookups. Import Row lives in Core and `Gift__c` and
`Soft_Credit__c` live in Giving, and a base package cannot hold a reference to an object
in a package that depends on it. The Giving package reads and writes these two attributes
by identifier. The cost is that the two links are not clickable in the standard record UI
and cannot be reported on through a relationship; the results screen resolves and links
them, and ADR-0014 records the deviation from the literal field list in plan Section 4.9.

**R-IR3 Person references.** A row resolves its people to Contacts or to person Accounts
according to the template's Person Mode, never to both (Section 4 "Person references").

**R-IR4 Raw values are never rewritten.** Raw Values holds what was uploaded. A
correction is made by fixing the file and re-running, not by editing the staged row, so
the batch remains an accurate record of what was loaded.

**R-IR5 Retention.** Rows are kept for the undo window and are deletable in bulk from the
batch record, so a large import does not sit in storage forever.

**R-IR6 Entities Core cannot resolve.** Core resolves `Organization`, `Household`,
`Contact1` and `Contact2`. `Affiliation`, `Gift`, `Allocation` and `SoftCredit` belong to
features or packages Core may not reference (ADR-0014), so the processor offers them to an
optional `ImportEntityProcessor` implementation found by `Type.forName` (the mechanism in
ADR-0017), and where none is installed it leaves those columns staged on the row, says so
in the run log, and counts the row on what it did resolve. A row is never rejected for
carrying a column nothing can load yet.

### Salesforce implementation

- **Object:** `Import_Row__c`, auto-number Name with format `IR-{000000}`.

| Attribute | API name | Type |
|---|---|---|
| Import Batch | `Import_Batch__c` | Master-Detail to `Import_Batch__c` |
| Row Number | `Row_Number__c` | Number |
| Raw Values | `Raw_Values_JSON__c` | Long Text Area |
| Status | `Status__c` | Picklist: Pending, Matched, Created, Updated, Rejected, Skipped |
| Error Message | `Error_Message__c` | Long Text Area |
| Household | `Household__c` | Lookup to Account |
| Contact 1 | `Contact_1__c` | Lookup to Contact |
| Person 1 Account | `Person_1_Account__c` | Lookup to Account |
| Contact 2 | `Contact_2__c` | Lookup to Contact |
| Person 2 Account | `Person_2_Account__c` | Lookup to Account |
| Organization | `Organization__c` | Lookup to Account |
| Gift | `Gift_Id__c` | Text (18) |
| Soft Credit | `Soft_Credit_Id__c` | Text (18) |

- **Service:** `ImportRowProcessor`, `ImportMatcher`, `ImportRowSelector`,
  `ImportEntityProcessor` (the interface a dependent package implements to resolve the row
  entities Core cannot, R-IR6).

---

# Part D: Giving entities

These entities are built by the Giving package. Sections 18 to 21 are v0.2 (features
G-01 to G-06); Sections 22 to 25 are v0.3 (features G-07 to G-11). Section 21A is the
Giving package's own settings object, which ADR-0017 introduced. Section 26 lists the
rollup definitions the Giving package ships and the target attributes they write.

Giving depends on Core, so Giving may hold references to Core objects and Core may not
hold references to Giving objects (ADR-0014). `Gift__c` is the gift system of record and
no entity here references Opportunity, Campaign, Lead, Case, or any Industries object
(ADR-0004).

## 18. Gift

### Definition

One received transaction: money, stock, or goods that arrived, from one donor, on one
date (plan Section 4.11). A gift is a fact about something that happened, which is why a
refund is another gift rather than an edit (ADR-0010).

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The gift's identifier, assigned automatically. |
| Donor Contact | reference(Contact) | conditional | The person credited with the gift, where people are Contacts. |
| Donor Account | reference(Organization) | conditional | The account credited with the gift: an organization, a household giving in its own name, or a person Account. |
| Household | reference(Household) | computed | The household credited with the gift, derived from the donor (R-G2). |
| Gift Date | date | yes | The date the gift was received, which is the date that appears on the receipt. |
| Amount | decimal | yes | The money received, negative for a refund or a write-off, and zero on an in-kind gift, which is goods rather than money (R-G12). |
| Type | picklist(Cash, Check, Card, ACH, Stock, In-kind, Grant, Other) | yes | How the gift arrived. |
| Status | picklist(Received, Pending, Refunded, Written off) | yes | Where the gift stands; only Received gifts count in the packaged giving totals. |
| Appeal | reference(Appeal) | no | The fundraising effort this gift responded to. |
| Acknowledgment Status | picklist(Not required, To acknowledge, Acknowledged, Do not acknowledge) | yes (defaults To acknowledge) | Whether this gift still needs a thank you. |
| Acknowledgment Date | date | no | The date the thank you was sent. |
| Receipt Number | text | no | The number of the receipt issued for this gift, unique across the org and never reused. |
| Tribute | reference(Tribute) | no | The honor or memorial this gift was given under (v0.3, R-G8). |
| Matched Gift | reference(Gift) | no | The employer's matching gift that this gift produced, or the employee gift that this gift matches (v0.3, G-10). |
| Commitment | reference(Commitment) | no | The pledge or recurring commitment this gift pays toward (v0.3). |
| Installment | reference(Installment) | no | The scheduled installment this gift fulfills (v0.3). |
| External Id | text | no | The identifier this gift carries in the system it came from, unique, used to make imports and the inbound API idempotent. |
| Payment Reference | text | no | The processor's transaction reference, check number, or deposit reference, for reconciliation against the bank. |
| Original Gift | reference(Gift) | conditional | The gift this one refunds or writes off; required when Amount is negative (R-G3). |
| Refund Reason | text | no | Why the money went back or the gift was written off, typed by the person recording it and carried on the negative gift (R-G3). |
| In-kind Description | long text | conditional | What was given, when the gift is goods or services rather than money. Required on an in-kind gift and empty on every other gift, and it is the text the receipt prints (v0.4, G-18, R-G12). |
| Fair Market Value | decimal | no | What the goods were worth, recorded for the organization's own reporting and never printed on a receipt (v0.4, G-18, R-G12, ADR-0030). |
| Benefit Description | long text | no | What the donor received in return for the gift, described as it must be printed on the receipt (v0.4, G-13, R-RC7). |
| Benefit Value | decimal | no | The organization's good faith estimate of what the benefit was worth, which the receipt subtracts to state the deductible amount (v0.4, G-13, R-RC7). |
| Intangible Religious Benefits | boolean | yes (defaults false) | Whether the only thing the donor received in return was an intangible religious benefit, which is a sentence the receipt must carry instead of a value (v0.4, G-13, R-RC7). |
| Created By Import Batch | reference(Import Batch) | no | The import that created this gift, so it can be found and, from v0.5, undone. |

### Relationships

- **Gift to Donor**, many to one, to exactly one of Donor Contact or Donor Account
  (R-G1 and Section 4 "Person references").
- **Gift to Household**, many to one, derived rather than entered (R-G2).
- **Gift to Gift Allocation**, one to many; the allocations are deleted with the gift.
- **Gift to Fund**, indirectly, through its allocations only. A gift has no fund
  reference of its own, because a gift can be split.
- **Gift to Appeal, Commitment, Installment, Tribute, Matched Gift, Original Gift**, many
  to one in each case.
- Gift is the source of almost every rollup in Section 26.

### Rules

**R-G1 Exactly one donor.** A gift has a Donor Contact or a Donor Account, never both and
never neither. Donor Account carries an organization, a household giving in its own name,
or a person Account, and the three are told apart by record type and by the dynamic
person-account test in Section 4, never by a static field reference.

**R-G2 Household is derived.** Household is written by the package, not by the user: from
the donor contact's household through `HouseholdService`, from the person Account's
household the same way in junction mode, from the Donor Account itself when that account
is a household, and left empty when the donor is an organization. It is recomputed when
the donor changes and when the donor's household membership changes, which is what keeps
household totals correct after a merge, split, or reparent (R-H12, R-H13).

**R-G3 Refunds and write-offs.** A refund or a write-off is a new gift with a negative
Amount and Original Gift set, never an edit and never a deletion (ADR-0010). The package
sets the original gift's Status to Refunded or Written off when the linked negative gift
is saved. The negative gift's own Status is Received, because it is a transaction that
happened, and it carries the same type and date semantics as any other gift. The reason the
money went back is typed once, on the negative gift, in Refund Reason: the original gift is
not edited to hold it, because editing the original is the thing this rule exists to
prevent. A partial refund leaves the original at Received, because part of it is still a
gift the organization holds.

**R-G4 Amount immutability.** Once a Receipt Number is present, Amount, Gift Date, the
donor references, and the In-kind Description do not change, and the gift is not deleted.
Receipt Number itself is written only by the receipting feature, from the sequence in
Section 25C: it is read only in every packaged permission set, a gift is never created
carrying one, and a save that sets, changes or clears it is refused unless the receipting
code is renumbering that gift (ADR-0033). A number typed in by hand belongs to no receipt,
locks the gift, can be issued again later by the sequence as a year end statement, and
leaves the gift permanently unreceiptable, so the first write is refused for the same
reason later ones are.
The in-kind description is in that list because it is printed on the document the donor
holds; Fair Market Value is not, because it never is (R-G12, ADR-0030). A correction voids the
receipt and reissues (ADR-0010). This is enforced in the domain layer from v0.2, before
the receipting feature exists in v0.4, so no early data escapes the rule. The enforcement
runs from its own automation, `Gift_Receipt_Lock`, which is marked Always Runs (R-A4), so
switching an automation off or pausing all automation does not lift the lock. The one way
past it is the `Override_Receipt_Lock` custom permission, which ships on no permission set
and in no permission set group: an administrator assigns it in Setup, makes the change, and
removes it again. Every change made under the override writes an Error Log entry at Warning
severity naming the gift, its receipt number, and what changed (ADR-0024).

**R-G5 Allocation totals.** Every gift's allocations total its Amount (R-GA1). A gift
saved with no allocation gets one allocation for the whole amount to the org's default
fund.

**R-G6 Automatic naming.** Name is assigned by the platform in the format `G-000001`.
Staff never type a gift name, and the number is not a receipt number.

**R-G7 Idempotent intake.** External Id is unique. The importer and the inbound API in
Connect both match on it, so re-sending a gift updates rather than duplicates.

**R-G8 Tribute link.** The authoritative link between a gift and a tribute is the
Tribute's own Gift reference (Section 25). The Gift's Tribute reference is a mirror the
package maintains, kept because gift list views, gift reports, and the receipt merge need
the tribute without a subquery.

**R-G9 Fields present before their feature.** Acknowledgment Status, Acknowledgment Date,
Receipt Number, In-kind Description, and Fair Market Value are defined in v0.2 and used
by v0.4 features (G-12, G-13, G-18). They ship in v0.2 so that `Gift__c` is not altered
later, which matters because altering a packaged object's field set after orgs hold data
is the change that upgrades handle worst.

**R-G10 No standard-object reference.** Nothing on this entity points at Opportunity or
Campaign. The mirrors live in Connect (ADR-0004).

**R-G11 Matching gift linkage (G-10).** An employer's matching gift is linked to the
employee's gift through Matched Gift, which both records carry, so the link is visible
from either side. The link is accepted only when the employer's gift has an Account donor
whose record type is Organization and the employee's gift has a person donor, and, where
the employee's Employer is set, only when it names that same organization. Linking creates
one automatic soft credit on the employer's gift, crediting the employee with Role Matched
Donor and the employer gift's amount; unlinking clears both references and removes that
credit, together with the negative credits described below. A gift matches at most one
other gift. Neither gift may have been refunded or written off at the moment the link is
made: a link that outlived the money would go on crediting the employee for a match the
organization gave back.

A refund of a linked employer gift reverses that credit rather than removing it, the way
every other automatic credit reverses (R-SC5, ADR-0031). The negative gift recording the
refund or the write-off carries a negative Matched Donor credit for the same person,
prorated to the amount returned, so an employer gift of 500 with 200 returned leaves the
employee recognized for 300 and one fully returned leaves them recognized for nothing. A
refund of the *employee's* gift does not touch the credit: the employer's money is still
money the organization holds. The link itself survives a refund and is not cleared
automatically, because it is the record of what the money was.

**R-G12 In-kind gifts carry no amount (G-18, ADR-0030).** A gift of goods or services is a
Gift with Type In-kind. Its Amount is zero, because an in-kind gift is not money the
organization holds and no money rollup, report or dashboard may treat it as though it were,
and its worth is carried on Fair Market Value instead. An in-kind gift must carry an In-kind
Description, which is what the receipt prints; a gift that is not in-kind carries neither the
description nor the fair market value, so a type changed in error cannot leave a value behind
that later reads as an in-kind gift. Fair Market Value is never negative and never appears on
a rendered receipt or statement (R-RC7, ADR-0016): the donor substantiates what donated
property was worth, the organization describes what it received. In-kind giving is reported on
its own two rollups in Section 26, In-kind Value and In-kind Gift Count, so a donor of goods
has a total and a count without either one entering Total Giving, a donor level (ADR-0028) or
a retention report (ADR-0026). Because Amount is zero and never changes, a mistaken in-kind
gift is corrected by writing it off or by correcting the description, not by a negative gift:
R-G3 has nothing to reverse.

### Salesforce implementation

- **Object:** `Gift__c`, auto-number Name with format `G-{000000}`, private
  organization-wide default recommended (plan Section 4.13).

| Attribute | API name | Type |
|---|---|---|
| Donor Contact | `Donor_Contact__c` | Lookup to Contact |
| Donor Account | `Donor_Account__c` | Lookup to Account |
| Household | `Household__c` | Lookup to Account |
| Gift Date | `Gift_Date__c` | Date |
| Amount | `Amount__c` | Currency |
| Type | `Type__c` | Picklist: Cash, Check, Card, ACH, Stock, In-kind, Grant, Other |
| Status | `Status__c` | Picklist: Received, Pending, Refunded, Written off |
| Appeal | `Appeal__c` | Lookup to `Appeal__c` |
| Acknowledgment Status | `Acknowledgment_Status__c` | Picklist: Not required, To acknowledge, Acknowledged, Do not acknowledge |
| Acknowledgment Date | `Acknowledgment_Date__c` | Date |
| Receipt Number | `Receipt_Number__c` | Text, External Id, unique, package written (R-G4) |
| Tribute | `Tribute__c` | Lookup to `Tribute__c` (v0.3) |
| Matched Gift | `Matched_Gift__c` | Lookup to `Gift__c` (v0.3) |
| Commitment | `Commitment__c` | Lookup to `Commitment__c` (v0.3) |
| Installment | `Installment__c` | Lookup to `Installment__c` (v0.3) |
| External Id | `External_Id__c` | Text, External Id, unique |
| Payment Reference | `Payment_Reference__c` | Text |
| Original Gift | `Original_Gift__c` | Lookup to `Gift__c` |
| Refund Reason | `Refund_Reason__c` | Text |
| In-kind Description | `In_Kind_Description__c` | Long Text Area (v0.4) |
| Fair Market Value | `Fair_Market_Value__c` | Currency (v0.4) |
| Benefit Description | `Benefit_Description__c` | Long Text Area (v0.4) |
| Benefit Value | `Benefit_Value__c` | Currency (v0.4) |
| Intangible Religious Benefits | `Intangible_Religious_Benefits__c` | Checkbox (v0.4) |
| Created By Import Batch | `Created_By_Import_Batch__c` | Lookup to `Import_Batch__c` |
| Sample Data | `Sample_Data__c` | Checkbox (v0.4) |

- **Service:** `GiftService`, `GiftDomain`, `GiftSelector`, LWC `quickGiftEntry` (G-03).
- **Receipt lock:** handler `GiftReceiptLockHandler`, registry record
  `Automation_Registry.Gift_Receipt_Lock` (execution order 5, Always Runs), custom
  permission `Override_Receipt_Lock` (granted to nobody by the package).

---

## 19. Gift Allocation

### Definition

The part of a gift that belongs to one fund (plan Section 4.11). A gift that is entirely
unrestricted still has one allocation, so that fund totals are answered by one query and
never by two different rules.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The allocation's identifier, assigned automatically. |
| Gift | reference(Gift) | yes | The gift being split. |
| Fund | reference(Fund) | yes | The fund this part of the gift is designated to. |
| Amount | decimal | yes | The amount designated to this fund. |
| Percent | decimal | computed | This allocation's share of the gift, shown so staff can enter and check a split either way. |

### Relationships

- **Gift Allocation to Gift**, many to one, and allocations are deleted with their gift.
- **Gift Allocation to Fund**, many to one.

### Rules

**R-GA1 Allocations total the gift.** The allocations of a gift total its Amount exactly.
A save that would leave a gift over-allocated or under-allocated is rejected with a
message naming the difference. Percent is maintained from Amount, and an admin entering
percentages has them converted to amounts on save, with the rounding difference added to
the largest allocation so the total is exact.

**R-GA2 Default allocation.** A gift saved with no allocation receives one allocation for
its whole amount to the org's default fund (Section 12). This is what makes fund
reporting complete without asking staff to think about designation on every gift.

**R-GA3 Negative gifts allocate negatively.** A refund's allocations mirror the original
gift's allocations with negative amounts, so fund totals correct themselves.

**R-GA4 Appeal and donor defaults.** Where an appeal names a default fund, a gift entered
against that appeal is allocated to it unless staff choose otherwise. This is a proposal
in the entry form, never a rule that rewrites a saved allocation.

### Salesforce implementation

- **Object:** `Gift_Allocation__c`, auto-number Name with format `GA-{000000}`.

| Attribute | API name | Type |
|---|---|---|
| Gift | `Gift__c` | Master-Detail to `Gift__c` |
| Fund | `Fund__c` | Lookup to `Fund__c` |
| Amount | `Amount__c` | Currency |
| Percent | `Percent__c` | Percent |

- **Service:** `AllocationService`, `AllocationDomain`.

---

## 20. Fund

### Definition

A designation or restriction on how money may be used: the general fund, a building
fund, a scholarship fund, a restricted grant (plan Section 13). NPSP calls this a General
Accounting Unit and Nonprofit Cloud calls it a Gift Designation; the label the admin sees
is Fund (plan Section 7.1).

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | yes | The fund's name as staff and the board know it, for example "Annual Fund". |
| Description | long text | no | What this fund pays for and any restriction attached to it. |
| Active | boolean | yes (defaults true) | Whether the fund is offered when allocating a new gift. |
| Restricted | boolean | yes (defaults false) | Whether a donor or funder limited this money to a purpose, which makes its balance a compliance obligation. |
| Accounting Code | text | no | The code this fund carries in the organization's accounting system, used by the export in Connect. |
| Is Default | boolean | yes (defaults false) | Marks the fund that receives a gift with no explicit allocation. |

### Relationships

- **Fund to Gift Allocation**, one to many. A fund reaches gifts only through
  allocations.
- Fund is a rollup target (Section 26).

### Rules

**R-F1 One default fund.** At most one fund has Is Default true. Setting it on a second
fund clears the first, and the Setup Assistant's "pick default fund" step writes the
org's default fund key from this flag.

**R-F2 Deactivation, not deletion.** A fund that has received gifts is deactivated rather
than deleted, so historical allocations keep their meaning. Deletion is blocked while
allocations exist.

**R-F3 Accounting code uniqueness.** Accounting Code, where used, is unique, because the
accounting export keys on it.

**R-F4 The default fund key holds an identifier.** The org's default fund is held in the
Core settings key `Default_Fund__c` as a record identifier rather than a reference,
because Core cannot hold a lookup to a Giving object (ADR-0014). The Giving package
resolves it and the settings console presents a fund picker, so the admin never sees an
identifier.

### Salesforce implementation

- **Object:** `Fund__c`.

| Attribute | API name | Type |
|---|---|---|
| Name | `Name` | Text (standard) |
| Description | `Description__c` | Long Text Area |
| Active | `Active__c` | Checkbox |
| Restricted | `Restricted__c` | Checkbox |
| Accounting Code | `Accounting_Code__c` | Text, unique |
| Is Default | `Is_Default__c` | Checkbox |
| Sample Data | `Sample_Data__c` | Checkbox (v0.4) |

Rollup target attributes on `Fund__c` are listed in Section 26.

- **Service:** `FundService`.

---

## 21. Appeal

### Definition

A fundraising effort: a year-end mailing, a gala, a spring appeal, a giving day (plan
Section 13). The word campaign is avoided in the interface because Salesforce's Campaign
object means something specific and is unavailable on Platform licenses.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | yes | The appeal's name as staff know it, for example "Year-end mailing 2026". |
| Description | long text | no | What this appeal was, who it went to, and what it asked for. |
| Goal | decimal | no | The amount this appeal set out to raise. |
| Cost | decimal | no | What the appeal cost to run, so net return can be shown. |
| Start Date | date | no | The date the appeal went out or opened. |
| End Date | date | no | The date the appeal closed. |
| Parent Appeal | reference(Appeal) | no | The larger effort this appeal is part of, for example a gala within a capital campaign. |
| Active | boolean | yes (defaults true) | Whether the appeal is offered when entering a new gift. |
| Net Raised | decimal | computed | Total raised less cost, calculated live from the two values. |
| Percent To Goal | decimal | computed | Total raised as a share of goal, calculated live, empty when no goal is set. |

### Relationships

- **Gift to Appeal**, many to one. Response rollups are not attributes an admin fills in;
  they arrive as Rollup Definitions (Section 26).
- **Appeal to Parent Appeal**, many to one, forming a shallow hierarchy.
- **Commitment to Appeal**, many to one, from v0.3.

### Rules

**R-AP1 Response numbers come from rollups.** Total raised, gift count, and the
fiscal-year windows on an appeal are packaged Rollup Definitions, not fields staff or
automation write by hand. This is the same engine every other total uses, so the numbers
cannot drift apart (plan Section 4.10).

**R-AP2 Hierarchy without recursion.** Parent Appeal may not form a cycle, and a parent's
packaged totals count gifts given directly to the parent only. Totals across a hierarchy
come from a grouped report, because a recursive rollup is a materially harder engine and
nothing in the plan requires one.

**R-AP3 Net and percent are calculated live.** Net Raised and Percent To Goal are derived
from Total Raised, Cost, and Goal at read time, so they carry no staleness and need no
recalculation.

**R-AP4 No Campaign reference.** An optional link to a standard Campaign exists only in
Connect (plan Section 4.12).

### Salesforce implementation

- **Object:** `Appeal__c`.

| Attribute | API name | Type |
|---|---|---|
| Name | `Name` | Text (standard) |
| Description | `Description__c` | Long Text Area |
| Goal | `Goal__c` | Currency |
| Cost | `Cost__c` | Currency |
| Start Date | `Start_Date__c` | Date |
| End Date | `End_Date__c` | Date |
| Parent Appeal | `Parent_Appeal__c` | Lookup to `Appeal__c` |
| Active | `Active__c` | Checkbox |
| Net Raised | `Net_Raised__c` | Formula (Currency) |
| Percent To Goal | `Percent_To_Goal__c` | Formula (Percent) |
| Sample Data | `Sample_Data__c` | Checkbox (v0.4) |

Rollup target attributes on `Appeal__c` are listed in Section 26.

- **Service:** `AppealService`.

---

## 21A. Giving Settings

### Definition

The Giving module's own org-wide toggles and values. ADR-0017 gives every module package
its own protected hierarchy custom setting, because a dependent package cannot add fields
to the Core settings object and Core must not carry fields for modules that are not
installed (Principle 3).

Core keeps the settings that Core itself reads, including `Default_Fund__c` and
`Default_Appeal__c`, which the Setup Assistant writes as record identifiers (R-F4,
ADR-0014). Everything that only the Giving package reads lives here.

### v0.3 keys

Moved here from Section 12 by ADR-0017, with their definitions unchanged.

| Key | Type | Default | Definition |
|---|---|---|---|
| `Automatic_Household_Soft_Credits__c` | boolean | true | Whether a gift from one household member automatically soft credits the household's other current members (R-SC3). |
| `Installment_Generation_Horizon_Months__c` | integer | 12 | How far ahead installments are generated for an open-ended recurring commitment, so the schedule does not generate rows forever (R-CM2). |
| `Installment_Overdue_Grace_Days__c` | integer | 5 | How many days after its due date an unpaid installment waits before it is marked Overdue (R-IN2). |

### v0.4 keys

| Key | Type | Default | Definition |
|---|---|---|---|
| `Donor_Levels_Enabled__c` | boolean | false | Whether donor levels are assigned at all. Off until the organization has built its ladder, because a wrong ladder is worse than none (R-DL7). |
| `Donor_Level_Source_Field__c` | text | `Total_Giving__c` | Which giving total the ladder is measured on, named as one of the packaged rollup attributes of Section 26 (R-DL1). Stored as text under ADR-0019. |
| `Donor_Levels_Last_Recalculated__c` | datetime | empty | When the nightly or on demand level pass last completed, shown read only on the Donor Levels page, the same freshness promise the rollups make (Principle 2). |

Added by acknowledgments (G-12, ADR-0032).

| Key | Type | Default | Definition |
|---|---|---|---|
| `Acknowledgments_Enabled__c` | boolean | false | Whether gifts are placed in the acknowledgment queue as they are saved. Off until the organization has written its rules, because a thank you that goes out with the wrong wording cannot be recalled (R-AK5). |
| `Acknowledgment_From_Address__c` | text | empty | The organization wide email address acknowledgments are sent from, named by its address. Empty means they are sent from the user who ran the send, which is what a small organization usually wants. |
| `Acknowledgments_Last_Run__c` | datetime | empty | When the last acknowledgment send finished, shown read only on the Acknowledgments page (R-AK12). |
| `Acknowledgments_Last_Run_Summary__c` | text | empty | What that run did, in one sentence, because a bare timestamp says the job woke up and not that it sent anything (R-AK12). |
Added by receipting (G-13). The organization's identity keys that a receipt prints, the
legal name, the tax identification number, the address, the logo, the signature, and the
signer's name and title, are Core keys and stay on `Nonprofit_Settings__c` (Section 12):
the Setup Assistant writes them and letters other than receipts print them too.

| Key | Type | Default | Definition |
|---|---|---|---|
| `Receipt_Number_Prefix__c` | text | R | The prefix printed before the year and the counter in a receipt number (R-RS2). |
| `Receipt_Next_Counter__c` | integer | 1 | The counter a new numbering series starts at, so an organization moving from another system continues its own sequence. |
| `Receipt_Statement_Year__c` | integer | empty | The tax year the year end run reports on, which an administrator sets in January and leaves alone. |
| `Receipt_Place_Of_Issue__c` | text | empty | The city and region the receipt is issued from, printed on the document. |
| `Receipt_Renderer__c` | text | empty | Which renderer produces the PDF, as one of the two keys ADR-0016 names (`Blob PDF`, `Visualforce`) and never a class name; empty means the shipped one. A key outside that list is refused before any class is resolved or constructed. Stored as text and validated in Apex per ADR-0019. It exists because ADR-0016 names a fallback implementation and the spike that would settle the question needs an org (ADR-0016, "Consequences"). |

### Rules

**R-GS1 Same contract as Core settings.** Protected, hierarchical, written synchronously
from the settings console and never from Setup, audited as a Setting Change, and extended
only by adding a row to the table above in the pull request that adds the field (R-N1 to
R-N5 apply unchanged).

**R-GS2 One console, several settings objects.** The Giving keys appear in the same
Nonprofit Settings console as the Core keys, in the Giving section. The console reaches
them because each shipped `Setting_Definition__mdt` row names its settings object, so an
administrator never learns that there is more than one place the values are stored.

**R-GS3 Absent module, absent setting.** An org without the Giving package has none of
these keys, which is what makes a module that is off leave nothing behind.

### Salesforce implementation

- **Custom setting:** `Giving_Settings__c`, hierarchy, protected.

| Attribute | API name | Type |
|---|---|---|
| Automatic Household Soft Credits | `Automatic_Household_Soft_Credits__c` | Checkbox |
| Installment Generation Horizon Months | `Installment_Generation_Horizon_Months__c` | Number(18, 0) |
| Installment Overdue Grace Days | `Installment_Overdue_Grace_Days__c` | Number(18, 0) |
| Auto Apply Gifts To Installments | `Auto_Apply_Gifts_To_Installments__c` | Checkbox |
| Installment Top Up Last Run | `Installment_Top_Up_Last_Run__c` | Date/Time |
| Receipt Number Prefix | `Receipt_Number_Prefix__c` | Text(10) |
| Receipt Next Counter | `Receipt_Next_Counter__c` | Number(18, 0) |
| Receipt Statement Year | `Receipt_Statement_Year__c` | Number(4, 0) |
| Receipt Place Of Issue | `Receipt_Place_Of_Issue__c` | Text(80) |
| Receipt Renderer | `Receipt_Renderer__c` | Text(60) |
| Acknowledgments Enabled | `Acknowledgments_Enabled__c` | Checkbox |
| Acknowledgment From Address | `Acknowledgment_From_Address__c` | Text(255) |
| Acknowledgments Last Run | `Acknowledgments_Last_Run__c` | Date/Time |
| Acknowledgments Last Run Summary | `Acknowledgments_Last_Run_Summary__c` | Text(255) |

- **Service:** Core `SettingsService`, reading and writing this object through the
  `Settings_Object__c` field on `Setting_Definition__mdt` (ADR-0017).

---

## 22. Commitment

### Definition

A promise to give: a pledge with a fixed total paid in installments, or a recurring gift
with an open-ended schedule (plan Section 13, feature G-07, v0.3). One entity covers both
because the difference between them is a type and an end condition, not a different shape
of data.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The commitment's identifier, assigned automatically. |
| Type | picklist(Pledge, Recurring) | yes | Pledge is a fixed total paid over time; Recurring is an open-ended schedule. |
| Donor Contact | reference(Contact) | conditional | The person who made the commitment, where people are Contacts. |
| Donor Account | reference(Organization) | conditional | The account that made the commitment: an organization, a household, or a person Account. |
| Household | reference(Household) | computed | The household credited with the commitment, derived exactly as a gift's is (R-G2). |
| Amount | decimal | yes | The amount expected in each installment. |
| Frequency | picklist(Weekly, Every two weeks, Monthly, Quarterly, Twice a year, Yearly) | yes | How often an installment falls due. |
| Day of Month | integer | no | The day an installment falls due for monthly and less frequent schedules; a day past the end of a short month falls on that month's last day. |
| Start Date | date | yes | The date the first installment falls due. |
| End Date | date | conditional | The date the schedule ends; required for a pledge, empty for an open-ended recurring gift. |
| Status | picklist(Active, Paused, Completed, Cancelled) | yes (defaults Active) | Where the commitment stands. |
| Expected Total | decimal | conditional | The total promised; required for a pledge, empty for an open-ended recurring gift. |
| Installments Planned | integer | conditional | How many installments the pledge is paid in; required for a pledge. |
| Fund | reference(Fund) | no | The fund the gifts paying this commitment are allocated to by default. |
| Appeal | reference(Appeal) | no | The fundraising effort this commitment came from. |
| Paid To Date | decimal | computed | The total of gifts received against this commitment (Section 26). |
| Balance | decimal | computed | Expected Total less Paid To Date, calculated live (R-CM5). |

### Relationships

- **Commitment to Donor**, many to one, to exactly one of Donor Contact or Donor Account
  (Section 4 "Person references").
- **Commitment to Installment**, one to many; installments are deleted with the
  commitment.
- **Gift to Commitment**, many to one, directly and through the installment a gift pays.
- **Commitment to Fund and Appeal**, many to one.

### Rules

**R-CM1 Exactly one donor.** As R-G1, and the household is derived the same way.

**R-CM2 Installment generation.** The package generates installments from Start Date,
Frequency, Day of Month, and either Installments Planned (a pledge) or the org's
generation horizon (a recurring gift, so an open-ended schedule does not generate rows
forever). Generation is idempotent: regenerating never duplicates an installment and
never deletes one that has a gift against it.

**R-CM3 Pause and cancel.** Pausing stops generation and leaves existing installments in
place. Cancelling stops generation and marks unpaid future installments Skipped. Neither
deletes history.

**R-CM4 Completion.** A pledge is Completed when its balance reaches zero or below. A
recurring commitment is never completed automatically; it ends when staff cancel it or
when End Date passes.

**R-CM5 Balance is calculated live.** Balance is Expected Total less Paid To Date for a
pledge and empty for a recurring commitment, which has no expected total to subtract
from. It is derived at read time rather than stored, because a difference of two numbers on the same record
cannot be stale and needs no recalculation pass. The household-level pledge balance
aggregates this value (Section 26). If the aggregation engine chosen in ADR-0011 cannot
aggregate a calculated attribute, Balance becomes a stored attribute written by the
commitment domain in the same transaction as Paid To Date, and this rule is updated with
the reason.

**R-CM6 Amount changes are forward-looking.** Changing Amount or Frequency regenerates
future installments only. Installments that are paid or partially paid are never
rewritten, because a gift already refers to them.

### Salesforce implementation

- **Object:** `Commitment__c`, auto-number Name with format `CM-{000000}`.

| Attribute | API name | Type |
|---|---|---|
| Type | `Type__c` | Picklist: Pledge, Recurring |
| Donor Contact | `Donor_Contact__c` | Lookup to Contact |
| Donor Account | `Donor_Account__c` | Lookup to Account |
| Household | `Household__c` | Lookup to Account |
| Amount | `Amount__c` | Currency |
| Frequency | `Frequency__c` | Picklist: Weekly, Every two weeks, Monthly, Quarterly, Twice a year, Yearly |
| Day of Month | `Day_of_Month__c` | Number (0 decimals) |
| Start Date | `Start_Date__c` | Date |
| End Date | `End_Date__c` | Date |
| Status | `Status__c` | Picklist: Active, Paused, Completed, Cancelled |
| Expected Total | `Expected_Total__c` | Currency |
| Installments Planned | `Installments_Planned__c` | Number (0 decimals) |
| Fund | `Fund__c` | Lookup to `Fund__c` |
| Appeal | `Appeal__c` | Lookup to `Appeal__c` |
| Balance | `Balance__c` | Formula (Currency) |
| Sample Data | `Sample_Data__c` | Checkbox (v0.4) |

Rollup target attributes on `Commitment__c`, including Paid To Date, are listed in
Section 26.

- **Settings keys** (on `Giving_Settings__c`, Section 12):
  `Installment_Generation_Horizon_Months__c`, `Auto_Apply_Gifts_To_Installments__c`,
  `Installment_Top_Up_Last_Run__c`.
- **Service:** `CommitmentService`, `CommitmentSelector`, `CommitmentTriggerHandler`,
  `GiftCommitmentHandler`, `InstallmentTopUpSchedulable`, `InstallmentTopUpBatch`.

---

## 23. Installment

### Definition

One expected payment on a commitment: what is due, when, and what has been paid against
it (plan Section 4.11, feature G-07, v0.3). Overdue and upcoming reports are queries over
this entity, which is why it exists rather than being computed on the fly.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The installment's identifier, assigned automatically. |
| Commitment | reference(Commitment) | yes | The commitment this installment belongs to. |
| Sequence | integer | yes | The installment's position in the schedule, counting from one. |
| Due Date | date | yes | The date this installment is expected. |
| Expected Amount | decimal | yes | The amount expected on that date. |
| Status | picklist(Scheduled, Paid, Partially paid, Overdue, Skipped) | yes (defaults Scheduled) | Where this installment stands. |
| Paid Amount | decimal | computed | The total of gifts received against this installment (Section 26). |

### Relationships

- **Installment to Commitment**, many to one, and installments are deleted with their
  commitment.
- **Gift to Installment**, many to one: one installment can be paid by more than one
  gift, which is what makes partial payment representable.

### Rules

**R-IN1 Generated, not typed.** Installments are created by the package from the
commitment schedule (R-CM2). Staff may change a due date or an expected amount on a
single installment, and regeneration respects a changed row rather than overwriting it.

**R-IN2 Status is derived.** Paid when Paid Amount reaches Expected Amount, Partially
paid when it is above zero and below it, Overdue when it is below Expected Amount and the
due date is more than the org's grace period in the past, Scheduled otherwise. Skipped is
the one status only a person sets.

**R-IN3 Payment linkage.** A gift pays an installment by referencing it. The gift also
carries the commitment, so a payment that does not correspond to any scheduled
installment still counts toward the commitment. A gift that names a commitment and no
installment is linked to that commitment's earliest unpaid installment by the package
when `Auto_Apply_Gifts_To_Installments__c` is true, which is the default, because staff
entering a cheque against a pledge know the pledge and not the row number.

**R-IN4 Sequence is stable.** Sequence is assigned at generation and does not change when
an installment is skipped or paid late, so an installment can be named the same way in a
report a year later.

### Salesforce implementation

- **Object:** `Installment__c`, auto-number Name with format `IN-{000000}`.

| Attribute | API name | Type |
|---|---|---|
| Commitment | `Commitment__c` | Master-Detail to `Commitment__c` |
| Sequence | `Sequence__c` | Number (0 decimals) |
| Due Date | `Due_Date__c` | Date |
| Expected Amount | `Expected_Amount__c` | Currency |
| Status | `Status__c` | Picklist: Scheduled, Paid, Partially paid, Overdue, Skipped |

Rollup target attributes on `Installment__c`, including Paid Amount, are listed in
Section 26.

- **Settings keys** (on `Giving_Settings__c`, Section 12): `Installment_Overdue_Grace_Days__c`.
- **Service:** `InstallmentSelector`, `InstallmentTriggerHandler`, `InstallmentSchedulable`.

---

## 24. Soft Credit

### Definition

Recognition for influencing a gift without legally giving it: a spouse, a solicitor, an
honoree, an employer whose match the gift produced (plan Section 13, feature G-08, v0.3).
A soft credit never changes who is hard credited, and it is never added into a hard credit
total.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The soft credit's identifier, assigned automatically. |
| Gift | reference(Gift) | yes | The gift being credited. |
| Contact | reference(Contact) | conditional | The person credited, where people are Contacts. |
| Account | reference(Organization) | conditional | The account credited: an organization, a household, or a person Account. |
| Role | picklist(Household Member, Matched Donor, Solicitor, Honoree, Influencer, Other) | yes | Why this person or organization is credited. |
| Custom Role | text | conditional | The role in the org's own words; required when Role is Other. |
| Amount | decimal | yes | The amount credited, which defaults to the gift's amount. |
| Percent | decimal | computed | The credited amount as a share of the gift. |
| Is Automatic | boolean | yes (defaults false) | Marks a credit the package created and maintains, as opposed to one a person entered. |

### Relationships

- **Soft Credit to Gift**, many to one, and soft credits are deleted with their gift.
- **Soft Credit to the credited party**, many to one, to exactly one of Contact or Account
  (Section 4 "Person references").

### Rules

**R-SC1 Exactly one credited party.** Contact or Account, never both and never neither.

**R-SC2 Soft credits are never hard credits.** No packaged rollup adds a soft credit into
a total giving attribute. Soft credit totals are their own attributes (Section 26), and
the interface always labels them as recognition.

**R-SC3 Automatic household-member credits.** When the org's automatic household soft
credit setting is on, every current member of the donor's household other than the donor
receives a soft credit with Role Household Member, Is Automatic true, and the gift's full
amount. This holds for every gift, including a negative gift recording a refund, whose
credits are negative in the same way, and including a gift whose own status has since
become Refunded or Written off (R-SC5). These records are maintained by the package: they
are recreated when household membership changes and removed when the setting is turned
off. A credit a person entered
is never touched by that maintenance, which is what Is Automatic is for.

**R-SC4 Amounts may exceed the gift.** The soft credits on a gift may total more than the
gift, because two people can each be recognized for the whole of it. This is recognition,
not accounting, and no validation caps it.

**R-SC5 Negative gifts.** A refund produces matching negative soft credits, so recognition
totals correct themselves the same way giving totals do. That negative credit is the only
reversal recognition gets: the gift being refunded keeps the credits it earned, and the
two rows cancel. A gift of 250 refunded in full leaves a credit of 250 on the original and
a credit of minus 250 on the negative gift, and the recognition total is zero (ADR-0023).
This holds for every automatic credit, whatever its role. A household credit follows the
donor onto the negative gift; a Matched Donor credit is mirrored onto the negative gift
that reverses the employer's gift, prorated to the amount returned, so a partial refund
nets to the amount the employer still holds (R-G11, ADR-0031).

**R-SC3a How a membership change reaches the credits.** The recompute a membership change
causes is queued, not done in the saving transaction: a household's giving history has no
bound, and moving one person between households must not fail on the size of it. The most
recent 500 gifts of each affected household are recomputed, a bound set by the soft credit
rows they imply rather than by the gifts themselves; a household that has given more than
that has the rest corrected the next time each of those gifts is saved.

**R-SC6 Automatic credits are recomputed, not accumulated.** The package recomputes a
gift's automatic credits whenever its donor, its amount, or its status changes, and
removes them when the gift is deleted. A refund does not remove them: the reversal is
R-SC5's negative credit, and doing both would take a fully refunded gift's recognition to
minus its own amount rather than to zero (ADR-0023). A status change therefore still
triggers a recompute but no longer changes its outcome. Recomputation is idempotent:
running it twice over the same gift leaves the same records. Manual credits are never
read, changed, or deleted by it.

**R-SC7 A credited party is credited once per gift and role.** Two automatic credits for
the same person, the same gift, and the same role are a duplicate, and the package keeps
the first. Staff may still enter a manual credit for a person who already holds an
automatic one, because a spouse can also be the solicitor.

### Salesforce implementation

- **Object:** `Soft_Credit__c`, auto-number Name with format `SC-{000000}`.

| Attribute | API name | Type |
|---|---|---|
| Gift | `Gift__c` | Master-Detail to `Gift__c` |
| Contact | `Contact__c` | Lookup to Contact |
| Account | `Account__c` | Lookup to Account |
| Role | `Role__c` | Picklist: Household Member, Matched Donor, Solicitor, Honoree, Influencer, Other |
| Custom Role | `Custom_Role__c` | Text |
| Amount | `Amount__c` | Currency |
| Percent | `Percent__c` | Percent |
| Is Automatic | `Is_Automatic__c` | Checkbox |

- **Settings keys:** `Automatic_Household_Soft_Credits__c` (Section 12).
- **Service:** `SoftCreditService`, `SoftCreditDomain`.

---

## 25. Tribute

### Definition

The honor or memorial a gift was given under, and who should be told about it (plan
Section 13, feature G-09, v0.3). A tribute is what turns a memorial gift into a letter the
family receives.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The tribute's identifier, assigned automatically. |
| Gift | reference(Gift) | yes | The gift given in honor or in memory. |
| Type | picklist(In honor of, In memory of) | yes | Whether the person honored is living or has died, which changes the letter. |
| Honoree Name | text | conditional | The name of the person honored, as the donor gave it; required when there is no honoree record. |
| Honoree Contact | reference(Contact) | no | The person honored, where they are a Contact the org knows. |
| Honoree Account | reference(Organization) | no | The person honored, where people are person Accounts. |
| Notification Recipient Contact | reference(Contact) | no | The person to be told about the gift, where they are a Contact. |
| Notification Recipient Account | reference(Organization) | no | The person to be told about the gift, where people are person Accounts. |
| Notification Recipient Name | text | no | The name and address of the person to be told, where they are not a record in the org. |
| Notification Sent | boolean | yes (defaults false) | Whether the notification has gone out. |
| Notification Sent Date | date | no | The date the notification was sent. |
| Message | long text | no | What the donor asked to be conveyed, quoted in the notification. |

### Relationships

- **Tribute to Gift**, many to one, and a tribute is deleted with its gift.
- **Tribute to Honoree** and **Tribute to Notification Recipient**, many to one, each to
  a Contact or a person Account, never both (Section 4 "Person references").

### Rules

**R-TR1 One tribute per gift.** At most one tribute exists for a gift, enforced in the
domain layer, and the gift carries a mirror reference to it (R-G8).

**R-TR2 An honoree does not have to be a record.** Honoree Name stands alone when the
person honored is not in the database, which is the common case for memorials. At least
one of Honoree Name, Honoree Contact, or Honoree Account is present.

**R-TR3 Notification without a record.** The same is true of the notification recipient:
a name and address is enough, and creating a Contact for a bereaved family is a choice the
org makes, not a thing the package requires.

**R-TR4 Sent date follows the flag.** Notification Sent Date is written when Notification
Sent is set, and neither is cleared by automation once set.

**R-TR5 Never an amount.** A tribute never states the gift's amount, because the
notification to a family does not disclose it.

**R-TR6 A memorial is never notified to the person who died.** An In memory of tribute
whose honoree is a record marked deceased, whether that record is a Contact or an Account,
may not name that same person as the notification recipient. Notifying an honoree who is
not marked deceased is allowed, because an In honor of gift to a foundation may quite
properly tell that foundation. The message says who is named and what to do, because the usual
cause is picking the wrong name from a list.

### Salesforce implementation

- **Object:** `Tribute__c`, auto-number Name with format `TR-{000000}`.

| Attribute | API name | Type |
|---|---|---|
| Gift | `Gift__c` | Master-Detail to `Gift__c` |
| Type | `Type__c` | Picklist: In honor of, In memory of |
| Honoree Name | `Honoree_Name__c` | Text |
| Honoree Contact | `Honoree_Contact__c` | Lookup to Contact |
| Honoree Account | `Honoree_Account__c` | Lookup to Account |
| Notification Recipient Contact | `Notification_Recipient_Contact__c` | Lookup to Contact |
| Notification Recipient Account | `Notification_Recipient_Account__c` | Lookup to Account |
| Notification Recipient Name | `Notification_Recipient_Name__c` | Text |
| Notification Sent | `Notification_Sent__c` | Checkbox |
| Notification Sent Date | `Notification_Sent_Date__c` | Date |
| Message | `Message__c` | Long Text Area |

- **Service:** `TributeService`.

---

## 25A. Donor Level

### Definition

One rung of the organization's giving ladder: a name a nonprofit uses for a group of
donors ("Leadership Circle", "Sustainer"), and the amount at which a donor reaches it.
The NPSP Levels successor (plan Section 5.2, feature G-14).

A level is not a calculation. It is a label put on a number that has already been
calculated: the giving totals the packaged rollups maintain on the donor's own record
(Section 26). That is what keeps a donor's level and the total shown next to it from
disagreeing, and it is why nothing here aggregates a gift.
## 25B. Receipt

### Definition

The record of a document a donor is holding (feature G-13, v0.4, ADR-0010 and ADR-0016). A
receipt is not an internal note: in the United States it is what a donor files with a tax
return, so once it is issued its number, its amount, its date and its stored PDF are facts
about the world and none of them change. A correction is a void and a new receipt, never an
edit.

Two kinds exist. A **per gift** receipt covers one gift. A **consolidated statement** covers
every qualifying gift a donor gave in one statement year, which is what most organizations
send in January.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | yes | What the organization calls this group of donors, as it appears on the donor's record and in reports. |
| Description | long text | no | What the level means and what a donor at it is offered, in the organization's own words. |
| Minimum Amount | currency | yes | The amount at which a donor reaches this level. A donor whose amount equals it is at this level. |
| Maximum Amount | currency | no | The amount at which a donor has passed beyond this level. A donor whose amount equals it is at the next level up. Empty means this is the top of the ladder. |
| Active | boolean | yes (defaults true) | Whether the level takes part in assignment. An inactive level keeps its name on the donors already at it and receives nobody new. |

### Relationships

- **Donor Level to donor**, one to many, in two directions: the level a donor is at now,
  and the level that donor was at before (R-DL4). The donor is a Household, an
  Organization, a person Account, or a Contact (R-DL3).
- Donor Level has no reference to Gift, to Rollup Definition, or to any settings record.
  Which number the ladder is measured on is a setting (Section 21A), not a reference.

### Rules

**R-DL1 One ladder, measured on one number.** The active levels form a single ladder for
the whole organization, ordered by Minimum Amount, and every donor is placed on it by one
number: the giving total named by `Donor_Level_Source_Field__c` (Section 21A). That
setting names one of the packaged rollup attributes of Section 26, so the number a level
is measured on is a number the donor's record already shows, calculated once by the rollup
engine under the status filter of ADR-0022, and never recalculated here. A ladder measured
on a second, privately calculated number would disagree with the donor's own total on
screen, which is the defect this rule exists to prevent.

**R-DL2 Which level a donor is at.** The assigned level is the active level with the
greatest Minimum Amount that is at most the donor's amount, and whose Maximum Amount is
empty or greater than that amount. A donor whose amount is below every Minimum Amount, or
whose amount is empty, is at no level, and no level is a legitimate answer rather than an
error. Where two active levels overlap, the one with the greater Minimum Amount wins, so
a badly built ladder is still deterministic.

**R-DL3 Whose level it is.** Three kinds of record carry a level, and they are exactly the
three the giving totals of Section 26 are written to: a Household Account, an Account that
is an organization or a person, and a Contact. A household and its members can therefore
sit at different levels, which is correct: they are answers to different questions, and
each one is read from the total on that same record.

Household membership mode does not enter into it. Because the level reads a total already
written to the record, the household membership abstraction was applied when that total
was calculated (R-R1), and no membership is resolved a second time here. Contact mode and
junction mode give the same result for the same reason.

**R-DL4 Previous level, and movement.** When assignment produces a level different from
the one on the record, the level the record held moves to Previous Donor Level and Donor
Level Changed Date is set to the date of the change. When assignment produces the level
already held, nothing is written, so Donor Level Changed Date keeps saying when the donor
last moved rather than when the calculation last ran. Previous Donor Level is the record
of where the donor came from, and it is never cleared by a later assignment.

**R-DL5 A donor whose total falls.** A refund, a write-off, or a corrected gift lowers the
total the ladder reads, and the level follows it down in the same save. The level always
states the level the current number earns, because a level that disagreed with the total
printed beside it would be worse than no level at all (Principle 2). What is retained is
the previous level and the date: a donor who drops from Leadership Circle to Sustainer
reads as Sustainer, previously Leadership Circle, changed today, so the movement is
visible to the person who has to decide what to do about it. Levels are not a floor; an
organization that awards a level permanently records that on the donor, not here.

**R-DL6 When assignment runs.** The same three answers the rollup engine gives (R-R4).
Real time: assignment happens in the save that changes the source total, which includes
the save the rollup engine itself makes when a gift lands, and it runs before the record
is written so it costs no second update. Scheduled: a nightly pass re-places every donor,
which is what catches a fiscal year turning over and a ladder edited yesterday. On demand:
the Recalculate button on the Donor Levels page does the scheduled pass now. Assignment is
idempotent in all three: running it twice over unchanged data writes nothing the second
time.

**R-DL7 Off until it is set up.** `Donor_Levels_Enabled__c` defaults false and no level
records ship, because a ladder's amounts belong to the organization and a wrong one is
worse than none. While it is off, nothing is assigned and nothing is cleared: the levels
already assigned stay on the records, exactly as an inactive Rollup Definition keeps the
values it calculated (R-R6).

**R-DL8 Editing the ladder.** Changing an amount, adding a rung, or deactivating one takes
effect for a donor at their next assignment, so the console offers Recalculate and the
admin guide says to press it. Deleting a level record removes the name from every donor
holding it, current and previous, which is the platform's behavior for a lookup and cannot
be softened; deactivating a level instead keeps the history and stops new assignments,
which is why the Active attribute exists.

**R-DL9 Nothing shipped, nothing overwritten.** The package ships no Donor Level records
and never edits one. An upgrade cannot change an organization's ladder because there is
nothing packaged to conflict with it (ADR-0006).

### Salesforce implementation

- **Object:** `Donor_Level__c`, a rung of the ladder, listed and edited from the Donor
  Levels page in the settings console.

| Attribute | API name | Type |
|---|---|---|
| Name | `Name` | Text (standard) |
| Description | `Description__c` | Long Text Area |
| Minimum Amount | `Minimum_Amount__c` | Currency |
| Maximum Amount | `Maximum_Amount__c` | Currency |
| Active | `Active__c` | Checkbox |

- **Fields on Account** (shipped by Giving, on the Household, Organization, and person
  layouts):

| Attribute | API name | Type |
|---|---|---|
| Donor Level | `Donor_Level__c` | Lookup to `Donor_Level__c` |
| Previous Donor Level | `Previous_Donor_Level__c` | Lookup to `Donor_Level__c` |
| Donor Level Changed Date | `Donor_Level_Changed_Date__c` | Date |

- **Fields on Contact** (shipped by Giving): the same three API names, with the same types
  and the same definitions.

- **Settings keys:** `Donor_Levels_Enabled__c`, `Donor_Level_Source_Field__c`, and
  `Donor_Levels_Last_Recalculated__c` on `Giving_Settings__c` (Section 21A).
- **Validation rule:** Maximum Amount, when it is filled in, is greater than Minimum
  Amount.
- **Automation:** `Donor_Level_Assignment` in `Automation_Registry__mdt`, one row for
  Account and one for Contact, both naming `DonorLevelTriggerHandler`, both bypassable and
  pausable like every other packaged automation (R-A1).
- **Service:** `DonorLevelService`, `DonorLevelSelector`, `DonorLevelTriggerHandler`,
  `DonorLevelBatch`, `DonorLevelSchedulable`, `DonorLevelWriter` (ADR-0021), and
  `DonorLevelController` for the page.

---

| Name | text | computed | The receipt record's identifier, assigned automatically. It is not the receipt number. |
| Receipt Number | text | yes | The number printed on the document, allocated once by the package sequence and never reused. |
| Type | picklist(Per gift, Consolidated statement) | yes | Whether this document covers one gift or a donor's whole year. |
| Status | picklist(Issued, Void) | yes (defaults Issued) | Whether the document still stands. |
| Statement Year | integer | yes | The tax year the document reports on. |
| Gift | reference(Gift) | conditional | The gift receipted; present on a per gift receipt and empty on a consolidated statement. |
| Donor Contact | reference(Contact) | conditional | The donor, where people are Contacts. |
| Donor Account | reference(Organization) | conditional | The donor, where the donor is an organization, a household giving in its own name, or a person Account. |
| Household | reference(Household) | no | The household credited, derived from the donor the same way a gift's household is (R-G2). |
| Total Amount | decimal | yes on an issued receipt | The amount the document states: the gift's amount, or the sum of the lines on a statement. A receipt reconciled from a consumed number carries zero, because no document was produced. |
| Issue Date | date | yes on an issued receipt | The date printed on the document. A reconciled receipt carries the date it was accounted for. |
| Content Document Id | text | no | The Salesforce file identifier of the stored PDF, so the record and its document find each other without a query on the link table. |
| Void Reason | text | conditional | Why the document was voided; required when Status is Void. |
| Voided On | datetime | conditional | When the document was voided; required when Status is Void. |
| Replaces | reference(Receipt) | no | The voided receipt this one was issued to replace. |
| Replaced By | reference(Receipt) | no | The receipt issued to replace this one, written on the original when it is voided and reissued. |
| Receipt Run | reference(Receipt Run) | no | The batch run that issued this receipt, empty when a person issued it one at a time. |
| Series Key | text | yes | The numbering series this number came from: receipt type plus statement year. |
| Donor Year Key | text | no | Donor, statement year and type as one value, unique, so a retried batch chunk reissues nothing. |

### Relationships

- **Receipt to Gift**, many to one, on a per gift receipt only. Deleting a gift does not
  delete its receipt: the receipt lock refuses the delete while a receipt exists (R-G4).
- **Receipt to Donor**, many to one, to exactly one of Donor Contact or Donor Account
  (Section 4 "Person references").
- **Receipt to Receipt**, through Replaces and Replaced By, which point at each other.
- **Receipt to Receipt Run**, many to one.
- **Receipt to its stored file**, one to one, as a `ContentVersion` linked to the receipt
  and, on a per gift receipt, to the gift. It is not linked to the donor: a
  `ContentDocumentLink` grants access to a file through the record it names, and every Core
  role can read a Contact and an Account (R-RC11, ADR-0034).

### Rules

**R-RC1 Issued means immutable.** A receipt's number, type, statement year, donor, total
amount, issue date and stored file do not change after it is issued. The only writes an
issued receipt accepts are the void fields and Replaced By (ADR-0010).

**R-RC2 A number is consumed once and never reused.** Numbers come from the sequence in
Section 25C. Gaplessness is not attempted at the database level, because a rolled back
transaction cannot un-consume a number that another transaction has already moved past.

**R-RC3 Every consumed number is accounted for, by one of two mechanisms.** For the
statement series, a number whose generation failed is reconciled into a receipt with Status
Void and Void Reason `Generation failed`, and that reconciliation runs at the end of every
batch run. For the per gift series there is no reconciliation pass: the allocation and the
receipt insert share one transaction and a failure rolls both back, so a failed issue
consumes no number. Either way an auditor asking what happened to number N gets a record
rather than silence. A per gift caller that catches a generation failure and commits anyway
breaks this rule, and the Health Check finding in C-11 counts only reconciled records, so it
would not see the result (ADR-0016, "Numbering").

**R-RC4 Voiding never touches the stored file.** A void writes Void Reason and Voided On
and leaves the document exactly as the donor received it. Deleting the file is not a void.

**R-RC5 Regeneration is a void plus a new receipt.** The replacement takes the next number
from the same series and carries Replaces; the original carries Replaced By. Nothing
regenerates a receipt in place.

**R-RC6 One donor, and a gift only on a per gift receipt.** Exactly one of Donor Contact
and Donor Account is set. Gift is required on a per gift receipt and empty on a
consolidated statement.

**R-RC7 The tax content is code, not template prose.** The renderer emits, per gift: the
no goods or services sentence by default; for a quid pro quo benefit, the benefit
description, the good faith estimate of its value, and the deductible amount; and the
intangible religious benefits sentence when the gift carries that flag. An in-kind gift
prints the donor supplied description and never a value the organization asserts. An
administrator edits wording and tokens around these sentences and never the sentences
themselves (ADR-0016, IRS Publication 1771).

**R-RC8 A statement states the status of every line.** A consolidated statement prints
each gift's status on that gift's line, not once in a footer, so a reader cannot mistake
which of a year's gifts was refunded.

**R-RC9 One receipt per donor, year and type, per run.** Donor Year Key is unique, so a
batch chunk that is retried after a failure resumes the run rather than issuing a second
document to the same donor. The key is cleared when the receipt is voided, so a reissue is
possible.

**R-RC10 Read only to everyone.** No packaged permission set grants Edit or Delete on
Receipt to any role, including the administrator's, and the fields above are read only in
every packaged permission set. The package writes them; a person never does.

**R-RC11 A receipt document is reached only through Receipt and Gift.** The stored file is
linked to its receipt, and on a per gift receipt to its gift, and to nothing else. A
`ContentDocumentLink` grants access through the record it names rather than through
`Receipt__c`, so linking the donor Contact or Account would give the file to every role that
can read a donor, including roles that hold no Giving permission set. The link is written with
`ShareType` Viewer, which caps what it can grant at reading (R-RC1), and `Visibility`
InternalUsers. The donor's route to the document is the Receipts related list on their record
(ADR-0034).

### Salesforce implementation

- **Object:** `Receipt__c`, auto-number Name with format `RC-{000000}`, private
  organization-wide default recommended (plan Section 4.13).

| Attribute | API name | Type |
|---|---|---|
| Receipt Number | `Receipt_Number__c` | Text(50), External Id, unique |
| Type | `Type__c` | Picklist: Per gift, Consolidated statement |
| Status | `Status__c` | Picklist: Issued, Void |
| Statement Year | `Statement_Year__c` | Number(4, 0) |
| Gift | `Gift__c` | Lookup to `Gift__c` |
| Donor Contact | `Donor_Contact__c` | Lookup to Contact |
| Donor Account | `Donor_Account__c` | Lookup to Account |
| Household | `Household__c` | Lookup to Account |
| Total Amount | `Total_Amount__c` | Currency, not universally required, see the attribute table |
| Issue Date | `Issue_Date__c` | Date, not universally required, see the attribute table |
| Content Document Id | `Content_Document_Id__c` | Text(18) |
| Void Reason | `Void_Reason__c` | Text(255) |
| Voided On | `Voided_On__c` | Date/Time |
| Replaces | `Replaces__c` | Lookup to `Receipt__c` |
| Replaced By | `Replaced_By__c` | Lookup to `Receipt__c` |
| Receipt Run | `Receipt_Run__c` | Lookup to `Receipt_Run__c` |
| Series Key | `Series_Key__c` | Text(80) |
| Donor Year Key | `Donor_Year_Key__c` | Text(120), External Id, unique |

- **Service:** `ReceiptService`, `ReceiptSelector`, `ReceiptNumberSequence`,
  `ReceiptContentBuilder`, `ReceiptRenderer` and `BlobToPdfReceiptRenderer`,
  `ReceiptFileWriter` (ADR-0021), batch `ReceiptStatementBatch`, LWC `receiptTemplates`
  and `receiptRunConsole`.

---

## 25C. Receipt Number Sequence

### Definition

The package owned counter that hands out receipt numbers, one row per series, where a
series is a receipt type plus a statement year (ADR-0016). It is not a Salesforce
auto-number: an auto-number cannot be prefixed per organization, cannot be restarted per
year, and cannot be read back so that a consumed number can be accounted for.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | yes | The series key, so the row reads for itself in a list view. |
| Series Key | text | yes | Receipt type plus statement year, unique. |
| Receipt Type | text | yes | The receipt type this series numbers. |
| Statement Year | integer | yes | The statement year this series numbers. |
| Prefix | text | yes | The prefix printed before the year and the counter, copied from settings when the series is created. |
| First Counter | integer | yes | The counter the series started at, so the consumed range has a lower bound. |
| Next Counter | integer | yes | The next counter to hand out. |

### Relationships

- **Receipt Number Sequence to Receipt**, one to many, by Series Key rather than by a
  lookup: a receipt keeps its number after the series row is archived.

### Rules

**R-RS1 One locked row per series.** An allocation selects the series row `FOR UPDATE`,
reads Next Counter, and advances it by the size of the block requested. A batch chunk
allocates its whole block in one update rather than one number at a time. The lock is held
until the transaction ends, not until the allocation returns, so the block keeps the wait to
one per chunk rather than one per document but does not make it short (ADR-0016,
"Consequences").

**R-RS2 The number format is fixed.** `{prefix}-{statement year}-{counter zero padded to
six digits}`. Prefix and starting counter come from settings; nothing else about the format
is configurable, because a receipt number that changes shape mid-year is a number an
auditor cannot follow.

**R-RS3 Consumed is consumed.** Next Counter never moves backward, and no code path
rewrites it to fill a gap. The reconciliation in R-RC3, not the sequence, is what answers
for a missing number.

### Salesforce implementation

- **Object:** `Receipt_Number_Sequence__c`, Text Name.

| Attribute | API name | Type |
|---|---|---|
| Series Key | `Series_Key__c` | Text(80), External Id, unique |
| Receipt Type | `Receipt_Type__c` | Text(40) |
| Statement Year | `Statement_Year__c` | Number(4, 0) |
| Prefix | `Prefix__c` | Text(10) |
| First Counter | `First_Counter__c` | Number(18, 0) |
| Next Counter | `Next_Counter__c` | Number(18, 0) |

- **Service:** `ReceiptNumberSequence`, a writer class under ADR-0021.

---

## 25D. Receipt Run

### Definition

One generation run: which type, which statement year, when it started and finished, and
what it produced (ADR-0016). It exists so that a run can be watched while it is going and
reconstructed afterward, and because a year end run over tens of thousands of donors is
long enough that "did it finish" is a real question.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The run's identifier, assigned automatically. |
| Type | picklist(Per gift, Consolidated statement) | yes | What the run generates. |
| Statement Year | integer | yes | The year the run reports on. |
| Status | picklist(Queued, Running, Completed, Completed with errors, Failed) | yes | Where the run stands. |
| Started | datetime | no | When the batch began. |
| Finished | datetime | no | When the batch ended. |
| Donors Processed | integer | yes (defaults 0) | How many donor records the run examined. |
| Receipts Issued | integer | yes (defaults 0) | How many documents the run produced. |
| Errors | integer | yes (defaults 0) | How many chunks failed, each of which is also in the Error Log. |
| Async Job Id | text | no | The platform job identifier, so a stuck run can be found. |

### Relationships

- **Receipt Run to Receipt**, one to many.

### Rules

**R-RR1 A chunk failure never aborts the run.** A failed chunk is counted, written to the
Error Log with the donors it covered, and the run continues. A run that ends with any
failed chunk is Completed with errors, never Completed.

**R-RR2 A run is resumed, not restarted.** Re-running the same type and statement year
skips donors that already hold an issued receipt for that year, because Donor Year Key is
unique (R-RC9).

**R-RR3 Counts are the run's own.** Donors Processed, Receipts Issued and Errors are
written by the batch as it goes, so a run that is still going shows real progress.

### Salesforce implementation

- **Object:** `Receipt_Run__c`, auto-number Name with format `RR-{000000}`.

| Attribute | API name | Type |
|---|---|---|
| Type | `Type__c` | Picklist: Per gift, Consolidated statement |
| Statement Year | `Statement_Year__c` | Number(4, 0) |
| Status | `Status__c` | Picklist: Queued, Running, Completed, Completed with errors, Failed |
| Started | `Started__c` | Date/Time |
| Finished | `Finished__c` | Date/Time |
| Donors Processed | `Donors_Processed__c` | Number(18, 0) |
| Receipts Issued | `Receipts_Issued__c` | Number(18, 0) |
| Errors | `Errors__c` | Number(18, 0) |
| Async Job Id | `Async_Job_Id__c` | Text(18) |

- **Service:** `ReceiptRunService`, batch `ReceiptStatementBatch`.

---

## 25E. Receipt Template

### Definition

The editable wording around a receipt: the letter an administrator writes, with merge
tokens for the organization, the donor, the amounts and the dates (ADR-0006 puts structured
configuration an admin manages as a list in a packaged custom object, and ADR-0016 puts the
template bodies there).

The template is HTML restricted to what the Visualforce PDF rendering service supports: no
web fonts, no JavaScript, no `data:` URI images, and page headers and footers only through
`@page` margin boxes. The tax sentences in R-RC7 are not in the template and cannot be
edited out of it.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | yes | What the administrator calls this template. |
| Type | picklist(Per gift, Consolidated statement) | yes | Which kind of document this template lays out. |
| Body | long text | yes | The HTML with merge tokens. |
| Active | boolean | yes (defaults false) | Whether this is the template the package uses for its type. |

### Relationships

- **Receipt Template to Receipt**, none. A receipt records the document it produced, not
  the template it came from, because the stored PDF is the document of record and the
  template will have changed by the time anyone asks.

### Rules

**R-RT1 One active template per type.** Activating a template deactivates the other
templates of the same type. Generating with no active template of the required type is an
error with a readable message, not a blank document.

**R-RT2 Tokens are a closed set.** Only the tokens the package documents are merged; an
unknown token is left as typed rather than silently emptied, so a typo is visible on the
proof rather than invisible on the donor's copy.

**R-RT3 The tax sentences are appended by code.** Whatever the body says, the renderer adds
the sentences R-RC7 requires. A template that also types them produces them twice, which is
the administrator's to fix, and a template that omits them still produces a valid receipt.

**R-RT4 The shipped letters arrive at install, and writing one needs Manage Nonprofit
Settings.** `Receipt_Template_Default__mdt` is materialized by the Giving post-install script,
at install and at every upgrade, creating only what the org does not have (ADR-0029). The
Receipts page carries a Restore the shipped letters action for an install whose step failed,
and issuing a receipt with no letter of that kind materializes the shipped one under
`Issue_Receipts`. Saving a body, switching a letter on, and restoring the shipped letters all
check `Manage_Nonprofit_Settings` and write in user mode (ADR-0034).

### Salesforce implementation

- **Object:** `Receipt_Template__c`, Text Name.

| Attribute | API name | Type |
|---|---|---|
| Type | `Type__c` | Picklist: Per gift, Consolidated statement |
| Body | `Body__c` | Long Text Area (32768) |
| Active | `Active__c` | Checkbox |

- **Shipped defaults:** `Receipt_Template_Default__mdt`, with `Template_Name__c`,
  `Receipt_Type__c` and `Body__c`, one row per receipt type, materialized into
  `Receipt_Template__c` by `GivingPostInstall` (R-RT4).
- **Service:** `ReceiptTemplateService`, LWC `receiptTemplates`, reached from the Nonprofit
  Settings console as a Component row.

---

## 25F. Acknowledgment Rule

### Definition

The organization's answer to "which thank you does this gift get" (feature G-12, v0.4,
ADR-0032). A rule matches a gift on the things a fundraising office actually sorts gifts
by, and resolves to a channel and, for email, to the standard email template that carries
the wording.

A rule is not a filter on a report. It is evaluated on the save of every gift, first
matching rule wins, so the order of the rules is the organization's editorial judgment
about which thank you takes precedence.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | yes | What the organization calls this rule, for example "Major gifts, over $1,000". |
| Description | long text | no | When this rule is meant to apply, in the organization's own words. |
| Active | boolean | yes (defaults true) | Whether the rule takes part in matching. An inactive rule matches nothing and is kept rather than deleted. |
| Order | integer | yes | Where the rule sits in the list. The lowest numbered matching rule wins. |
| Channel | picklist(Email, Letter, None) | yes | How the donor is thanked, or that this kind of gift is not acknowledged. |
| Email Template | text | conditional | The developer name of the standard email template this rule sends; required when Channel is Email. |
| Minimum Amount | currency | no | The smallest gift this rule matches. Empty means no lower bound. |
| Maximum Amount | currency | no | The largest gift this rule matches. Empty means no upper bound. |
| Gift Type | picklist(Cash, Check, Card, ACH, Stock, In-kind, Grant, Other) | no | The one gift type this rule matches. Empty means any type. |
| Appeal | reference(Appeal) | no | The one appeal this rule matches. Empty means any appeal, and no appeal. |
| First Gift Only | boolean | yes (defaults false) | Whether the rule matches only a donor's first gift. |

### Relationships

- **Acknowledgment Rule to Acknowledgment**, one to many: every acknowledgment records the
  rule that produced it, so a rule that sent the wrong letter can be traced to what it sent.
- **Acknowledgment Rule to Appeal**, many to one, as a matching criterion.
- Acknowledgment Rule has no reference to Gift. A gift does not carry the rule that matched
  it, because rules are re-evaluated when the queue is sent (R-AK3).

### Rules

**R-AK1 First matching rule wins.** Active rules are considered in Order, lowest first, and
the first one whose criteria all match the gift decides the channel and the template. Ties
on Order are broken by Name, so a badly ordered list is still deterministic. A gift matching
no rule is left exactly as it is: no channel, no send, and the status it already had.

**R-AK2 What a rule can match on.** Amount range (inclusive at both ends), gift type,
appeal, and whether the gift is the donor's first. An empty criterion is not a criterion:
an empty Gift Type matches every type rather than matching gifts with no type. First Gift
Only is true for a gift where the donor, the Contact or the Account that the gift credits,
has no other gift of a positive amount, counted at the moment the gift is saved rather than
read from a rollup, because the rollup for a gift being inserted has not been calculated
yet.

**R-AK3 Rules are evaluated twice, on purpose.** On the save of a gift, to decide whether it
joins the queue, and again when the queue is sent, to decide which template each queued gift
gets. Nothing is stored on the gift in between. An administrator who fixes a rule's template
on Tuesday morning therefore fixes it for the gifts that arrived on Monday and have not gone
out yet, which is what she expects and what a stored channel would have prevented.

**R-AK4 Channel None means not required.** A rule whose channel is None sets the gift's
Acknowledgment Status to Not required, which is the organization saying this kind of gift
does not get a thank you. It is not the same as Do not acknowledge, which is a person's
decision about one gift and which no rule ever overwrites (R-AK6).

**R-AK5 Nothing is shipped, nothing is overwritten.** The package ships no rules. An org
with no rules acknowledges nothing automatically, which is the correct behavior for a
feature that sends mail to donors on the organization's letterhead.

---

## 25G. Acknowledgment

### Definition

One thank you, recorded (feature G-12, ADR-0032). The row exists so that the questions
asked in January have answers: did this go, when, by which letter, to which address, and
did it go twice.

An acknowledgment is not a receipt (Section 25B). It carries no number, it is not
immutable, it may legitimately happen more than once for the same gift, and it has no
statutory content.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The record's identifier, assigned automatically. |
| Gift | reference(Gift) | yes | The gift being acknowledged. |
| Rule | reference(Acknowledgment Rule) | no | The rule that produced this acknowledgment; empty when a person acknowledged the gift outside the rules. |
| Channel | picklist(Email, Letter) | yes | How this one went out. |
| Template | text | no | The developer name of the email template used, as it was at the time, so a letter that has since been rewritten can still be identified. |
| Status | picklist(Queued, Sent, Failed) | yes (defaults Queued) | Where this acknowledgment stands. A letter stays Queued until the letters are marked sent. |
| Sent On | datetime | conditional | When it went; set when Status becomes Sent. |
| Recipient Contact | reference(Contact) | no | The person it was addressed to. |
| Recipient Email | email | no | The address it was sent to, kept because the contact's address changes and the question is where it actually went. |
| Failure Reason | text | conditional | Why it did not go, in a sentence a person can read; required when Status is Failed. |
| Run | reference(Acknowledgment Run) | no | The run that produced it, empty when a person produced it one at a time. |
| Gift Key | text | no | The gift's identifier, unique, held while this acknowledgment stands and cleared when the gift is deliberately queued again (R-AK7). |

### Relationships

- **Acknowledgment to Gift**, many to one. A gift may hold several acknowledgments over its
  life; at most one of them holds the Gift Key.
- **Acknowledgment to Acknowledgment Run**, many to one.
- **Acknowledgment to Acknowledgment Rule**, many to one.

### Rules

**R-AK6 The gift's two fields are the summary, the record is the truth.** Acknowledgment
Status and Acknowledgment Date on Gift (R-G9) are written from the ledger and never the
other way around: a row reaching Sent sets the gift to Acknowledged and stamps the date. The
fields exist because a list view and a report need one column, not a subquery. Where they
disagree with the ledger the ledger is right, and Do not acknowledge on a gift is a person's
instruction that no automation and no run ever overwrites.

**R-AK7 A gift is thanked once unless a person says otherwise.** Gift Key is unique and
holds the gift's identifier from the moment the row is written, which is before anything is
sent. A second row for the same gift therefore cannot be inserted, so a batch chunk retried
after a partial failure resumes rather than sending again, and two people pressing Send at
once produce one thank you. The key is cleared in exactly two cases: the send failed, so the
gift is retried; or a person set the gift's Acknowledgment Status back to To acknowledge,
which is the deliberate act of thanking a donor again. Both leave the earlier row in place,
so "we sent it twice" reads as two rows rather than as silence.

**R-AK8 Only a positive received gift is ever acknowledged.** A gift whose Status is
Refunded, Written off or Pending, and any gift whose Amount is zero or negative, is never
queued and never sent, so the negative gift that records a refund (R-G3) is outside this
feature entirely. Refunding a gift does not withdraw its acknowledgment: the donor was
thanked, and that happened.

**R-AK9 A failure is one row, not a run.** A send that fails marks its own row Failed with
the reason, clears its key so the next send retries it, and writes an Error Log entry naming
the gift. The rest of the chunk goes out.

A gift with nobody to email, an organization gift with no primary contact for example, gets
no row at all. Nothing went wrong and nothing was attempted, so there is nothing to record
about the thank you; the run counts it, names it in one Error Log entry for the whole chunk,
and leaves the gift in the queue, where a letter rule or a corrected contact will pick it up.
A row per night for a gift that will never have an email address is noise on the donor's
record, which is the thing this ledger exists to keep clean.

---

## 25H. Acknowledgment Run

### Definition

One send (ADR-0032). It exists for the same reason the receipt run does, and for one more:
a letter run owns the merge file, which is the thing the administrator actually leaves
Salesforce with.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The run's identifier, assigned automatically. |
| Channel | picklist(Email, Letter) | yes | What the run does. |
| Status | picklist(Queued, Running, Ready to merge, Completed, Completed with errors, Failed) | yes | Where the run stands. Ready to merge belongs to a letter run whose file is written and whose letters have not yet been marked sent. |
| Started | datetime | no | When the run began. |
| Finished | datetime | no | When the run ended. |
| Gifts Processed | integer | yes (defaults 0) | How many gifts the run examined. |
| Acknowledgments Sent | integer | yes (defaults 0) | How many thank yous it produced. |
| Errors | integer | yes (defaults 0) | How many failed, each of which is also in the Error Log. |
| Async Job Id | text | no | The platform job identifier, so a stuck run can be found. |
| Merge File Document Id | text | no | The Salesforce file identifier of the letter merge CSV, on a letter run. |

### Relationships

- **Acknowledgment Run to Acknowledgment**, one to many.

### Rules

**R-AK10 A failed send never aborts the run.** Counted, logged, and the run continues. A run
that ends with any failure is Completed with errors, never Completed, which is the same
promise the receipt run makes (R-RR1).

**R-AK11 A letter run is finished by a person.** The run writes the merge file and stops at
Ready to merge with its rows Queued. Marking it sent, which the Acknowledgments page offers
and which nothing does automatically, stamps the rows and the gifts and closes the run. The
package cannot know whether a letter was printed, so it does not pretend to.

**R-AK12 The run is visible without being opened.** Last run and last run summary are held
on Giving Settings and shown on the Acknowledgments page, the same freshness promise the
seasonal address swap makes (R-AD8), so an administrator can see that last night's send
happened without finding the run record.

### Salesforce implementation

- **Objects:** `Acknowledgment_Rule__c` (Text Name), `Acknowledgment__c` (auto-number Name
  with format `AK-{000000}`) and `Acknowledgment_Run__c` (auto-number Name with format
  `AR-{000000}`), all three shipped by Giving.

| Attribute | API name | Type |
|---|---|---|
| Description | `Description__c` | Long Text Area |
| Active | `Active__c` | Checkbox |
| Order | `Order__c` | Number(4, 0) |
| Email Template | `Email_Template__c` | Text(80) |
| Minimum Amount | `Minimum_Amount__c` | Currency |
| Maximum Amount | `Maximum_Amount__c` | Currency |
| Gift Type | `Gift_Type__c` | Picklist: Cash, Check, Card, ACH, Stock, In-kind, Grant, Other |
| Appeal | `Appeal__c` | Lookup to `Appeal__c` |
| First Gift Only | `First_Gift_Only__c` | Checkbox |

- **Fields on `Acknowledgment__c`:**

| Attribute | API name | Type |
|---|---|---|
| Gift | `Gift__c` | Lookup to `Gift__c` |
| Rule | `Rule__c` | Lookup to `Acknowledgment_Rule__c` |
| Template | `Template__c` | Text(80) |
| Sent On | `Sent_On__c` | Date/Time |
| Recipient Contact | `Recipient_Contact__c` | Lookup to Contact |
| Recipient Email | `Recipient_Email__c` | Email |
| Failure Reason | `Failure_Reason__c` | Text(255) |
| Run | `Run__c` | Lookup to `Acknowledgment_Run__c` |
| Gift Key | `Gift_Key__c` | Text(18), External Id, unique |

- **Fields on `Acknowledgment_Run__c`:**

| Attribute | API name | Type |
|---|---|---|
| Started | `Started__c` | Date/Time |
| Finished | `Finished__c` | Date/Time |
| Gifts Processed | `Gifts_Processed__c` | Number(18, 0) |
| Acknowledgments Sent | `Acknowledgments_Sent__c` | Number(18, 0) |
| Errors | `Errors__c` | Number(18, 0) |
| Async Job Id | `Async_Job_Id__c` | Text(18) |
| Merge File Document Id | `Merge_File_Document_Id__c` | Text(18) |

  `Channel__c` (Picklist: Email, Letter, None on the rule; Email, Letter on the other two)
  and `Status__c` (Picklist: Queued, Sent, Failed on the acknowledgment; Queued,
  Running, Ready to merge, Completed, Completed with errors, Failed on the run) are shipped
  on the objects named above.

- **Settings keys:** `Acknowledgments_Enabled__c`, `Acknowledgment_From_Address__c`,
  `Acknowledgments_Last_Run__c` and `Acknowledgments_Last_Run_Summary__c` on
  `Giving_Settings__c` (Section 21A).
- **Validation rules:** on the rule, Maximum Amount above Minimum Amount when both are
  filled in, and an Email Template named when Channel is Email.
- **Automation:** `Gift_Acknowledgment` in `Automation_Registry__mdt`, naming
  `GiftAcknowledgmentHandler`, execution order 40, switchable and pausable like every other
  convenience (R-A1, and deliberately not `Always_Runs__c`, ADR-0024).
- **Service:** `AcknowledgmentRuleService`, `AcknowledgmentService`,
  `AcknowledgmentSelector`, `AcknowledgmentWriter` (ADR-0021), `AcknowledgmentSender` with
  `MessagingAcknowledgmentSender`, `AcknowledgmentBatch`, `AcknowledgmentScheduler`,
  `AcknowledgmentLetterMerge`, and `AcknowledgmentController` for the page.
- **Custom permission:** `Send_Acknowledgments`, granted to Giving Admin and Giving Staff.
- **Page:** LWC `acknowledgments` on the `Acknowledgments` tab and flexipage, reached from
  the Giving section of the Nonprofit Settings console by navigation (ADR-0020).

---

## 25I. Stewardship Plan Template

### Definition

A named sequence of follow-up work an organization repeats: the tasks that should happen
after a first gift, after a large gift, after a pledge starts. The NPSP Engagement Plans
successor (plan Section 5.2, feature G-15).

The template is the recipe, not the work. It holds what starts the sequence and the steps
it lays out; a `Stewardship_Plan__c` is one running copy of it on one donor, and the tasks
belong to the people who have to do them.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | yes | What the administrator calls the plan, for example "First gift welcome". |
| Plan Key | text | yes | A stable key, unique, so a shipped default is recognized on upgrade without matching on a name the administrator may have changed. |
| Active | boolean | yes (defaults false) | Whether the plan can start. An inactive template keeps the plans it already started. |
| Trigger Event | picklist(Manual, First gift, Gift received, Commitment started) | yes | What starts a plan from this template. Manual means a person starts it and nothing starts it automatically. Commitment started means a pledge or a recurring gift became active (R-SP3a). |
| Minimum Amount | currency | no | For the two gift events, the smallest gift that starts a plan. Blank means any amount. |
| Description | long text | no | What this plan is for, in the administrator's words, shown when a person picks a plan to start by hand. |

### Relationships

- **Stewardship Plan Template to Stewardship Plan Step**, one to many, master detail. A
  template's steps have no meaning apart from it, so deleting a template takes its steps.
- **Stewardship Plan Template to Stewardship Plan**, one to many, lookup. A running plan
  keeps working when its template is deleted, because the tasks it created are already real
  work assigned to real people (R-SP8).

### Rules

**R-SP1 A trigger event does not make a plan mandatory.** Every automatic start goes
through `TriggerDispatcher` like every other packaged automation, so an administrator can
switch stewardship off before a bulk import and switch it back on afterwards (rule R-A1).
Nothing here is exempt from the automation switch.

**R-SP2 Only an active template starts anything.** Deactivating a template stops new plans
and leaves running ones alone.

**R-SP3 First gift means the donor's first.** The First gift event starts a plan only when
the gift being saved is the only gift the donor has that counts toward giving totals, using
the same status set the giving rollups use (Section 26). A refund that arrives later does
not retroactively unstart the plan, because the welcome has already been sent.

**R-SP3a Commitment started means the commitment became active.** A plan on this event
starts when a commitment is created already Active, and when an existing commitment moves
into Active from any other status. Both, because a pledge entered as Active and a pledge
entered as Paused and turned on a week later are the same event to the donor. A resumed
commitment therefore starts a plan again only once the earlier plan has been closed, since
R-SP6 still holds. Nothing starts for a commitment created Paused, Completed or Cancelled,
and Minimum Amount is not read here: the amount condition belongs to the two gift events,
which is what the Amount Only For Gift Events rule already enforces at save.

### Salesforce implementation

- **Object:** `Stewardship_Plan_Template__c`, Giving package.

| Attribute | API name | Type |
|---|---|---|
| Plan Key | `Plan_Key__c` | Text, unique, external id |
| Active | `Active__c` | Checkbox |
| Trigger Event | `Trigger_Event__c` | Picklist: Manual, First gift, Gift received, Commitment started |
| Minimum Amount | `Minimum_Amount__c` | Currency (18, 2) |
| Description | `Description__c` | Long Text Area |

- **Service:** `StewardshipService`, with `StewardshipSelector` reading and
  `StewardshipWriter` writing, following the pattern the rest of Giving uses.
- **Settings console:** the Stewardship Plans page, component `stewardshipPlans` with
  `StewardshipPlanController` behind it, on the `Stewardship_Plans` tab and flexipage and
  registered as a `Setting_Definition__mdt` Component row reached by navigation (ADR-0020).
  Templates, their steps, their order and their Active state are all administered there, so
  no part of setting a plan up needs Setup or a raw object tab.

---

## 25J. Stewardship Plan Step

### Definition

One task a template lays out, and when it comes due relative to the day the plan starts.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The step's identifier, assigned automatically. |
| Plan Template | reference(Stewardship Plan Template) | yes | The template this step belongs to. |
| Order | number | yes | The order the steps are listed in and created in. |
| Subject | text | yes | The task's subject, which is what the assignee sees in their list. |
| Days After Start | number | yes (defaults 0) | How many days after the plan starts this task is due. |
| Assign To | picklist(Record owner, Plan starter, Specific user) | yes | Who gets the task. Record owner is the owner of the donor record the plan runs on. |
| Assigned User | reference(User) | conditional | Required when Assign To is Specific user, ignored otherwise. |
| Priority | picklist(Low, Normal, High) | yes (defaults Normal) | The task's priority. |
| Comments | long text | no | The task's description, copied onto every task the step creates. |

### Relationships

- **Stewardship Plan Step to Stewardship Plan Template**, many to one, master detail.

### Rules

**R-SP4 A step with no assignee resolves to the person who started the plan.** Where Assign
To is Record owner and the donor record has no owner the package can read, or where
Assigned User names a user who is inactive, the task goes to the person who started the
plan rather than to nobody. A task nobody owns is a task nobody does.

**R-SP5 A due date never lands in the past.** Days After Start is counted from the day the
plan starts, so a plan started today with a step at day zero is due today. Negative values
are refused at save.

### Salesforce implementation

- **Object:** `Stewardship_Plan_Step__c`, Giving package. Name is an auto number, `SPS-{00000000}`.

| Attribute | API name | Type |
|---|---|---|
| Plan Template | `Stewardship_Plan_Template__c` | Master-Detail to `Stewardship_Plan_Template__c` |
| Order | `Order__c` | Number (3, 0) |
| Subject | `Subject__c` | Text (255) |
| Days After Start | `Days_After_Start__c` | Number (4, 0) |
| Assign To | `Assign_To__c` | Picklist: Record owner, Plan starter, Specific user |
| Assigned User | `Assigned_User__c` | Lookup to User |
| Priority | `Priority__c` | Picklist: Low, Normal, High |
| Comments | `Comments__c` | Long Text Area |

---

## 25K. Stewardship Plan

### Definition

One running copy of a template on one donor: what started it, when, and whether it is still
going. It exists so that a person can see which sequences are open on a donor, and so the
same sequence does not start twice on the same event.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The plan's identifier, assigned automatically. |
| Plan Template | reference(Stewardship Plan Template) | yes | The template this plan was made from. |
| Contact | reference(Contact) | conditional | The donor, where people are Contacts. |
| Account | reference(Organization) | conditional | The donor, where the donor is an organization or where people are person Accounts. |
| Gift | reference(Gift) | no | The gift that started the plan, where a gift event did. |
| Commitment | reference(Commitment) | no | The commitment that started the plan, where the Commitment started event did. |
| Status | picklist(Running, Complete, Cancelled) | yes (defaults Running) | Where the sequence stands. |
| Started Date | date | yes | The day the plan started, which is the day its due dates count from. |
| Completed Date | date | no | The day the plan was marked complete or cancelled. |

### Relationships

- **Stewardship Plan to Contact or Organization**, many to one. Exactly one of the two is
  set, following the person reference convention in Section 4.
- **Stewardship Plan to Task**, one to many. Each task carries the plan on its `WhatId`, so
  the tasks a plan created are visible from the plan without a package field on Task.

### Rules

**R-SP6 One running plan per template per donor.** Starting a template on a donor that
already has a Running plan from that template is refused with a readable message rather
than creating a second set of the same tasks. Completing or cancelling the first one frees
the donor for another.

**R-SP7 Tasks are created once, when the plan starts.** All of a template's steps become
tasks at start, dated from Started Date. Editing a template afterwards does not reach back
into plans already running, because the tasks are already in people's lists and rewriting
them would move work someone has planned their week around.

**R-SP8 The package never deletes a task it created.** Cancelling a plan sets its status and
its Completed Date and leaves every task alone. A task is a person's record of their own
work, and an open task on a cancelled plan is theirs to close. Deleting a template does not
touch running plans or their tasks for the same reason.

**R-SP9 A failure to start a plan never fails the gift.** The starter runs after the gift is
saved and logs to Error Log (rule R-E1). A stewardship plan that could not start is a follow
up that did not happen; a gift that could not save is money the organization lost track of,
and the second is worse.

**R-SP10 Completion is a person's judgment in v0.4.** A plan is marked Complete by whoever
decides the sequence is done. The package does not close a plan automatically when its last
task closes: that needs automation on Task, which the package does not ship, and the plan's
status is a record of intent rather than a derived count. This is recorded here as a
deliberate limit rather than an omission, and it is the first thing to revisit if plans are
found sitting Running long after their work finished.

### Salesforce implementation

- **Object:** `Stewardship_Plan__c`, Giving package. Name is an auto number, `SP-{00000000}`.

| Attribute | API name | Type |
|---|---|---|
| Plan Template | `Stewardship_Plan_Template__c` | Lookup to `Stewardship_Plan_Template__c` |
| Contact | `Contact__c` | Lookup to Contact |
| Account | `Account__c` | Lookup to Account |
| Gift | `Gift__c` | Lookup to `Gift__c` |
| Commitment | `Commitment__c` | Lookup to `Commitment__c` |
| Status | `Status__c` | Picklist: Running, Complete, Cancelled |
| Started Date | `Started_Date__c` | Date |
| Completed Date | `Completed_Date__c` | Date |

- **Automation:** two `Automation_Registry__mdt` rows, both order 60 and neither always
  running: `Stewardship_Plan_Starter`, handler `StewardshipTriggerHandler`, on `Gift__c`,
  and `Stewardship_Plan_Starter_Commitment`, handler `StewardshipCommitmentHandler`, on
  `Commitment__c`. Two rows rather than one because the switch is per row, and an
  administrator loading a year of gifts has no reason to also stop the commitments she
  enters by hand from starting their plans.

---

## 26. Packaged default rollups

### Definition

The Rollup Definitions the Giving package ships and the attributes they write (plan
Sections 4.6 and 4.10, features G-02 and G-11). They are shipped as
`Rollup_Definition_Default__mdt` rows and materialized as `Rollup_Definition__c` records
on install (Section 13, R-R6). Every one of them is editable and deactivatable by the
admin.

The Giving package owns these target attributes, including the ones that sit on the
standard Account and Contact objects. An org without Giving installed has none of them,
which is Principle 3.

### Target scopes

Account carries households, organizations, and, in Person Account orgs, people. One
target attribute therefore serves three kinds of record, filled by three definitions whose
target record sets are disjoint (R-R8).

| Scope | Target entity | Target filter | Relationship path from Gift |
|---|---|---|---|
| Household | Account, record type Household | record type is Household | `Household__c` |
| Account (organization or person) | Account, any other record type | record type is not Household | `Donor_Account__c` |
| Contact | Contact | none | `Donor_Contact__c` |

Definition keys follow the scope: `Household_Total_Giving`, `Account_Total_Giving`,
`Contact_Total_Giving`, and so on, so a shipped default can be found by name.

### Giving totals on Account and Contact

Every definition here uses source entity Gift with the base filter `Status` in
`Received`, `Refunded`, `Written off`, and mode Both. The set, rather than `Status equals
Received`, is what makes R-R9 true: a refund is a negative gift whose own status is
Received while the original it reverses is moved to Refunded, so a filter that admitted
only Received would keep the negative rows and drop the positive one, and a fully refunded
gift would subtract itself twice (ADR-0022). Pending, Failed, and any other status that
does not represent money the organization holds stay outside the filter.

The rows that count, rather than add, carry `Amount__c` greater than 0 on top of that
status set, so that a gift given once and refunded in full reads as one gift and a total
of zero. A count and a sum here answer different questions on purpose: how many gifts this
donor gave, and what the organization is left holding.

| Target attribute | Aggregate | Source attribute | Extra filter | Definition |
|---|---|---|---|---|
| `Total_Giving__c` | SUM | `Amount__c` | none | The total of all gifts ever received from this donor, net of anything given back. |
| `Gift_Count__c` | COUNT | none | `Amount__c` greater than 0 | How many gifts this donor has given, counting a gift once whether or not it was later refunded. |
| `First_Gift_Date__c` | MIN | `Gift_Date__c` | `Amount__c` greater than 0 | The date of this donor's first gift, which is what "new donor" reporting counts from. |
| `Last_Gift_Date__c` | MAX | `Gift_Date__c` | `Amount__c` greater than 0 | The date of this donor's most recent gift, which is what lapsed-donor reporting counts from. |
| `Largest_Gift__c` | MAX | `Amount__c` | `Amount__c` greater than 0 | The largest single gift this donor has given. Without the amount condition a donor whose whole history was refunded would have a negative gift as their largest. |
| `Giving_This_Year__c` | SUM | `Amount__c` | fiscal year offset 0 | Total given in the current fiscal year. |
| `Giving_Last_Year__c` | SUM | `Amount__c` | fiscal year offset -1 | Total given in the previous fiscal year, which is the "LY" in LYBUNT. |
| `Giving_Two_Years_Ago__c` | SUM | `Amount__c` | fiscal year offset -2 | Total given two fiscal years ago, used by SYBUNT and retention reporting. |
| `Gifts_Last_Year__c` | COUNT | none | `Amount__c` greater than 0, fiscal year offset -1 | How many gifts this donor gave in the previous fiscal year, counting a gift once whether or not it was later refunded. A sum cannot answer this: a donor whose only gift last year was refunded inside that same year sums to zero while having given, and a donor whose sole activity last year was a refund of an older gift sums to less than zero while having given nothing. The retention reports read this attribute to tell a retained donor from a reactivated one (G-16, ADR-0026). |

### In-kind giving on Account and Contact

An in-kind gift is a Gift with Type In-kind whose Amount is zero (R-G12, ADR-0030), so it
adds nothing to any row in the table above and is excluded from every row that counts, which
is what keeps a donated vehicle out of Total Giving, out of Largest Gift, out of a donor level
(ADR-0028) and out of the retention reports (ADR-0026). These two rows are where it does
appear. They take the same status set and add `Type__c` equals `In-kind`.

| Target attribute | Aggregate | Source attribute | Extra filter | Definition |
|---|---|---|---|---|
| `In_Kind_Value__c` | SUM | `Fair_Market_Value__c` | `Type__c` equals `In-kind` | What this donor's gifts of goods and services were worth, as the organization recorded them. Reported beside Total Giving and never added to it. |
| `In_Kind_Gift_Count__c` | COUNT | none | `Type__c` equals `In-kind` | How many gifts of goods and services this donor has given. There is no amount condition here, because a donor can give goods whose value they never told the organization and that gift still happened. |

Two further definitions on the same targets use different sources:

| Target attribute | Source | Aggregate | Source attribute | Filter | Definition |
|---|---|---|---|---|---|
| `Pledge_Balance__c` | Commitment | SUM | `Balance__c` | Type is Pledge and Status is Active or Paused | What this donor has promised and not yet paid. |
| `Total_Soft_Credits__c` | Soft Credit | SUM | `Amount__c` | gift status in the set above | The total this donor is recognized for without being hard credited. |
| `Soft_Credit_Count__c` | Soft Credit | COUNT | none | gift status in the set above, `Amount__c` greater than 0 | How many gifts this donor is recognized on. |

Relationship paths for the two non-Gift sources follow the same scope table, reading
`Household__c`, `Donor_Account__c`, or `Donor_Contact__c` on Commitment and `Account__c`
or `Contact__c` on Soft Credit.

### Totals on Giving objects

| Target entity | Target attribute | Source | Aggregate | Source attribute | Filter | Definition |
|---|---|---|---|---|---|---|
| Fund | `Total_Raised__c` | Gift Allocation | SUM | `Amount__c` | gift status in the set above | Everything ever designated to this fund. |
| Fund | `Total_Raised_This_Year__c` | Gift Allocation | SUM | `Amount__c` | gift status in the set above, fiscal year offset 0 | Designated to this fund in the current fiscal year. |
| Fund | `Gift_Count__c` | Gift Allocation | COUNT | none | gift status in the set above, `Amount__c` greater than 0 | How many gifts have been designated to this fund. |
| Fund | `Last_Gift_Date__c` | Gift Allocation | MAX | `Gift__r.Gift_Date__c` | gift status in the set above, `Amount__c` greater than 0 | The most recent gift to this fund. |
| Appeal | `Total_Raised__c` | Gift | SUM | `Amount__c` | status in the set above | What this appeal brought in. |
| Appeal | `Gift_Count__c` | Gift | COUNT | none | status in the set above, `Amount__c` greater than 0 | How many gifts responded to this appeal. |
| Commitment | `Paid_To_Date__c` | Gift | SUM | `Amount__c` | status in the set above | What has been paid against this commitment. |
| Installment | `Paid_Amount__c` | Gift | SUM | `Amount__c` | status in the set above | What has been paid against this scheduled installment. |

The fund definitions aggregate Gift Allocation but filter and read attributes on the
parent gift, written with a relationship-qualified name such as `Gift__r.Status__c`. That
is a requirement on the aggregation engine, recorded here so that it is part of the
vendoring evaluation in ADR-0011 rather than a surprise during the build.

Appeal donor count is deliberately absent: counting distinct donors is not one of the
seven aggregates the engine offers (plan Section 4.10), and a grouped report answers it
without a new engine capability.

### Freshness: one last-calculated attribute per target entity

Every target entity carries a single `Rollups_Last_Calculated__c` datetime, written when
a rollup pass over that entity completes. There is not one per target attribute.

*Why.* The requirement is that a rollup shows when it was last calculated (Principle 2,
plan Section 4.10). Two questions are actually asked, and one attribute each answers
them: "when was this record's giving last recalculated", answered on the record page by
the entity-level attribute, and "when did this particular rollup last run", answered in
the settings console by Last Calculated on the Rollup Definition (R-R5). A per-attribute
sibling would add eleven datetime attributes to Account and eleven to Contact, all
carrying the same value whenever the pass that writes them is the same pass, which it is:
the engine recalculates a target record's definitions together. The cost of the choice is
that a single definition recalculated on its own moves the whole entity's stamp, which is
why the definition keeps its own Last Calculated as well.

### Salesforce implementation

- **Fields on Account** (shipped by Giving, shown on the Household and Organization
  layouts and, in Person Account orgs, on the person layout):

| Attribute | API name | Type |
|---|---|---|
| Total Giving | `Total_Giving__c` | Currency |
| Gift Count | `Gift_Count__c` | Number |
| First Gift Date | `First_Gift_Date__c` | Date |
| Last Gift Date | `Last_Gift_Date__c` | Date |
| Largest Gift | `Largest_Gift__c` | Currency |
| Giving This Year | `Giving_This_Year__c` | Currency |
| Giving Last Year | `Giving_Last_Year__c` | Currency |
| Giving Two Years Ago | `Giving_Two_Years_Ago__c` | Currency |
| Gifts Last Year | `Gifts_Last_Year__c` | Number |
| Pledge Balance | `Pledge_Balance__c` | Currency |
| Total Soft Credits | `Total_Soft_Credits__c` | Currency |
| Soft Credit Count | `Soft_Credit_Count__c` | Number |
| In-kind Value | `In_Kind_Value__c` | Currency |
| In-kind Gift Count | `In_Kind_Gift_Count__c` | Number |
| Rollups Last Calculated | `Rollups_Last_Calculated__c` | DateTime |

- **Fields on Contact** (shipped by Giving): the same fifteen API names, with the same
  types and the same definitions.

- **Fields on `Fund__c`:**

| Attribute | API name | Type |
|---|---|---|
| Total Raised | `Total_Raised__c` | Currency |
| Total Raised This Year | `Total_Raised_This_Year__c` | Currency |
| Gift Count | `Gift_Count__c` | Number |
| Last Gift Date | `Last_Gift_Date__c` | Date |
| Rollups Last Calculated | `Rollups_Last_Calculated__c` | DateTime |

- **Fields on `Appeal__c`:**

| Attribute | API name | Type |
|---|---|---|
| Total Raised | `Total_Raised__c` | Currency |
| Gift Count | `Gift_Count__c` | Number |
| Rollups Last Calculated | `Rollups_Last_Calculated__c` | DateTime |

- **Fields on `Commitment__c`:**

| Attribute | API name | Type |
|---|---|---|
| Paid To Date | `Paid_To_Date__c` | Currency |
| Rollups Last Calculated | `Rollups_Last_Calculated__c` | DateTime |

- **Fields on `Installment__c`:**

| Attribute | API name | Type |
|---|---|---|
| Paid Amount | `Paid_Amount__c` | Currency |
| Rollups Last Calculated | `Rollups_Last_Calculated__c` | DateTime |

- **Shipped defaults:** one `Rollup_Definition_Default__mdt` row per line in the tables
  above, per scope.
- **Service:** the Core engine (Section 14); Giving ships definitions, not engine code.

---

# Part E: Core additions for v0.3

These three entities are built by the v0.3 iteration in the Core package (features C-15,
C-16, C-17). They are constituent data: they describe how the people and organizations in
Part A are connected and where they live.

## 27. Relationship

### Definition

A connection between two people: spouses, a parent and a child, two colleagues, a friend
who introduced a donor (feature C-15, v0.3). This is the successor to NPSP's relationship
object, and its defining behavior is that the package maintains the other side of the
connection so that staff never enter it twice.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The relationship's identifier, assigned automatically. |
| Contact | reference(Contact) | conditional | The person this relationship is described from, where people are Contacts. |
| Person Account | reference(Organization) | conditional | The person this relationship is described from, where people are person Accounts. |
| Related Contact | reference(Contact) | conditional | The other person, where people are Contacts. |
| Related Person Account | reference(Organization) | conditional | The other person, where people are person Accounts. |
| Type | picklist(Spouse, Partner, Parent, Child, Sibling, Grandparent, Grandchild, Friend, Colleague, Employer contact, Other) | yes | What the other person is to this person, read from this person's side. |
| Reciprocal Type | picklist(same values as Type) | computed | What this person is to the other one, filled from the shipped type mapping. |
| Status | picklist(Current, Former) | yes (defaults Current) | Whether the relationship still holds. |
| Start Date | date | no | When the relationship began. |
| End Date | date | no | When the relationship ended; empty means current. |
| Description | long text | no | Anything staff need to remember about the connection. |
| Reciprocal Relationship | reference(Relationship) | computed | The record that describes the same connection from the other person's side. |
| Is Reciprocal Managed | boolean | yes (defaults true) | Whether the package keeps the other side in step with this one. |

### Relationships

- **Relationship to each person**, many to one, to exactly one of Contact or Person
  Account on each side (Section 4 "Person references").
- **Relationship to Relationship**, one to one, pairing the two sides of one connection.

### Rules

**R-RL1 The package owns the other side.** Saving a relationship creates the mirrored
record from the other person's side, with the two sides pointing at each other and the
mirrored record's Type set from the reciprocal mapping. Editing Status, Start Date, End
Date, or Description on either side updates the other. Deleting either side deletes both.
This is controlled by the org's automatic reciprocal setting, which is on by default. On by
default means on before the org has saved anything: a checkbox on a hierarchy custom setting
reads back false, not its declared default, until Apex puts the shipped value on the record
(ADR-0035).

**R-RL2 Is Reciprocal Managed is the opt-out.** An org that needs the two sides to differ
(a relationship described asymmetrically, or one imported from a system that already holds
both sides) clears Is Reciprocal Managed on a record, and the package stops synchronizing
it while leaving the pairing reference intact.

**R-RL3 Reciprocal types come from shipped metadata.** The mapping from a type to its
reciprocal is `Relationship_Type__mdt` (Section 13). It ships gender-neutral: Parent maps
to Child, Child maps to Parent, Spouse and Partner and Sibling and Friend and Colleague
map to themselves, Grandparent maps to Grandchild, Employer contact maps to Colleague, and
anything unmapped maps to Other. No shipped row is gendered, so no reciprocal ever asserts
a person's gender from a relationship.

**R-RL4 A person is not related to themselves.** The two sides must be different people,
and a duplicate relationship of the same type between the same two people is rejected with
a message naming the existing record. A duplicate is counted in one direction: the same
person on this side, the same person on the other side, and the same type. A to B as
Parent and B to A as Parent are two different relationships and both are allowed, which is
what makes the mirrored record of A to B as Parent (B to A as Child) legal rather than a
duplicate of anything.

**R-RL4a Pairing prefers a record that is already there.** Before the package creates the
other side it looks for a relationship that is already the other side and is not paired
with anything: the two people the other way round, of exactly the reciprocal type, with no
Reciprocal Relationship set. Finding one, it pairs the two records instead of creating a
third. This is what makes an import that already carried both sides, and a restore from
the recycle bin that brought both sides back, settle into one pair rather than into
duplicates.

**R-RL5 Status follows the dates.** Setting End Date sets Status to Former on both sides.
Clearing it returns both to Current. Status is never left disagreeing with the dates.

**R-RL6 Relationships are not household membership.** A relationship never changes who is
in a household. Spouses in one household have both a household membership and, optionally,
a Spouse relationship, and the two mechanisms do not read each other.

### Salesforce implementation

- **Object:** `Relationship__c`, auto-number Name with format `RL-{000000}`.

| Attribute | API name | Type |
|---|---|---|
| Contact | `Contact__c` | Lookup to Contact |
| Person Account | `Person_Account__c` | Lookup to Account |
| Related Contact | `Related_Contact__c` | Lookup to Contact |
| Related Person Account | `Related_Person_Account__c` | Lookup to Account |
| Type | `Type__c` | Picklist: Spouse, Partner, Parent, Child, Sibling, Grandparent, Grandchild, Friend, Colleague, Employer contact, Other |
| Reciprocal Type | `Reciprocal_Type__c` | Picklist, same value set as `Type__c` |
| Status | `Status__c` | Picklist: Current, Former |
| Start Date | `Start_Date__c` | Date |
| End Date | `End_Date__c` | Date |
| Description | `Description__c` | Long Text Area |
| Reciprocal Relationship | `Reciprocal_Relationship__c` | Lookup to `Relationship__c` |
| Is Reciprocal Managed | `Is_Reciprocal_Managed__c` | Checkbox |
| Sample Data | `Sample_Data__c` | Checkbox (v0.4) |

- **Shipped defaults:** `Relationship_Type__mdt` (Section 13).
- **Settings key:** `Relationship_Auto_Reciprocal__c` (Section 12), registered in
  `SettingsService.SHIPPED_DEFAULTS` so a fresh org gets it switched on (ADR-0035).
- **Service:** `RelationshipService`, `RelationshipDomain`, `RelationshipSelector`.
- **Automation:** two registry rows on `Relationship__c`. `Relationship_Validation`, handler
  `RelationshipValidationHandler`, execution order 10, holds the defaults and the rules
  (R-RL3, R-RL4, R-RL5). `Relationship_Reciprocal`, handler
  `RelationshipMaintenanceHandler`, execution order 30, writes and removes the other side.
  Two rows so that switching the upkeep off from the Automation page leaves every rule
  running. The service stands both automations down by name while it writes the other side,
  which is how a mirrored write does not re-enter the trigger that made it and is not
  checked a second time against the record it mirrors.

---

## 28. Affiliation

### Definition

A person's connection to an organization: an employee, a board member, a congregant, a
staff contact at a funder (feature C-16, v0.3). This is the successor to NPSP's
affiliation object, and it is what lets a person be related to an organization without
leaving their household.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The affiliation's identifier, assigned automatically. |
| Contact | reference(Contact) | conditional | The person, where people are Contacts. |
| Person Account | reference(Organization) | conditional | The person, where people are person Accounts. |
| Organization | reference(Organization) | yes | The organization the person is connected to. |
| Role | text | no | What the person does there, in the org's own words, for example "Board chair". |
| Status | picklist(Current, Former) | yes (defaults Current) | Whether the person is still connected to the organization. |
| Is Primary | boolean | yes (defaults false) | Marks the organization this person is chiefly associated with. |
| Start Date | date | no | When the connection began. |
| End Date | date | no | When the connection ended; empty means current. |
| Description | long text | no | Anything staff need to remember about the connection. |

### Relationships

- **Affiliation to the person**, many to one, to exactly one of Contact or Person Account
  (Section 4 "Person references").
- **Affiliation to Organization**, many to one.
- **Contact to Primary Affiliation**, many to one: the person's primary organization,
  maintained by the package (R-AF2).

### Rules

**R-AF1 One person, one organization, dated.** A person may have many affiliations at
once, and the same person and organization may be affiliated more than once over time, so
long as the date ranges do not overlap for the same role.

**R-AF2 One primary per person.** At most one current affiliation per person has Is
Primary true. Setting it on a second clears the first, and the package mirrors the
primary organization to the person's Primary Affiliation reference so that a list view or
a mail merge can show an employer without a subquery.

**R-AF3 Affiliation is not household membership.** Setting an affiliation never changes
the person's household or their Account reference in contact mode. This is the mistake the
entity exists to prevent: a donor who works at a foundation is still a member of their
household.

**R-AF4 Status follows the dates.** As R-RL5: setting End Date sets Status to Former, and
a former affiliation is never the primary one.

**R-AF5 Created by the importer.** A spreadsheet row that names an employer creates or
matches an affiliation (R-IR1), which is how most affiliations in a converted org arrive.

### Salesforce implementation

- **Object:** `Affiliation__c`, auto-number Name with format `AF-{000000}`.

| Attribute | API name | Type |
|---|---|---|
| Contact | `Contact__c` | Lookup to Contact |
| Person Account | `Person_Account__c` | Lookup to Account |
| Organization | `Organization__c` | Lookup to Account |
| Role | `Role__c` | Text |
| Status | `Status__c` | Picklist: Current, Former |
| Is Primary | `Is_Primary__c` | Checkbox |
| Start Date | `Start_Date__c` | Date |
| End Date | `End_Date__c` | Date |
| Description | `Description__c` | Long Text Area |
| Sample Data | `Sample_Data__c` | Checkbox (v0.4) |

- **Field on Contact:** `Primary_Affiliation__c`, a Lookup to Account, maintained by the
  package (R-AF2). In Person Account orgs the same attribute exists on Account as
  `Primary_Affiliation__c`, added there with the other person attributes (Section 4
  "Person references"). It holds the **organization**, not the Affiliation record: the
  point of the field is that a list view or a mail merge can show an employer without a
  subquery, and an Affiliation id would not do that. The label an admin sees is Primary
  Affiliation because that is the nonprofit's word for it.
- **Automation:** two registry rows on `Affiliation__c`. `Affiliation_Validation`, handler
  `AffiliationValidationHandler`, execution order 10, holds the defaults and the rules
  (R-AF1, R-AF4). `Affiliation_Primary`, handler `AffiliationMaintenanceHandler`, execution
  order 30, settles who is primary. Two rows so that switching the upkeep off from the
  Automation page leaves every rule running. The service stands both automations down by
  name while it clears the primary flag from a person's other affiliations.
- **Service:** `AffiliationService`, `AffiliationDomain`.

---

## 29. Address

### Definition

A place a household, an organization, or a person receives mail (plan Section 4.7,
feature C-17). Addresses exist as records rather than as fields so that a household can
have more than one, so that a seasonal address can take over automatically, and so that
history is not lost when someone moves.

### Attributes

| Attribute | Type | Required | Definition |
|---|---|---|---|
| Name | text | computed | The address's identifier, assigned automatically. |
| Account | reference(Household) | conditional | The household or organization this address belongs to. |
| Contact | reference(Contact) | conditional | The person this address belongs to, for an address that is theirs rather than their household's. |
| Person Account | reference(Organization) | conditional | The person this address belongs to, where people are person Accounts. |
| Type | picklist(Home, Work, Mailing, Seasonal, Other) | yes | What kind of address this is. |
| Street | long text | no | The street address, including any second line. |
| City | text | no | The city or town. |
| State | text | no | The state, province, or region. |
| Postal Code | text | no | The postal or ZIP code. |
| Country | text | no | The country. |
| Seasonal Start Month | integer | conditional | The month a seasonal address takes over; required when Type is Seasonal. |
| Seasonal Start Day | integer | conditional | The day of that month; required when Type is Seasonal. |
| Seasonal End Month | integer | conditional | The month a seasonal address stops being used; required when Type is Seasonal. |
| Seasonal End Day | integer | conditional | The day of that month; required when Type is Seasonal. |
| Is Default | boolean | yes (defaults false) | Marks the address currently written to the standard address fields. |
| Verification Status | picklist(Unverified, Verified, Failed) | yes (defaults Unverified) | Whether an address verification service has confirmed this address. |
| Latest Verified Date | date | no | When verification last succeeded. |
| Replaced By Seasonal | boolean | yes (defaults false) | Marks the address the seasonal swap displaced, so the job knows which address to put back when the season ends. |

### Relationships

- **Address to its owner**, many to one, to exactly one of Account, Contact, or Person
  Account (R-AD1).
- Addresses have no relationship to gifts or receipts: a receipt reads the owner's default
  address at the time it is issued and stores the text it printed (v0.4, G-13).

### Rules

**R-AD1 One owner.** Exactly one of Account, Contact, or Person Account is set. An address
owned by an account is the household's or the organization's; an address owned by a person
is theirs alone and does not affect their household.

**R-AD2 One default per owner.** At most one address per owner has Is Default true.
Setting it on a second clears the first.

**R-AD3 Default propagation.** The default address is copied to the standard address
fields, so every standard feature, report, and third-party app keeps working: to the
Account's billing address for a household or an organization, and to the Contact's mailing
address for a person. The copy happens on save and on the seasonal swap, and the standard
fields are never the place a change is made.

Where people are person accounts, the person's mailing fields are written instead of a
contact's. An account is written that way only when its record type is a person type. In a
person accounts org those mailing fields exist on every account record, but only a person
account will accept a value in one, so the org's shape is not the question: the record's
is. A household member, or an owner named in Person Account, that turns out to be a
household or an organization is left out of the copy rather than written and refused, which
would refuse the address the user was saving along with it.

**R-AD4 Seasonal swap.** A daily scheduled job makes the seasonal address the default
while today falls inside its range, and restores the previous default when the range ends.
Ranges may wrap the end of the year, so a November to March range is one range and not two.
A range is inclusive at both ends: an address used from November 1 to March 31 is in use on
November 1 and on March 31, and out of use on April 1.

The job works one owner at a time and does exactly one of four things for each:

1. A seasonal address is in season and is not the default: the current default is marked
   Replaced By Seasonal, its default flag is cleared, and the seasonal address becomes the
   default.
2. The default is a seasonal address whose season has ended: the address marked Replaced By
   Seasonal becomes the default again and that mark is cleared. If no address carries the
   mark, the most recently created address that is not seasonal is promoted instead, and if
   the owner has no other address the seasonal one stays in place rather than leaving the
   owner with no address at all.
3. Two seasonal addresses are in season on the same day, which is a data entry mistake: the
   oldest wins so the outcome does not change from night to night, and the run records the
   collision in the Error Log rather than choosing silently.
4. Nothing to do: the right address is already the default.

Nothing else on the address is touched, and the propagation to the standard address fields
(R-AD3) is the address automation's work rather than the job's, so switching that automation
off stops the copy without stopping the swap.

**R-AD8 The run is visible.** Every run records when it finished and what it did (how many
addresses moved in, how many moved back, how many failed), and both are shown on the Hub
home page and on the Addresses page of the settings console, where the schedule is also
started and stopped. A failure on one owner is written to the Error Log and the run
continues: one household with an unreachable address never stops the rest of the org
swapping. The job reads and writes in system mode, because a nightly reconciliation of
package owned data must not depend on what the person who happened to schedule it can see
(ADR-0027).

**R-AD5 Contact address change behavior.** When a person's address is edited, the org's
contact address change behavior setting decides what happens: update the household's
address, so everyone in the household moves together, or create a personal address for
that person alone. The setting is explained in those words in the settings console, not in
terms of objects.

**R-AD6 Verification is a placeholder.** Verification Status and Latest Verified Date are
never written by packaged code. They exist so that a third-party verification app can
write them and so that a report can find unverified addresses. Third-party verification is
out of scope (plan Section 4.7).

**R-AD7 History is kept.** Moving a household creates a new address and clears the old
one's default flag. The old address is not deleted, so a mailing sent last year can still
be explained.

### Salesforce implementation

- **Object:** `Address__c`, auto-number Name with format `AD-{000000}`.

| Attribute | API name | Type |
|---|---|---|
| Account | `Account__c` | Lookup to Account |
| Contact | `Contact__c` | Lookup to Contact |
| Person Account | `Person_Account__c` | Lookup to Account |
| Type | `Type__c` | Picklist: Home, Work, Mailing, Seasonal, Other |
| Street | `Street__c` | Text Area |
| City | `City__c` | Text |
| State | `State__c` | Text |
| Postal Code | `Postal_Code__c` | Text |
| Country | `Country__c` | Text |
| Seasonal Start Month | `Seasonal_Start_Month__c` | Number (0 decimals) |
| Seasonal Start Day | `Seasonal_Start_Day__c` | Number (0 decimals) |
| Seasonal End Month | `Seasonal_End_Month__c` | Number (0 decimals) |
| Seasonal End Day | `Seasonal_End_Day__c` | Number (0 decimals) |
| Is Default | `Is_Default__c` | Checkbox |
| Verification Status | `Verification_Status__c` | Picklist: Unverified, Verified, Failed |
| Latest Verified Date | `Latest_Verified_Date__c` | Date |
| Replaced By Seasonal | `Replaced_By_Seasonal__c` | Checkbox |

- **Standard fields written:** `Account.BillingStreet`, `BillingCity`, `BillingState`,
  `BillingPostalCode`, `BillingCountry`; `Contact.MailingStreet`, `MailingCity`,
  `MailingState`, `MailingPostalCode`, `MailingCountry`.
- **Settings keys:** `Contact_Address_Change_Behavior__c`, `Seasonal_Address_Last_Run__c`,
  `Seasonal_Address_Last_Run_Summary__c` (Section 12).
- **Service:** `AddressService`, `AddressTriggerHandler`, `AddressSelector`,
  `AddressController`; and for the seasonal swap `SeasonalAddressService`,
  `SeasonalAddressSelector`, `SeasonalAddressWriter`, `SeasonalAddressBatch`,
  `SeasonalAddressScheduler`, `SeasonalAddressController`.

---

## 30. Deferred to later iterations

These entities exist in the product plan but are deliberately **not** part of v0.1, v0.2,
or v0.3. They are listed here so that nobody adds them early, and so that the iteration
that owns them is unambiguous. Each will be specified in this document by the iteration
that builds it, before its metadata is created.

| Entity | Package | Iteration | Plan reference |
|---|---|---|---|
| Receipt | Giving | v0.4 (G-13) | Section 4.11, ADR-0010 |
| Donor Level | Giving | v0.4 (G-14) | Section 5.2 |
| Gift Batch | Giving | v0.5 (G-17) | Section 4.11 |
| Volunteer, Job, Shift, Sign-up, Hours, Skill | Volunteers | v0.7 | Section 5.3 |
| Program, Service, Enrollment, Attendance, Service Delivery, Outcome | Programs | v0.8 | Section 5.4 |
| Funder pipeline entities (grant, reporting deadline, award compliance) | Funders | v0.9 | Section 5.5 |
| Connect adapter entities and mirror mappings | Connect | v0.6 onward | Section 4.12 |

Receipt left this table in v0.4 and is specified in Sections 25B to 25E, together with
Receipt Number Sequence, Receipt Run and Receipt Template. Acknowledgment Rule left it in
the same iteration and is specified in Section 25F, together with Acknowledgment (25G) and
Acknowledgment Run (25H).

Stewardship Plan left this table in v0.4 as well and is specified in Sections 25I to 25K,
as Stewardship Plan Template, Stewardship Plan Step and the running Stewardship Plan.

Two v0.4 entities have attributes that already exist on `Gift__c` from v0.2, because the
object is not worth altering later for fields this cheap: Acknowledgment Status,
Acknowledgment Date, and Receipt Number for G-12 and G-13, and In-kind Description and
Fair Market Value for G-18 (R-G9).

### Known gaps in shipped rules

Rules this document states that the shipped code does not implement. They are listed here
so that a reader is not told the product does something it does not, and so that the gap
is closed deliberately rather than discovered.

| Rule | Gap | Why it is open |
|---|---|---|
| R-M3 (Section 6) | The primary member is not mirrored to the household's Primary Contact. | `Primary_Contact__c` is a lookup to Contact, so it cannot name a person stored as a Person Account, which is the org shape junction membership serves. Closing the gap means changing the field (a Contact and Account pair, per Section 4) or dropping the second half of the rule. Needs an ADR either way. |

---

## 31. Change log

| Version | Date | Change |
|---|---|---|
| v0.1 | 2026-09-06 | Initial model: Household, Household Member, Contact, Organization, plus the platform configuration entities Error Log, Automation Setting, Setting Change, Nonprofit Settings, and the shipped-defaults custom metadata Naming Pattern and Automation Registry. |
| v0.1 | 2026-09-07 | C-05 review fix: Error Log entries are published as `Error_Log_Event__e` (Publish Immediately) and written by a subscriber, so an entry survives the rollback it documents (new rule R-E4). |
| v0.1 | 2026-09-08 | C-05 review fix: all three packaged permission sets grant Read and Create on `Error_Log_Event__e`, because publishing is governed by Create on the event (rule R-E4). |
| v0.1 | 2026-09-08 | C-01 follow-up, R-H10 enforced in code. No object or field added. Household upkeep now clears Primary Contact when the person it names is no longer a current member, in both membership modes, and promotes nobody in their place: R-H10 already said the next member is proposed and not silently assigned, so the code follows the rule rather than the rule following the code. An organization shares the Primary Contact field (R-O3) and is never touched by this upkeep. |
| v0.1 | 2026-09-09 | C-01 documentation corrections. No object, field, or code changed. The duplicated "Person attributes on Account" bullet in Section 5 is removed. Household Member's `Account` attribute is retyped `reference(Account)` and defined as the person's own account only, because `reference(Household)` read as a second household reference and invited the confusion R-M4 exists to prevent. R-M3's Primary Contact mirror is recorded as unimplemented and unimplementable as written, and listed in Section 30 as a known gap. R-H14 now says what the console does: a preview over fixed sample households rather than the org's own, and a recompute batch that confirms it was queued and then reports nothing further. |
| v0.1 | 2026-09-08 | C-09 merge and split build. No object or field added. R-H13 gains the paragraph above on what a merge does, in what order, and what audits it. Recorded against R-M3: a move carries a person's role and primary flag with them, but never gives a household a second primary, so a merge or a split of people who were each primary in their own household leaves the survivor with one. |
| v0.1 | 2026-09-07 | C-04 and C-05 build. Error Log gains Object Name. Automation Setting gains Handler Class, Object Name, Execution Order, and Package Default, all copied from the shipped registry when a record is materialized. Automation Registry field API names fixed ("Object" and "Order" are reserved words). Error Log and Setting Change record names recorded as auto numbers. Nonprofit Settings picklist keys recorded as text, per ADR-0019. |
| v0.1 | 2026-09-07 | C-01 and C-02 build. Added `Household__c` (Lookup to Account) to Household Member: the original field list named the household side and the person side with the same attribute, so junction mode had no way to say which household a membership belonged to. `Account__c` is now defined as the person side only, matching R-M4. Recorded the naming service's token forms: `{FirstName}`, `{LastName}`, and `{Salutation}`, with the `{!Token}` spelling accepted as an alias so patterns copied from formula fields keep working. |
| v0.1 | 2026-09-07 | Junction membership made a first-class v0.1 path for orgs that store people as accounts (product owner priority change). The five Contact person attributes (`Deceased__c`, `Household_Role__c`, `Exclude_From_Household_Name__c`, `Exclude_From_Greetings__c`, `Preferred_Name__c`) are now present on Account with the same API names and definitions, because a person stored as an account carries them on that record. Naming and greetings read a person through the `HouseholdService.Person` shape rather than through Contact, so one set of rules serves both. |
| v0.1 | 2026-09-08 | C-01 and C-02 review round. `Household__c` on Household Member is now a required lookup with a cascade delete, matching the "Required: yes" already in the attribute table. The Salesforce note that a household could be deleted without touching membership history was written before the field was required and is corrected: a deleted household now takes its own membership rows with it, which is the only case where history is lost.
| v0.2 | 2026-09-07 | Core: Rollup Definition (Section 14) with the filter document format and the mode-resolved path notation; Import Template, Import Batch, and Import Row (Sections 15 to 17) with the Created By Import Batch tag on Household, Contact, Organization, and Gift. Giving: Gift, Gift Allocation, Fund, and Appeal (Sections 18 to 21), and the packaged default giving rollups (Section 26). Nonprofit Settings gains `Fiscal_Year_Start_Month__c`, `Default_Fund__c`, `Default_Appeal__c`, `Rollup_Mode_Default__c`, `Import_Chunk_Size__c`, and `Setup_Assistant_Steps_Complete__c`. Shipped defaults gain `Rollup_Definition_Default__mdt` and `Import_Template_Default__mdt`. Published for build, objects not yet created. |
| v0.3 | 2026-09-07 | Giving: Commitment, Installment, Soft Credit, and Tribute (Sections 22 to 25) with their rollup targets. Core: Relationship, Affiliation, and Address (Sections 27 to 29), the Primary Affiliation reference on Contact, and the shipped defaults `Relationship_Type__mdt`. Nonprofit Settings gains `Automatic_Household_Soft_Credits__c`, `Installment_Generation_Horizon_Months__c`, `Installment_Overdue_Grace_Days__c`, `Contact_Address_Change_Behavior__c`, `Relationship_Auto_Reciprocal__c`, and `Seasonal_Address_Last_Run__c`. Published for build, objects not yet created. |
| v0.3 | 2026-09-07 | Convention added: person references are a Contact and Account pair with exactly one set (Section 4), following the change of first customer to Nonprofit Cloud and Agentforce Nonprofit orgs where individuals are person Accounts. Import Row and Import Template carry the person-mode attributes this requires. |
| v0.3 | 2026-09-08 | G-08, G-09, G-10 review round. R-SC3a records that the membership change recompute is queued and capped at 500 gifts per household. R-TR6 now reads Deceased on Account as well as Contact, and allows notifying an honoree who is not marked deceased. R-G11 refuses a link where either gift has been refunded or written off. |
| v0.3 | 2026-09-07 | Giving G-08, G-09, G-10: the Employer attribute on Contact and on Account (`Employer__c`), rule R-G11 (matching gift linkage), rules R-SC6 and R-SC7 (automatic soft credits are recomputed and deduplicated), rule R-TR6 (a memorial is never notified to the person who died), and the gift status Received filter on the two soft credit rollups in Section 26. |
| v0.3 | 2026-09-07 | Giving: Gift gains `Refund_Reason__c`, so the reason a refund or a write-off was recorded is held on the negative gift rather than by editing the original (R-G3, G-04). Giving Settings added as Section 21A: `Giving_Settings__c` holds the three v0.3 Giving keys that ADR-0017 moved out of `Nonprofit_Settings__c`, and Section 12 records the move. |
| v0.3 | 2026-09-07 | Commitments (G-07, G-11): Giving Settings gains `Auto_Apply_Gifts_To_Installments__c` and `Installment_Top_Up_Last_Run__c`, and Section 12 records that the Giving keys live on `Giving_Settings__c` rather than `Nonprofit_Settings__c` (ADR-0017). R-CM5 states that Balance is empty for a recurring commitment; R-IN3 states the automatic linking of a gift to the earliest unpaid installment. |
| v0.3 | 2026-09-07 | Sections renumbered to keep the document in reading order: the former Section 14 "Deferred to later iterations" is now Section 30 and the former Section 15 "Change log" is now Section 31. Section 32 "Entity ownership by package" is new. |
| v0.3 | 2026-09-07 | C-10 sample data loader: added `Sample Data` (`Sample_Data__c`, Checkbox, default false) to Household, Contact, and Organization so the sample data set can be removed in one action. |
| v0.3 | 2026-09-08 | C-15 and C-16 automation split (product owner decision). No object or field added. Relationships and affiliations each ship two `Automation_Registry__mdt` rows instead of one: `Relationship_Validation` (order 10, `RelationshipValidationHandler`) with `Relationship_Reciprocal` (order 30, `RelationshipMaintenanceHandler`), and `Affiliation_Validation` (order 10, `AffiliationValidationHandler`) with `Affiliation_Primary` (order 30, `AffiliationMaintenanceHandler`). Switching the maintenance automation off no longer switches off that object's validation, which is what an administrator pausing automation before a bulk import needs. `applyDefaults` sits with the validation handler because the status and date rules (R-RL5, R-AF4) have to survive the upkeep being off. Both services now bypass the validation row alongside their own while they write. |
| v0.3 | 2026-09-09 | C-15 defect found by the first org run: the reciprocal upkeep never ran on a fresh org. `Relationship_Auto_Reciprocal__c` ships on, but a checkbox on a hierarchy custom setting read through `getOrgDefaults()` before the org has saved comes back false rather than carrying its declared default, so `RelationshipService` read the feature as switched off and wrote no other side, silently. No object or field added: the shipped value is now declared in `SettingsService.SHIPPED_DEFAULTS` and applied to the unsaved record, and `scripts/ci/check-setting-defaults.py` fails the build for any checkbox that ships on and is not registered (ADR-0035). |
| v0.3 | 2026-09-08 | C-13 rollup adapter build. `Rollup_Definition__c` and `Rollup_Definition_Default__mdt` created as Sections 14 and 13 specify, with one correction: both gain `Fiscal_Date_Field__c`. R-R3 said the fiscal window is computed from the start month and the offset but never said which date attribute it is measured on, and every fiscal definition in Section 26 sums an amount rather than a date, so the window had nothing to bound. The attribute is optional and falls back to the attribute being aggregated, which is right for a rollup that aggregates a date. `Mode__c` on the definition ships with Both as its default value, matching R-R4 and the shipped Giving rows. |
| v0.3 | 2026-09-08 | C-17 Addresses build. `Address__c` and its fields, list views, compact layout, and validation rules created as specified in Section 29, with two recorded deviations: `Street__c` ships as Text Area (255) because the platform has no long text field that a list view or a validation rule can read, and `Contact_Address_Change_Behavior__c` ships as Text(40) on `Nonprofit_Settings__c` per ADR-0019 rather than as a picklist. `Verification_Status__c` defaults to Unverified and is left writable for a third party verification app (R-AD6); no packaged code writes it. |
| v0.3 | 2026-09-08 | G-02 defect fix (ADR-0022). No object or field added. Section 26's base filter changes from `Status equals Received` to `Status` in `Received`, `Refunded`, `Written off`, because R-G3 moves a fully refunded gift's status while leaving the negative gifts that reverse it at Received, so the old filter kept the negatives, dropped the positive, and subtracted a refunded gift twice. The count rows, largest gift, and the two date rows additionally require `Amount__c` greater than 0, so a gift given once and refunded in full reads as one gift and a total of zero. All 38 gift sourced, Gift Allocation sourced and Soft Credit sourced `Rollup_Definition_Default__mdt` rows updated; the three Pledge Balance rows filter on Commitment status and are unaffected. R-R9 gains the sentence that makes this a consequence of the rule rather than an exception to it. |
| v0.3 | 2026-09-08 | G-08 rule collision resolved (ADR-0023). No object, field, or rollup row changed. R-SC5 and R-SC6 collided on a full refund: R-SC5 creates a negative automatic credit on the negative gift while R-SC6 removed the original gift's automatic credits once its status became Refunded or Written off, so a fully refunded gift of 250 left a recognition total of minus 250 rather than zero. R-SC6 no longer removes credits on refund; removal is now only for a deleted gift. R-SC5 states the resulting pair explicitly and R-SC3 states that a gift keeps its household credits after its status is reversed. Section 26's soft credit rows already read gift status through the widened set from ADR-0022, so they need no further change and now carry both halves of the pair. |
| v0.3 | 2026-09-08 | G-04 receipt lock (ADR-0024). `Automation_Registry__mdt` and `Automation_Setting__c` each gain `Always_Runs__c` (Checkbox, default false): an automation marked that way enforces a rule rather than providing a convenience, so the dispatcher ignores the bypass, the pause and the switch for it, and the console shows its switch off and disabled with a reason (new rule R-A4). Giving ships the `Gift_Receipt_Lock` automation (order 5, `GiftReceiptLockHandler`) carrying the two enforcement calls that used to run inside `Gift_Core_Rules`, and the custom permission `Override_Receipt_Lock`, which is on no permission set and in no permission set group. R-G4 restated: the lock survives the automation switch, the override is a deliberate act in Setup, and every use of it is written to the Error Log at Warning severity. No object added. |
| v0.4 | 2026-09-08 | G-15 stewardship plans. Three objects added: `Stewardship_Plan_Template__c` (Section 25I) with `Plan_Key__c`, `Active__c`, `Trigger_Event__c`, `Minimum_Amount__c` and `Description__c`; `Stewardship_Plan_Step__c` (25J) as its master detail child; and the running `Stewardship_Plan__c` (25K), which carries the person reference pair `Contact__c` and `Account__c` with exactly one set. Rules R-SP1 to R-SP10. Two limits are recorded as decisions rather than gaps: R-SP7 does not reach back into running plans when a template is edited, and R-SP10 leaves completion to a person because closing a plan from its last task would need packaged automation on Task. Tasks hang off the plan through `WhatId`, so no package field is added to a standard object. |
| v0.4 | 2026-09-08 | G-15 gaps closed. `Stewardship_Plan__c` gains `Commitment__c` (Lookup), because the Commitment started event now starts plans and a plan started that way had nothing recording what started it. New rule R-SP3a says what the event means: a commitment created Active, or an existing commitment moving into Active from any other status. The automation is two registry rows rather than one, `Stewardship_Plan_Starter` on `Gift__c` and `Stewardship_Plan_Starter_Commitment` on `Commitment__c`, so each is switchable on its own. Templates, steps, step order and the Active state are now administered on a Stewardship Plans page in the settings console rather than on raw object tabs, which is what the every setting in the console rule requires. R-SP10 is unchanged: completion is still a person's judgment. |
| v0.4 | 2026-09-08 | G-16 retention reports. One attribute added: `Gifts_Last_Year__c` (Number) on Account and Contact, filled by three new `Rollup_Definition_Default__mdt` rows (`Household_Gifts_Last_Year`, `Account_Gifts_Last_Year`, `Contact_Gifts_Last_Year`) as a COUNT over Gift with the ADR-0022 count filter and fiscal year offset -1. It is the one retention question no shipped attribute could answer: whether a donor gave last fiscal year, counted rather than summed. Everything else G-16 needs was already here, so LYBUNT, SYBUNT and the conversion report add no fields and read `Last_Gift_Date__c`, `First_Gift_Date__c` and `Gift_Count__c`, which already carry the count filter. No object added (ADR-0025, ADR-0026). |
| v0.4 | 2026-09-08 | C-18 seasonal address swap build. `Address__c` gains `Replaced_By_Seasonal__c` (Checkbox, default false): R-AD4 said the previous default is restored when a season ends but nothing recorded which address that was, so an owner with a home address, a work address and a winter address had no unambiguous address to go back to. `Nonprofit_Settings__c` gains `Seasonal_Address_Last_Run_Summary__c` (Text 255) alongside the `Seasonal_Address_Last_Run__c` timestamp already specified in v0.3: a bare timestamp says the job woke up, not that it did anything, and "visible last run" is the half of C-18 that makes the job trustworthy. R-AD4 restated with the four outcomes per owner and the inclusive boundary days; R-AD8 added for the visible run and the system mode posture (ADR-0027). |
| v0.4 | 2026-09-09 | G-10 refund propagation (ADR-0031). No object, field, or rollup row changed. ADR-0023 left one credit unreversed: the Matched Donor credit R-G11 creates sits on the employer's gift, and the negative gift recording a refund is not half of a matching pair, so a refunded match left the employee recognized for the full amount. R-G11 and R-SC5 restated: the negative gift carries a negative Matched Donor credit for the same person, prorated to the amount returned, so an employer gift of 500 with 200 returned leaves the employee recognized for 300. Only the employer's gift reverses the credit, the link survives the refund, and unlinking removes both halves. Section 26's soft credit rows already read gift status through the widened set from ADR-0022 and need no change. |
| v0.4 | 2026-09-08 | G-14 donor levels (ADR-0028). New Section 25A, `Donor_Level__c`, with `Minimum_Amount__c`, `Maximum_Amount__c`, `Description__c` and `Active__c`, and three fields shipped by Giving on both Account and Contact: `Donor_Level__c`, `Previous_Donor_Level__c` and `Donor_Level_Changed_Date__c`. Giving Settings gains `Donor_Levels_Enabled__c`, `Donor_Level_Source_Field__c` and `Donor_Levels_Last_Recalculated__c`. A level is a label on a giving total the rollup engine already maintains (R-DL1), never a second aggregation, so the ladder cannot disagree with the total printed beside it and the household membership modes are resolved once, by the rollup, rather than twice. Donor Level is removed from the deferred table in Section 30 and its ownership row now points at Section 25A. |
| v0.4 | 2026-09-08 | G-13 receipting (ADR-0016). Four objects added: `Receipt__c` (Section 25B), `Receipt_Number_Sequence__c` (25C), `Receipt_Run__c` (25D) and `Receipt_Template__c` (25E), with rules R-RC1 to R-RC10, R-RS1 to R-RS3, R-RR1 to R-RR3 and R-RT1 to R-RT3. Gift gains `Benefit_Description__c`, `Benefit_Value__c` and `Intangible_Religious_Benefits__c`, which is what a receipt needs to state a quid pro quo disclosure and the intangible religious benefits sentence; the deductible amount is computed by the renderer rather than stored, because a stored copy of a subtraction is a second place for it to be wrong. Giving Settings gains `Receipt_Number_Prefix__c`, `Receipt_Next_Counter__c`, `Receipt_Statement_Year__c`, `Receipt_Place_Of_Issue__c` and `Receipt_Renderer__c`, and its implementation subsection now lists every key it holds. Receipt leaves Section 30. |
| v0.4 | 2026-09-09 | G-18 in-kind gifts (ADR-0030). No object added. Two attributes added on both Account and Contact, `In_Kind_Value__c` (Currency) and `In_Kind_Gift_Count__c` (Number), filled by six new `Rollup_Definition_Default__mdt` rows across the three scopes of Section 26, filtered to `Type__c` equals `In-kind` on top of the ADR-0022 status set. Rule R-G12 records what an in-kind gift is: a Gift of Type In-kind whose Amount is zero, whose worth is on `Fair_Market_Value__c`, which is never printed on a receipt, and whose description is required and is printed. R-G4 gains `In_Kind_Description__c`, because it appears on the document the donor holds. The `Amount_Cannot_Be_Zero` validation rule is narrowed to gifts that are not in-kind, and `In_Kind_Needs_Description`, `In_Kind_Has_No_Amount`, `In_Kind_Fields_Need_In_Kind_Type` and `Fair_Market_Value_Not_Negative` are added. |
| v0.4 | 2026-09-09 | G-12 acknowledgments (ADR-0032). Three objects added: `Acknowledgment_Rule__c` (Section 25F), `Acknowledgment__c` (25G) and `Acknowledgment_Run__c` (25H), with rules R-AK1 to R-AK12. No field is added to `Gift__c`: `Acknowledgment_Status__c` and `Acknowledgment_Date__c` were shipped in v0.2 for this feature (R-G9), and the rule that matched a gift is deliberately not stored on it, so that an edited rule applies to the gifts already queued (R-AK3). Giving Settings gains `Acknowledgments_Enabled__c`, `Acknowledgment_From_Address__c`, `Acknowledgments_Last_Run__c` and `Acknowledgments_Last_Run_Summary__c`. The wording of an emailed thank you lives in a standard `EmailTemplate` rather than in a packaged template object, which is what the plan's note on G-12 asks for and is the whole of the difference between this feature and receipting. Acknowledgment Rule leaves Section 30.
| v0.4 | 2026-09-09 | G-13 receipt number tampering fixed (ADR-0033). No object or field added. `Gift__c.Receipt_Number__c` becomes read only in `Giving_Staff` and `Giving_Admin`, matching `Giving_Read_Only`, and the receipt lock refuses every write to it, including the first one and including an insert, unless the receipting code is renumbering that gift. R-G4 restated: the number comes from the sequence in Section 25C or it does not exist. A number typed on by hand belonged to no receipt, locked the gift irreversibly, could be issued again later by the sequence, and left the gift unreceiptable, which is the collision ADR-0016 says nobody can recover from. The write moves from user mode to `GiftReceiptNumberWriter` in system mode under ADR-0021, because a field nobody may edit cannot be written in user mode, and the renumbering allowance changes from a transaction wide flag to the set of gift Ids being renumbered, so it no longer reaches an unrelated gift saved in the same transaction. |
| v0.4 | 2026-09-09 | G-13 receipting defects found by security review (ADR-0034). No object or field added. Section 25B gains R-RC11: a receipt's stored file is linked to its receipt and, on a per gift receipt, to its gift, and never to the donor Contact or Account, because a `ContentDocumentLink` grants access to a file through the record it names and every Core role can read a donor. The relationship bullet is corrected to match. Section 25E gains R-RT4: the shipped letters are materialized by the Giving post-install script rather than by a cacheable controller method, which cannot perform DML, and every write to `Receipt_Template__c` checks `Manage_Nonprofit_Settings`. |
| v0.4 | 2026-09-08 | C-10 sample data extended to the Giving module and to connections. `Sample Data` (`Sample_Data__c`, Checkbox, default false) added to `Gift__c`, `Fund__c`, `Appeal__c`, `Commitment__c`, `Relationship__c` and `Affiliation__c`, so every record the sample loader creates can be found and removed in one action; a gift's allocations, soft credits and tributes, and a commitment's installments, are details of a flagged record and go with it. `Sample Data Key` (`Sample_Data_Key__c`, Text(20)) added to Account and Contact: it holds the key the generated file gives a household, an organization or a person, which is how the Giving sample gifts find the donor they belong to across the asynchronous chain. No object added. |
| v0.4 | 2026-09-09 | C-17 address propagation defect, found by the first org run on a person accounts org. No object or field added. R-AD3 gains the record type test: the person mailing fields exist on every account in a person accounts org, so `AddressService` asked the org whether it had them and then wrote them on whatever account it was holding. A household member, or an owner named in Person Account, that is a household or an organization was written through fields it cannot carry, the platform refused the update, and the address the user was saving was refused with it, with a message about permissions that named nothing true. The write is now decided by the account's record type, read once per save through `HouseholdSelector.getAccountRecordTypes` as an ADR-0021 upkeep read, and an account that holds no person is left out of the copy. Invisible on the Platform-only shape (ADR-0013), where the fields do not exist and the path returns early. |

---
## 32. Entity ownership by package
One row per entity in the model, so a contributor or an agent can tell at a glance which
package owns a thing and which iteration creates it. Package configuration entities are
included; standard objects the packages extend are named by the entity that governs them.
| Entity | Package | Iteration | Section |
|---|---|---|---|
| Household (Account, record type Household) | Core | v0.1 | 5 |
| Household Member | Core | v0.1 | 6 |
| Contact | Core | v0.1 | 7 |
| Organization (Account, record type Organization) | Core | v0.1 | 8 |
| Error Log | Core | v0.1 | 9 |
| Automation Setting | Core | v0.1 | 10 |
| Setting Change | Core | v0.1 | 11 |
| Nonprofit Settings | Core | v0.1, extended v0.2 and v0.3 | 12 |
| Naming Pattern (shipped default) | Core | v0.1 | 13 |
| Automation Registry (shipped default) | Core | v0.1 | 13 |
| Rollup Definition | Core | v0.2 | 14 |
| Rollup Definition Default (shipped default) | Core | v0.2 | 13 |
| Import Template | Core | v0.2 | 15 |
| Import Template Default (shipped default) | Core | v0.2 | 13 |
| Import Batch | Core | v0.2 | 16 |
| Import Row | Core | v0.2 | 17 |
| Gift | Giving | v0.2 | 18 |
| Gift Allocation | Giving | v0.2 | 19 |
| Fund | Giving | v0.2 | 20 |
| Appeal | Giving | v0.2 | 21 |
| Giving Settings | Giving | v0.2, keys from v0.3 and v0.4 | 21A |
| Giving rollup target attributes on Account and Contact | Giving | v0.2 | 26 |
| Commitment | Giving | v0.3 | 22 |
| Installment | Giving | v0.3 | 23 |
| Soft Credit | Giving | v0.3 | 24 |
| Tribute | Giving | v0.3 | 25 |
| Relationship | Core | v0.3 | 27 |
| Relationship Type (shipped default) | Core | v0.3 | 13 |
| Affiliation | Core | v0.3 | 28 |
| Address | Core | v0.3 | 29 |
| Acknowledgment Rule | Giving | v0.4 | 25F |
| Acknowledgment | Giving | v0.4 | 25G |
| Acknowledgment Run | Giving | v0.4 | 25H |
| Receipt | Giving | v0.4 | 30 |
| Donor Level | Giving | v0.4 | 25A |
| Receipt | Giving | v0.4 | 25A |
| Receipt Number Sequence | Giving | v0.4 | 25B |
| Receipt Run | Giving | v0.4 | 25C |
| Receipt Template | Giving | v0.4 | 25D |
| Donor Level | Giving | v0.4 | 30 |
| Stewardship Plan Template | Giving | v0.4 | 25I |
| Stewardship Plan Step | Giving | v0.4 | 25J |
| Stewardship Plan | Giving | v0.4 | 25K |
| Gift Batch | Giving | v0.5 | 30 |
| Gift Transaction mirror | Connect | v0.6 | 30 |
| Opportunity mirror | Connect | v0.6 | 30 |
| Campaign sync | Connect | v0.6 | 30 |
| Volunteers entities | Volunteers | v0.7 | 30 |
| Programs entities | Programs | v0.8 | 30 |
| Funders entities | Funders | v0.9 | 30 |
| NPSP household adoption | Connect | v0.9 | 30 |
Two rows differ from plan Section 6 because the first customers are now Nonprofit Cloud
and Agentforce Nonprofit orgs: the Gift Transaction mirror is v0.6, brought forward from
v0.9, and NPSP household adoption is v0.9, moved back from v0.6. The plan's roadmap table
is the place that reprioritization is recorded permanently; this table follows it.
| v0.1 | 2026-09-07 | C-03: added the shipped-defaults type Setting Definition (Section 13), which drives the Nonprofit Settings console, and the Nonprofit Settings key `Setup_Steps_Completed__c` (Section 12), which records Setup Assistant progress. |
| v0.1 | 2026-09-07 | C-03, following ADR-0017: added `Settings_Object__c` to Setting Definition, so each package owns its own protected hierarchy custom setting and the console reads and writes any registered one. |
| v0.1 | 2026-09-07 | C-03, following ADR-0020: added `Navigation_Target__c` to Setting Definition, so a module's settings page is reached by navigation while Core's own panels are imported by name. |
| v0.2 | 2026-09-07 | C-12: added the Nonprofit Settings keys that the full Setup Assistant fills in (Section 12): the organization identity keys used on receipts (`Organization_Legal_Name__c`, `Organization_EIN__c`, `Organization_Address__c`, `Receipt_Logo_Document_Id__c`, `Receipt_Signature_Document_Id__c`, `Receipt_Signer_Name__c`, `Receipt_Signer_Title__c`), the giving defaults written only when the Giving module is present (`Default_Fund__c`, `Default_Appeal__c`), and the assistant's own progress keys `Setup_Steps_Skipped__c` and `Setup_Started_At__c`. The v0.2 key planned as `Setup_Assistant_Steps_Complete__c` shipped as `Setup_Steps_Completed__c` plus `Setup_Steps_Skipped__c`. |


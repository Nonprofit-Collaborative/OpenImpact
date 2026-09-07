# Canonical Data Model

**Version:** v0.1
**Status:** governing specification for the v0.1 build
**Last updated:** 2026-09-06

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

This is **v0.1**, covering the entities the v0.1 iteration builds: the constituent
entities and the platform configuration entities that v0.1 features require. Later
iterations extend it. Section 8 lists what is deliberately absent and when it arrives,
so no one adds it early.

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

### Relationships

- **Household to Contact**, one to many, through membership. The mechanism depends on
  the membership mode (see rules below) and is never referenced directly by callers.
- **Household to Household Member**, one to many, in junction mode only.
- Household is the target of the giving rollups defined from v0.2 onward. Those rollup
  target fields are not part of v0.1 and are not listed here.

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
update, delete, undelete, reparent, merge) and counts current members only.

**R-H12 Reparenting and empty households.** Moving a contact to a different household
recalculates both households' member counts and, once Giving is installed, their giving
rollups. The vacated household is deleted when it is empty and
`Delete_Empty_Households__c` is on.

**R-H13 Merge and split.** Two households can be merged (members move to the surviving
household, rollups recalculate, names and greetings recompute unless Custom Name is set)
and a contact can be split out to a new or existing household. Both are front-end
actions on the record page, not Setup operations.

**R-H14 Recompute action.** Changing a naming pattern in the settings console shows a
preview against five sample households and offers a "Recompute all households" batch
with progress and a completion notice. Recomputation never touches households with
Custom Name set.

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
| Account | reference(Household) | conditional | The household, and in Person Account orgs also the person's own Person Account. |
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

**R-M3 One primary.** At most one current member of a household has Is Primary true, and
that member is mirrored to the household's Primary Contact.

**R-M4 Person representation.** Exactly one of Contact or Account identifies the person:
Contact where the person is a Contact, the person's own Person Account where Person
Accounts are enabled. Both empty, or both pointing at people, is invalid.

**R-M5 No direct callers.** All reads and writes go through `HouseholdService`. Feature
code never branches on membership mode.

### Salesforce implementation

- **Object:** `Household_Member__c` (junction).
- **Fields:** `Contact__c` (Lookup to Contact), `Account__c` (Lookup to Account),
  `Role__c` (Picklist: Head, Spouse or Partner, Child, Other), `Is_Primary__c`
  (Checkbox), `Start_Date__c` (Date), `End_Date__c` (Date).

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
| Household | reference(Household) | conditional | The household this person belongs to; in contact mode this is the person's Account. |

### Relationships

- **Contact to Household**, many to one in contact mode (one household per person), many
  to many in junction mode through Household Member.
- **Contact to Organization**, in v0.1 only the platform's own Contact to Account
  reference where an org chooses to relate a person to an organization directly. The
  Affiliation entity that models this properly arrives in v0.3.

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

### Relationships

- **Organization to Contact**, one to many, for people the platform relates to the
  organization. The typed, dated Affiliation entity arrives in v0.3.
- Organizations are donors in their own right from v0.2 onward, where a Gift's donor is
  either a Contact or an Account.

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
- **Fields:** standard `Name`; `Primary_Contact__c` (shared with Household, above).

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
publishing itself fails.

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

### Salesforce implementation

- **Object:** `Automation_Setting__c` with `Automation_Name__c` (Text, external id,
  unique), `Description__c` (Long Text Area), `Enabled__c` (Checkbox),
  `Handler_Class__c` (Text), `Object_Name__c` (Text), `Execution_Order__c` (Number),
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
| Old Value | long text | no | The value before the change, empty when the setting had never been set. |
| New Value | long text | no | The value after the change, empty when the setting was cleared. |
| Changed By | reference(User) | yes | The user who made the change. |
| Changed At | datetime | yes | When the change was saved. |

### Rules

**R-S1** Every write through the settings service produces exactly one Setting Change
record per setting actually changed. Saving a page without changing anything writes
nothing.
**R-S2** Setting Change records are never edited or deleted by packaged code.
**R-S3** Values are stored as text so that any setting type can be audited uniformly.

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

### Automation Registry

`Automation_Registry__mdt`: the catalog of packaged automations, materialized into
Automation Setting records (Section 10) on install and on upgrade.

| Field | Type | Definition |
|---|---|---|
| DeveloperName | text | The stable identifier of the automation, matched to Automation Setting. |
| Label | text | The automation's name as the admin sees it. |
| Description__c | long text | What the automation does, in nonprofit language. |
| Enabled_By_Default__c | boolean | Whether the automation is on when it is first materialized. |
| Handler_Class__c | text | The Apex handler the trigger dispatcher invokes. |
| Object_Name__c | text | The object whose trigger this automation runs on. |
| Execution_Order__c | integer | The order in which handlers run for that object. |

The custom field API names are given here because two of the plain names in the original
draft ("Object" and "Order") are platform reserved words, and because the materialized
`Automation_Setting__c` fields carry the same names (Section 10). v0.1 ships the type with
no records: the first records arrive with feature C-01, which ships the first two trigger
handlers.

### Rule

**R-D1** These lists are the **starting inventory for v0.1** and each feature pull
request may extend them. Any new custom metadata field is added to the tables above
before the metadata file is created.

---

## 14. Deferred to later iterations

These entities exist in the product plan but are deliberately **not** part of v0.1. They
are listed here so that nobody adds them early, and so that the iteration that owns them
is unambiguous. Each will be specified in this document by the iteration that builds it,
before its metadata is created.

| Entity | Package | Iteration | Plan reference |
|---|---|---|---|
| Rollup Definition | Core | v0.2 (C-13) | Section 4.10 |
| Import Template, Import Batch, Import Row | Core | v0.2 (C-14), extended v0.5 (C-19) | Section 4.9 |
| Gift, Gift Allocation, Fund, Appeal | Giving | v0.2 (G-01, G-05) | Section 4.11 |
| Commitment, Installment | Giving | v0.3 (G-07) | Section 4.11 |
| Soft Credit, Tribute | Giving | v0.3 (G-08, G-09) | Section 4.11 |
| Relationship | Core | v0.3 (C-15) | Section 5.1 |
| Affiliation | Core | v0.3 (C-16) | Section 5.1 |
| Address | Core | v0.3 (C-17), seasonal swap v0.4 (C-18) | Section 4.7 |
| Acknowledgment Rule, Receipt | Giving | v0.4 (G-12, G-13) | Section 4.11 |
| Gift Batch | Giving | v0.5 (G-17) | Section 4.11 |

Household giving rollup fields (total giving, first and last gift, largest gift, gift
count, this year, last year, two years ago, pledge balance, soft credit totals) are part
of the Giving package's default rollup definitions in v0.2, not of the v0.1 Household
entity.

---

## 15. Change log

| Version | Date | Change |
|---|---|---|
| v0.1 | 2026-09-06 | Initial model: Household, Household Member, Contact, Organization, plus the platform configuration entities Error Log, Automation Setting, Setting Change, Nonprofit Settings, and the shipped-defaults custom metadata Naming Pattern and Automation Registry. |
| v0.1 | 2026-09-07 | C-05 review fix: Error Log entries are published as `Error_Log_Event__e` (Publish Immediately) and written by a subscriber, so an entry survives the rollback it documents (new rule R-E4). |
| v0.1 | 2026-09-07 | C-04 and C-05 build. Error Log gains Object Name. Automation Setting gains Handler Class, Object Name, Execution Order, and Package Default, all copied from the shipped registry when a record is materialized. Automation Registry field API names fixed ("Object" and "Order" are reserved words). Error Log and Setting Change record names recorded as auto numbers. Nonprofit Settings picklist keys recorded as text, per ADR-0019. |

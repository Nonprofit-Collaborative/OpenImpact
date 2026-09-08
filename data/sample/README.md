# Sample data

## Purpose

Tracked as **C-10** in the product plan: 200 realistic households (440
contacts) and 25 organizations, so a contributor or reviewer can see the product working
immediately, without hand-entering data. Gifts join the set once Giving ships (v0.2).

## Format

The sample set is not a `sf data import tree` plan. It ships as one JSON static resource,
`packages/core/main/default/staticresources/SampleData.json`, loaded and removed inside
the org by Apex (`SampleDataLoader`), so that household and contact records go through the
same triggers a real import would (automatic household naming, greetings, member counts),
and so that "remove sample data" is a single in-app action rather than a manual delete.

`SampleData.json` is generated, not hand-edited. It is produced by
`scripts/data/generate-sample-data.py` (Python 3, standard library only, no dependencies to
install). The generator is deterministic: a fixed random seed means running it again
produces a byte-identical file, so a regenerated file is easy to diff in code review.

The JSON shape:

```json
{
  "households": [
    {
      "key": "H001",
      "name": null,
      "customName": false,
      "anniversary": "1998-06-12",
      "address": { "street": "...", "city": "...", "state": "...", "postalCode": "..." },
      "members": [
        {
          "firstName": "...",
          "lastName": "...",
          "salutation": "Mr.",
          "householdRole": "Head",
          "email": "...@example.org",
          "phone": "...",
          "mailingStreet": "...",
          "mailingCity": "...",
          "mailingState": "...",
          "mailingPostalCode": "...",
          "birthdate": "1975-03-02",
          "preferredName": "...",
          "deceased": false
        }
      ]
    }
  ],
  "organizations": [{ "key": "O001", "name": "...", "type": "church", "website": "...", "phone": "..." }]
}
```

`name` is `null` for every household except the roughly three with `customName: true`
(and the staff household), because household name, formal greeting, and informal greeting
are computed by the household naming trigger, not by the sample data set, exactly as a
real import would produce them (canonical model Section 5, rule R-H4). Custom-name
households carry the name directly, matching `Custom_Name__c` behavior (rule R-H8).

The set deliberately includes: households sharing a surname and households with differing
surnames, a few hyphenated surnames, single-person households, about ten
three-generation households, five households with a deceased member, three households
with a custom name (for example "The Reverend and Mrs. Alvarez"), one household guaranteed
to be "The Garcia Family" (used by the admin guide's walkthrough), and one "Staff
Household" containing Maria, David, Priya, Tom, Jen, and Sam so the personas are always
findable in a freshly loaded org. Mailing addresses spread across a dozen US states.

## Regeneration

Change the generator, then run:

```bash
python3 scripts/data/generate-sample-data.py
```

This overwrites `packages/core/main/default/staticresources/SampleData.json` in place.
Commit the regenerated file alongside the generator change. The script prints household,
contact, and organization counts and the resulting file size (kept under 400 KB) so a
change that grows the set unexpectedly is caught at generation time, not in review.

## Loading and removing

`SampleDataLoader.load()` (Apex) reads the static resource, inserts households and
organizations first (record types by DeveloperName, `Sample_Data__c` true), then contacts
in chunks, all flagged `Sample_Data__c` true. `SampleDataLoader.remove()` deletes every
record carrying that flag. Both are exposed to admins through **Nonprofit Settings > Sample
Data** (`sampleDataManager` LWC); see `docs/admin-guide/sample-data.md`.
`scripts/org/seed-sample-data.sh` runs the load from the command line for contributors
setting up a scratch org.

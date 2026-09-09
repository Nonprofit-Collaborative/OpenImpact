#!/usr/bin/env python3
"""Checks that every checkbox setting which ships switched on is actually switched on.

A checkbox field can declare `<defaultValue>true</defaultValue>`. That default is what the
platform applies when a record is created through the user interface. It is not what Apex
reads: `Nonprofit_Settings__c.getOrgDefaults()` on an org that has never saved its settings
returns a materialized record with every checkbox false, not null and not the declared
default. So a feature guarded by such a setting does nothing at all on every fresh install,
raises nothing, and logs nothing.

That is not hypothetical. C-15 shipped the relationship reciprocal upkeep behind
`Relationship_Auto_Reciprocal__c`, whose metadata and admin guide both say it ships on. The
first org run this project ever had found thirteen failures, every count exactly half of what
was expected, because the other side of a relationship was never written. No offline check
could see it: the field metadata was right, the Apex compiled, and the assumption that joined
them was invisible.

The gate: a checkbox on a hierarchy custom setting that declares a default of true has to be
registered in `SHIPPED_DEFAULTS` in SettingsService, which puts the value on the record for an
org that has never saved one, or be listed in KNOWN_UNREGISTERED below with a reason. The
listed ones are also checked, so an entry cannot outlive the field it excuses.
"""

import glob
import os
import re
import sys
import xml.etree.ElementTree as ET

NS = "http://soap.sforce.com/2006/04/metadata"
SETTINGS_SERVICE = "packages/core/main/default/classes/SettingsService.cls"
CORE_SETTINGS = "Nonprofit_Settings__c"

# Checkboxes that ship on and are deliberately not registered, with the reason. An entry here
# says the shipped default is not applied for that field today: it is a known gap, recorded
# rather than hidden, and it is checked, so it cannot name a field that no longer qualifies.
KNOWN_UNREGISTERED = {
    (
        "Nonprofit_Settings__c",
        "Auto_Create_Households__c",
    ): "HouseholdService.ensureHouseholds reads it as '!= true', so a fresh org gets the "
    "opposite of the shipped default. Registering it turns household creation on for every "
    "test class that never saves settings, and no org run has measured that yet, so it "
    "belongs to the household cluster rather than to C-15.",
    (
        "Nonprofit_Settings__c",
        "Delete_Empty_Households__c",
    ): "HouseholdService.deleteEmptyHouseholds reads it as '!= true'. Same cluster, same "
    "reason as Auto_Create_Households__c.",
    (
        "Giving_Settings__c",
        "Auto_Apply_Gifts_To_Installments__c",
    ): "A module settings object is read through SettingsService.getValue, which returns null "
    "rather than false while no record exists, and CommitmentService.autoApplyGifts treats "
    "null as on. The gap reopens once a record is created for some other key, and closing it "
    "needs the same mechanism on the module read path.",
    (
        "Giving_Settings__c",
        "Automatic_Household_Soft_Credits__c",
    ): "Read through SettingsService.getValue by SoftCreditService."
    "automaticHouseholdCreditsEnabled, which treats null as on. Same gap as "
    "Auto_Apply_Gifts_To_Installments__c.",
}


def q(tag):
    return f"{{{NS}}}{tag}"


def text_of(element, tag):
    child = element.find(q(tag))
    return (child.text or "").strip() if child is not None and child.text else ""


def hierarchy_setting_objects():
    """Every hierarchy custom setting object in the repository, as (object name, fields dir)."""
    found = []
    for path in sorted(glob.glob("packages/*/main/default/objects/*/*.object-meta.xml")):
        root = ET.parse(path).getroot()
        if text_of(root, "customSettingsType") != "Hierarchy":
            continue
        directory = os.path.dirname(path)
        found.append((os.path.basename(directory), os.path.join(directory, "fields")))
    return found


def ships_on(fields_dir):
    """The checkbox fields in one settings object that declare a default of true."""
    on = []
    for path in sorted(glob.glob(os.path.join(fields_dir, "*.field-meta.xml"))):
        root = ET.parse(path).getroot()
        if text_of(root, "type") != "Checkbox":
            continue
        if text_of(root, "defaultValue").lower() != "true":
            continue
        on.append(text_of(root, "fullName"))
    return on


def registered_defaults(source):
    """The (object, field) pairs registered in SettingsService.SHIPPED_DEFAULTS."""
    match = re.search(
        r"SHIPPED_DEFAULTS\s*=\s*new\s+Map<Schema\.SObjectField,\s*Boolean>\s*\{(.*?)\}",
        source,
        re.DOTALL,
    )
    if match is None:
        return None
    pairs = {}
    for object_name, field_name, value in re.findall(
        r"(\w+__c)\.(\w+__c)\s*=>\s*(true|false)", match.group(1)
    ):
        pairs[(object_name, field_name)] = value == "true"
    return pairs


def main():
    if not os.path.exists(SETTINGS_SERVICE):
        print(f"{SETTINGS_SERVICE} is missing, so the shipped defaults cannot be read.")
        return 1
    with open(SETTINGS_SERVICE, encoding="utf-8") as handle:
        registered = registered_defaults(handle.read())
    if registered is None:
        print(
            "SettingsService no longer declares a SHIPPED_DEFAULTS map of "
            "Schema.SObjectField to Boolean. That map is what puts a shipped default on an "
            "org that has never saved its settings; without it every checkbox that ships on "
            "reads off on a fresh install."
        )
        return 1

    problems = []
    checked = 0
    declared = set()

    for object_name, fields_dir in hierarchy_setting_objects():
        for field_name in ships_on(fields_dir):
            checked += 1
            key = (object_name, field_name)
            declared.add(key)
            if key in registered:
                if not registered[key]:
                    problems.append(
                        f"{object_name}.{field_name}: the field ships on, but SettingsService "
                        f"registers it as false. The two have to agree."
                    )
                continue
            if key in KNOWN_UNREGISTERED:
                continue
            registerable = object_name == CORE_SETTINGS
            problems.append(
                f"{object_name}.{field_name} declares defaultValue true, but Apex never sees "
                f"that default: getOrgDefaults() returns false for it until the org saves its "
                f"settings, so whatever this setting guards does nothing on a fresh install "
                + (
                    "and says nothing about it. Register it in SettingsService.SHIPPED_DEFAULTS."
                    if registerable
                    else "and says nothing about it. A module settings object has no shipped "
                    "default mechanism yet, so add one or list the field in "
                    "KNOWN_UNREGISTERED in this script with the reason."
                )
            )

    for key in sorted(KNOWN_UNREGISTERED):
        if key not in declared:
            problems.append(
                f"{key[0]}.{key[1]} is listed in KNOWN_UNREGISTERED but is no longer a checkbox "
                f"that ships on. Remove the entry."
            )

    for key in sorted(registered):
        if key not in declared:
            problems.append(
                f"{key[0]}.{key[1]} is registered in SettingsService.SHIPPED_DEFAULTS but its "
                f"field metadata does not declare defaultValue true. The console, the admin "
                f"guide and the code all read that metadata as the shipped default, so they "
                f"have to agree."
            )

    if problems:
        print("Settings that ship on but would read off:")
        for problem in problems:
            print(f"  - {problem}")
        print("")
        print(
            "Background: a hierarchy custom setting read through getOrgDefaults() comes back "
            "materialized, with every checkbox false, not null. See ADR-0035."
        )
        return 1

    print(
        f"Checked {checked} checkbox settings that ship switched on: "
        f"{len(registered)} registered, {len(KNOWN_UNREGISTERED)} recorded as known gaps."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

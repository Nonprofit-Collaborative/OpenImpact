#!/usr/bin/env python3
"""Checks that every permission set grants access to metadata that exists.

A permission set naming a class, tab, application, object, field or custom permission that
the packages do not ship fails the whole deployment with a component error. Nothing else in
the check suite sees it: the offline Apex compiler does not read permission sets, and the
canonical model check reads objects and fields rather than who is granted them.

This ran because Nonprofit_Admin granted a Household_Member__c tab that had never been
created. The integration contract asked for that tab, the grant was added, and the tab was
not, so the permission set had been undeployable for as long as it had existed.

The permission sets are assembled by hand at each merge from the integration files, which is
exactly the process that produces this mistake, so it is worth a gate rather than care.

Standard objects and fields are not checked: they exist in the org rather than in this
repository. Only custom API names, which end in __c, are resolved against the packages.
"""

import glob
import os
import sys
import xml.etree.ElementTree as ET

NS = "http://soap.sforce.com/2006/04/metadata"


def q(tag):
    return f"{{{NS}}}{tag}"


def exists(pattern):
    return bool(glob.glob(pattern))


def check(path):
    """Every dangling reference in one permission set, as readable lines."""
    name = os.path.basename(path).replace(".permissionset-meta.xml", "")
    root = ET.parse(path).getroot()
    problems = []

    def report(kind, value):
        problems.append(f"{name}: {kind} {value}, which no package ships")

    for entry in root.findall(q("classAccesses")):
        value = entry.find(q("apexClass")).text
        if not exists(f"packages/*/main/default/classes/{value}.cls"):
            report("grants Apex class", value)

    for entry in root.findall(q("tabSettings")):
        value = entry.find(q("tab")).text
        if not exists(f"packages/*/main/default/tabs/{value}.tab-meta.xml"):
            report("grants tab", value)

    for entry in root.findall(q("applicationVisibilities")):
        value = entry.find(q("application")).text
        if not exists(f"packages/*/main/default/applications/{value}.app-meta.xml"):
            report("grants application", value)

    for entry in root.findall(q("customPermissions")):
        value = entry.find(q("name")).text
        if not exists(f"packages/*/main/default/customPermissions/{value}.customPermission-meta.xml"):
            report("grants custom permission", value)

    for entry in root.findall(q("objectPermissions")):
        value = entry.find(q("object")).text
        if value.endswith("__c") and not exists(f"packages/*/main/default/objects/{value}"):
            report("grants object", value)

    for entry in root.findall(q("recordTypeVisibilities")):
        value = entry.find(q("recordType")).text
        obj, _, record_type = value.partition(".")
        if obj.endswith("__c") or exists(f"packages/*/main/default/objects/{obj}"):
            if not exists(
                f"packages/*/main/default/objects/{obj}/recordTypes/{record_type}.recordType-meta.xml"
            ):
                report("grants record type", value)

    for entry in root.findall(q("fieldPermissions")):
        value = entry.find(q("field")).text
        obj, _, field = value.partition(".")
        if field.endswith("__c") and not exists(
            f"packages/*/main/default/objects/{obj}/fields/{field}.field-meta.xml"
        ):
            report("grants field", value)

    return problems


def main():
    paths = sorted(glob.glob("packages/*/main/default/permissionsets/*.permissionset-meta.xml"))
    problems = []
    for path in paths:
        problems.extend(check(path))

    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(
            f"check-permission-sets.py: FAILED, {len(problems)} dangling reference(s) above",
            file=sys.stderr,
        )
        return 1

    print(f"check-permission-sets.py: OK, {len(paths)} permission sets grant only what exists")
    return 0


if __name__ == "__main__":
    sys.exit(main())

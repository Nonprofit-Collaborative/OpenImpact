#!/usr/bin/env python3
"""Checks that every Learn more link in the Settings console points at a page that exists.

A Setting Definition record carries `Help_Path__c`, and SettingsController turns it into a
URL by appending it to a base that already ends in `docs/admin-guide/`. A row that stores
`admin-guide/access.md` rather than `access.md` therefore produces
`docs/admin-guide/admin-guide/access.md`, which is a 404.

That is what twelve of the thirty four shipped rows did. Nothing catches it: the value is a
string, so it deploys, and the link is only wrong once an administrator clicks it, in an org,
looking for help. This is the cheapest possible gate for a defect whose whole cost falls on
the person the feature exists for.

Checks two things: the value is a bare file name, not a path that repeats the directory, and
the file it names is actually in docs/admin-guide.
"""

import glob
import os
import sys
import xml.etree.ElementTree as ET

NS = "http://soap.sforce.com/2006/04/metadata"
GUIDE_DIR = "docs/admin-guide"


def q(tag):
    return f"{{{NS}}}{tag}"


def help_path(path):
    """The Help_Path__c value in one custom metadata record, or None."""
    root = ET.parse(path).getroot()
    for values in root.findall(q("values")):
        field = values.find(q("field"))
        if field is not None and (field.text or "").strip() == "Help_Path__c":
            value = values.find(q("value"))
            return (value.text or "").strip() if value is not None else ""
    return None


def main():
    paths = sorted(
        glob.glob("packages/*/main/default/customMetadata/Setting_Definition.*.md-meta.xml")
    )
    problems = []
    checked = 0

    for path in paths:
        name = os.path.basename(path).replace("Setting_Definition.", "").replace(
            ".md-meta.xml", ""
        )
        value = help_path(path)
        if not value:
            continue
        checked += 1
        if "/" in value:
            problems.append(
                f"{name}: Help_Path__c is '{value}', which SettingsController appends to a base "
                f"already ending in {GUIDE_DIR}/. Store just the file name."
            )
            continue
        if not os.path.isfile(os.path.join(GUIDE_DIR, value)):
            problems.append(f"{name}: Help_Path__c names {GUIDE_DIR}/{value}, which does not exist")

    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(
            f"check-help-links.py: FAILED, {len(problems)} broken Learn more link(s) above",
            file=sys.stderr,
        )
        return 1

    print(f"check-help-links.py: OK, {checked} Learn more links point at a page that exists")
    return 0


if __name__ == "__main__":
    sys.exit(main())

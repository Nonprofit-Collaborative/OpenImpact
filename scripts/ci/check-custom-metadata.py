#!/usr/bin/env python3
"""Checks every shipped custom metadata record against its type definition.

A record that names a field the type does not define deploys nowhere: the
metadata API refuses the whole deployment. The offline Apex compiler does not
see custom metadata records, so nothing else in the check suite catches it.
This ran because three Automation Registry records reached main naming
Default_Enabled__c, a field that belongs to Naming Pattern, not to that type.

It also checks the other half of a Setting Definition row whose Data_Type__c is
Component: the settings console can only render a component it names in its own
import switch, because dynamic imports must be statically analyzable. A row
naming a component the console does not import deploys cleanly and then shows
"not installed" to the administrator, which is a defect only a person opening
that page in an org would ever see.
"""

import glob
import os
import re
import sys

FIELD = re.compile(r"<field>([^<]+)</field>")
VALUE_FOR = (
    lambda field: re.compile(
        r"<field>" + field + r"</field>\s*<value[^>]*>([^<]*)</value>", re.DOTALL
    )
)
CONSOLE = "packages/core/main/default/lwc/settingsConsole/settingsConsole.js"
CONSOLE_CASE = re.compile(r"case '([A-Za-z0-9_]+)':")


def type_definitions():
    """Every custom metadata type in the repo, by name without the __mdt suffix."""
    return {
        os.path.basename(path)[: -len("__mdt")]: path
        for path in glob.glob("packages/*/main/default/objects/*__mdt")
    }


def defined_fields(type_path):
    return {
        os.path.basename(path)[: -len(".field-meta.xml")]
        for path in glob.glob(f"{type_path}/fields/*.field-meta.xml")
    }


def value_of(text, field):
    """The value of one field in a custom metadata record, or None."""
    found = VALUE_FOR(field).search(text)
    return found.group(1).strip() if found else None


def console_components():
    """Every component name the settings console can actually import."""
    return set(CONSOLE_CASE.findall(open(CONSOLE, encoding="utf-8").read()))


def check_console_components(problems):
    """Every Component setting row names a component the console imports."""
    importable = console_components()
    for record in sorted(
        glob.glob("packages/core/main/default/customMetadata/Setting_Definition.*.md-meta.xml")
    ):
        text = open(record, encoding="utf-8").read()
        if value_of(text, "Data_Type__c") != "Component":
            continue
        component = value_of(text, "Component__c")
        if not component:
            # A Component row with no component navigates away instead, which is ADR-0020.
            continue
        if component not in importable:
            problems.append(
                f"{record}: names the component {component}, which settingsConsole.js "
                "does not import, so the settings console would show it as not installed"
            )


def main():
    types = type_definitions()
    problems = []
    checked = 0

    for record in sorted(glob.glob("packages/*/main/default/customMetadata/*.md-meta.xml")):
        type_name = os.path.basename(record).split(".")[0]
        type_path = types.get(type_name)
        if type_path is None:
            problems.append(f"{record}: no {type_name}__mdt definition in any package")
            continue
        fields = defined_fields(type_path)
        checked += 1
        for named in FIELD.findall(open(record, encoding="utf-8").read()):
            if named not in fields:
                problems.append(f"{record}: names {named}, which {type_name}__mdt does not define")

    check_console_components(problems)

    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(f"check-custom-metadata.py: FAILED, {len(problems)} problem(s) above", file=sys.stderr)
        return 1
    print(f"check-custom-metadata.py: OK, {checked} records match their type")
    return 0


if __name__ == "__main__":
    sys.exit(main())

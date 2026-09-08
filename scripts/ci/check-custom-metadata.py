#!/usr/bin/env python3
"""Checks every shipped custom metadata record against its type definition.

A record that names a field the type does not define deploys nowhere: the
metadata API refuses the whole deployment. The offline Apex compiler does not
see custom metadata records, so nothing else in the check suite catches it.
This ran because three Automation Registry records reached main naming
Default_Enabled__c, a field that belongs to Naming Pattern, not to that type.
"""

import glob
import os
import re
import sys

FIELD = re.compile(r"<field>([^<]+)</field>")


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

    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(f"check-custom-metadata.py: FAILED, {len(problems)} problem(s) above", file=sys.stderr)
        return 1
    print(f"check-custom-metadata.py: OK, {checked} records match their type")
    return 0


if __name__ == "__main__":
    sys.exit(main())

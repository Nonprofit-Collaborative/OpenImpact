#!/usr/bin/env python3
"""Checks that the decision records and their index agree with each other.

Three things, all of which have gone wrong here:

Every ADR file's number matches the number in its own heading. Parallel branches pick the
next free ADR number at the same time and collide, so renumbering at merge is routine, and a
renumber that renames the file but not the heading leaves a document that disagrees with
itself.

Every ADR is listed in the index, and every link in the index resolves. ADR-0024 was written
and never indexed, which is how the next author picks a number that is already taken.

No two ADRs share a number. That is the collision itself, and it is silent: both files exist,
both are valid markdown, and the second one to be read wins whatever argument they disagree
on.

Body references (ADR-0025 cited inside a paragraph) are not checked. A renumber has to fix
those by hand, and the temptation is a blanket search and replace across a file that cites
several ADRs, which is how a correct citation gets rewritten to a wrong one. This gate does
not catch that; reading the diff does.
"""

import glob
import os
import re
import sys

DECISIONS = "docs/architecture/decisions"
TEMPLATE = "0000-adr-template.md"
LINK = re.compile(r"\]\((0\d{3}-[a-z0-9.-]+\.md)\)")
HEADING = re.compile(r"^# ADR-(\d{4}):")


def main():
    paths = sorted(glob.glob(f"{DECISIONS}/0*.md"))
    index_path = os.path.join(DECISIONS, "README.md")
    if not os.path.isfile(index_path):
        print(f"check-adrs.py: FAILED, no index at {index_path}", file=sys.stderr)
        return 1

    problems = []
    by_number = {}

    for path in paths:
        name = os.path.basename(path)
        if name == TEMPLATE:
            continue
        number = name[:4]
        by_number.setdefault(number, []).append(name)
        first_line = ""
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                if line.strip():
                    first_line = line.rstrip("\n")
                    break
        match = HEADING.match(first_line)
        if not match:
            problems.append(f"{name}: first line is not a '# ADR-NNNN: ...' heading")
        elif match.group(1) != number:
            problems.append(
                f"{name}: the file is {number} and the heading says {match.group(1)}. "
                "A renumber renamed the file and not the heading."
            )

    for number, names in sorted(by_number.items()):
        if len(names) > 1:
            problems.append(f"ADR-{number} is used by more than one file: {', '.join(sorted(names))}")

    with open(index_path, encoding="utf-8") as handle:
        index = handle.read()
    linked = set(LINK.findall(index))

    for target in sorted(linked):
        if not os.path.isfile(os.path.join(DECISIONS, target)):
            problems.append(f"the index links {target}, which does not exist")

    shipped = {os.path.basename(p) for p in paths} - {TEMPLATE}
    for missing in sorted(shipped - linked):
        problems.append(f"{missing} is not listed in the index")

    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(f"check-adrs.py: FAILED, {len(problems)} problem(s) above", file=sys.stderr)
        return 1

    print(f"check-adrs.py: OK, {len(shipped)} decision records numbered and indexed consistently")
    return 0


if __name__ == "__main__":
    sys.exit(main())

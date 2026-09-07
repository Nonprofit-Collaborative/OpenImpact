# Sample data

## Purpose

Tracked as **C-10** in the product plan: roughly 200 realistic households (contacts,
households, addresses, and gifts once Giving ships) so a contributor or reviewer can see the
product working immediately, without hand-entering data.

## Format

A `sf data import tree` plan (`data/sample/plan.json`) referencing per-object JSON data files in
this directory, following the standard SFDX data-tree format. `scripts/org/seed-sample-data.sh`
runs `sf data import tree --plan data/sample/plan.json` when the plan exists.

## Status

Not yet populated. Until `plan.json` exists, `seed-sample-data.sh` prints
`sample data not yet available (C-10)` and exits successfully rather than failing.

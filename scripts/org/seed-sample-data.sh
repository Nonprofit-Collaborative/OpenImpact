#!/usr/bin/env bash
# seed-sample-data.sh <alias>
#
# Loads sample data into the target org, if a sample data plan exists yet (tracked as C-10 in
# the product plan: 200 realistic households). Safe to call before the plan exists; it just
# prints a note and exits successfully so callers (create-scratch-org.sh) do not fail.

set -euo pipefail

ALIAS="${1:-}"

if [[ -z "$ALIAS" ]]; then
  echo "Usage: seed-sample-data.sh <org-alias>" >&2
  exit 1
fi

PLAN_FILE="data/sample/plan.json"

if [[ -f "$PLAN_FILE" ]]; then
  echo "Loading sample data from ${PLAN_FILE} into ${ALIAS}..."
  sf data import tree --plan "$PLAN_FILE" --target-org "$ALIAS"
else
  echo "sample data not yet available (C-10)"
fi

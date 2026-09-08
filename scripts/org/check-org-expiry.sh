#!/usr/bin/env bash
# check-org-expiry.sh <alias>
#
# Prints how many days the org has left and warns as expiry approaches.
#
# The test org is a scratch org, and Salesforce caps a scratch org at 30 days and deletes it
# on the day it expires. When that happens, continuous integration stops being able to log in
# and every run fails at authentication, which looks like a broken build rather than a diary
# entry that came due. So the number of days left is printed on every run, and a warning
# starts a week out.
#
# Exit codes: 0 always. This reports; it does not fail a build.

set -uo pipefail

ALIAS="${1:-testorg}"

EXPIRY="$(sf org display --target-org "$ALIAS" --json 2>/dev/null |
  python3 -c 'import json,sys; print(json.load(sys.stdin)["result"].get("expirationDate") or "")' 2>/dev/null || true)"

if [[ -z "$EXPIRY" ]]; then
  echo "Org '${ALIAS}' reports no expiry date. If it is a Developer Edition org that is"
  echo "correct and it never expires. If it is a scratch org, something is wrong."
  exit 0
fi

TODAY="$(date -u +%Y-%m-%d)"
DAYS_LEFT="$(python3 - "$EXPIRY" "$TODAY" <<'PY'
import sys
from datetime import date
expiry = date.fromisoformat(sys.argv[1][:10])
today = date.fromisoformat(sys.argv[2])
print((expiry - today).days)
PY
)"

echo "Test org '${ALIAS}' expires on ${EXPIRY} (${DAYS_LEFT} days left)."

if (( DAYS_LEFT <= 0 )); then
  echo "::error::The test org has expired. Recreate it and replace the SF_TEST_ORG_AUTH_URL secret. See docs/contributor-guide/ci.md."
elif (( DAYS_LEFT <= 7 )); then
  echo "::warning::The test org expires in ${DAYS_LEFT} days. Refresh it with scripts/org/create-scratch-org.sh person-accounts dev --days 30 --replace and replace the SF_TEST_ORG_AUTH_URL secret before then."
fi

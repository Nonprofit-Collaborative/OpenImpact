#!/usr/bin/env bash
# seed-sample-data.sh <alias>
#
# Loads the C-10 sample data set (about 200 households, roughly 430 contacts, and 25
# organizations) into the target org and waits for it to finish.
#
# SampleDataLoader.load() runs as a chain of queueable jobs (see
# packages/core/main/default/classes/SampleDataLoadQueueable.cls), so it returns as soon
# as the first job is queued, not once loading is done. There is no way to poll Apex
# state (SampleDataLoader.status()) from a shell script, so instead this polls the
# number of Household Accounts flagged Sample_Data__c until it reaches the expected
# count or 3 minutes pass, printing progress along the way. See
# docs/admin-guide/sample-data.md and data/sample/README.md.
#
# Safe to call before scripts/org/load-sample-data.apex exists; it just prints a note
# and exits successfully so callers (create-scratch-org.sh) do not fail.

set -euo pipefail

ALIAS="${1:-}"

if [[ -z "$ALIAS" ]]; then
  echo "Usage: seed-sample-data.sh <org-alias>" >&2
  exit 1
fi

APEX_FILE="scripts/org/load-sample-data.apex"
EXPECTED_HOUSEHOLDS=200
POLL_INTERVAL_SECONDS=5
MAX_WAIT_SECONDS=180

if [[ ! -f "$APEX_FILE" ]]; then
  echo "sample data not yet available (C-10)"
  exit 0
fi

echo "Starting the sample data load in ${ALIAS} (runs in the background as a queueable chain)..."
sf apex run --target-org "$ALIAS" --file "$APEX_FILE"

echo "Waiting for households flagged Sample_Data__c to reach ${EXPECTED_HOUSEHOLDS} (up to ${MAX_WAIT_SECONDS}s)..."

ELAPSED=0
while [[ "$ELAPSED" -lt "$MAX_WAIT_SECONDS" ]]; do
  COUNT_JSON="$(sf data query \
    --target-org "$ALIAS" \
    --query "SELECT COUNT() FROM Account WHERE Sample_Data__c = true AND RecordType.DeveloperName = 'Household'" \
    --json)"
  COUNT="$(echo "$COUNT_JSON" | node -e "
    let data = '';
    process.stdin.on('data', (chunk) => { data += chunk; });
    process.stdin.on('end', () => {
      try {
        console.log(JSON.parse(data).result.totalSize);
      } catch (e) {
        console.log(0);
      }
    });
  ")"

  echo "  ${COUNT} / ${EXPECTED_HOUSEHOLDS} households loaded (${ELAPSED}s elapsed)"

  if [[ "$COUNT" -ge "$EXPECTED_HOUSEHOLDS" ]]; then
    echo "Sample data load complete."
    exit 0
  fi

  sleep "$POLL_INTERVAL_SECONDS"
  ELAPSED=$((ELAPSED + POLL_INTERVAL_SECONDS))
done

echo "Sample data load did not finish within ${MAX_WAIT_SECONDS}s." >&2
echo "Check Setup > Apex Jobs, or open Nonprofit Settings > Sample Data in the org, for progress." >&2
exit 1

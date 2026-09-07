#!/usr/bin/env bash
# delete-scratch-org.sh <alias>
#
# Deletes the named scratch org.

set -euo pipefail

ALIAS="${1:-}"

if [[ -z "$ALIAS" ]]; then
  echo "Usage: delete-scratch-org.sh <alias>" >&2
  exit 1
fi

echo "Deleting scratch org '${ALIAS}'..."
sf org delete scratch --target-org "$ALIAS" --no-prompt

echo "Deleted '${ALIAS}'."

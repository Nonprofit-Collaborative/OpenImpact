#!/usr/bin/env bash
# create-scratch-org.sh <shape> [alias] [--days N] [--no-sample-data]
#
# Creates a scratch org of the given shape, deploys Core, assigns Core's permission sets, and
# (for the platform-only shape) verifies that a Salesforce Platform license user can use every
# packaged permission set. See docs/contributor-guide/scratch-orgs.md for the full explanation.
#
# Shapes (see config/scratch-defs/):
#   platform-only     Developer edition, no Sales/Service objects available to the org's
#                      standard users. See the PLATFORM-ONLY VERIFICATION comment below for why
#                      this shape needs an extra check that the others do not.
#   sales-cloud        Enterprise edition, standard Sales Cloud objects available.
#   npsp                Enterprise edition, NPSP installed on top (scripts/org/install-npsp.sh).
#   person-accounts     Enterprise edition with Person Accounts enabled.

set -euo pipefail

usage() {
  echo "Usage: create-scratch-org.sh <shape> [alias] [--days N] [--no-sample-data]" >&2
  echo "  shape: platform-only | sales-cloud | npsp | person-accounts" >&2
  exit 1
}

SHAPE="${1:-}"
[[ -z "$SHAPE" ]] && usage
shift || true

ALIAS=""
DAYS=7
LOAD_SAMPLE_DATA=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --days)
      DAYS="${2:-7}"
      shift 2
      ;;
    --no-sample-data)
      LOAD_SAMPLE_DATA=0
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      ;;
    *)
      if [[ -z "$ALIAS" ]]; then
        ALIAS="$1"
        shift
      else
        echo "Unexpected argument: $1" >&2
        usage
      fi
      ;;
  esac
done

DEF_FILE="config/scratch-defs/${SHAPE}.json"
if [[ ! -f "$DEF_FILE" ]]; then
  echo "Unknown shape '${SHAPE}'. Expected one of: platform-only, sales-cloud, npsp, person-accounts" >&2
  echo "(no scratch-def file found at ${DEF_FILE})" >&2
  exit 1
fi

if [[ -z "$ALIAS" ]]; then
  ALIAS="openimpact-${SHAPE}"
fi

echo "== Creating scratch org: shape=${SHAPE} alias=${ALIAS} days=${DAYS} =="
sf org create scratch \
  --definition-file "$DEF_FILE" \
  --alias "$ALIAS" \
  --duration-days "$DAYS" \
  --set-default \
  --wait 15

if [[ "$SHAPE" == "npsp" ]]; then
  echo "== Installing NPSP (shape=npsp) =="
  scripts/org/install-npsp.sh "$ALIAS"
fi

echo "== Deploying Core to ${ALIAS} =="
sf project deploy start --source-dir packages/core --wait 30 --ignore-conflicts --target-org "$ALIAS"

echo "== Assigning Core permission sets to the default (deployment) user =="
PERMSET_DIR="packages/core/main/default/permissionsets"
FOUND_PERMSET=0
if [[ -d "$PERMSET_DIR" ]]; then
  for PS_FILE in "$PERMSET_DIR"/*.permissionset-meta.xml; do
    [[ -e "$PS_FILE" ]] || continue
    FOUND_PERMSET=1
    PS_NAME="$(basename "$PS_FILE" .permissionset-meta.xml)"
    echo "Assigning permission set: ${PS_NAME}"
    sf org assign permset --name "$PS_NAME" --target-org "$ALIAS"
  done
fi
if [[ "$FOUND_PERMSET" -eq 0 ]]; then
  echo "no permission sets yet"
fi

# PLATFORM-ONLY VERIFICATION
#
# Scratch orgs always provision Sales Cloud objects regardless of the requested edition or
# features; there is no scratch-org setting that removes them. So the platform-only shape
# cannot be verified simply by inspecting what exists in the org. Instead we verify it two ways:
#   (a) a CI static check (scripts/ci/check-standard-objects.sh) that fails if any file under
#       packages/core (or any other non-Connect package) references a Sales/Service/Industries
#       object, so the source itself never depends on what a real Platform-only org lacks; and
#   (b) here, at org-creation time for the platform-only shape only: we create a user with the
#       "Salesforce Platform" user license and the "Standard Platform User" profile, then assign
#       every Core permission set to that user. The "Standard Platform User" profile cannot see
#       Sales/Service objects, so if any Core permission set grants access to an object that
#       license cannot see, the assignment fails loudly, which is exactly the signal we want.
if [[ "$SHAPE" == "platform-only" ]]; then
  echo "== Platform-only license check: creating Standard Platform User =="
  PLATFORM_USER_DEF="$(mktemp)"
  sed "s/<alias>/${ALIAS}/g" config/users/platform-user.json > "$PLATFORM_USER_DEF"
  sf org create user --definition-file "$PLATFORM_USER_DEF" --target-org "$ALIAS"
  rm -f "$PLATFORM_USER_DEF"

  PLATFORM_USERNAME="platformuser@${ALIAS}.openimpact.test"

  if [[ "$FOUND_PERMSET" -eq 1 ]]; then
    for PS_FILE in "$PERMSET_DIR"/*.permissionset-meta.xml; do
      [[ -e "$PS_FILE" ]] || continue
      PS_NAME="$(basename "$PS_FILE" .permissionset-meta.xml)"
      echo "Assigning ${PS_NAME} to ${PLATFORM_USERNAME} (Standard Platform User license check)"
      sf org assign permset --name "$PS_NAME" --target-org "$ALIAS" --on-behalf-of "$PLATFORM_USERNAME"
    done
  else
    echo "no permission sets yet; skipping Standard Platform User assignment check"
  fi
fi

if [[ "$LOAD_SAMPLE_DATA" -eq 1 ]]; then
  echo "== Seeding sample data =="
  scripts/org/seed-sample-data.sh "$ALIAS"
else
  echo "Skipping sample data (--no-sample-data)."
fi

echo "== Done =="
echo "Open the org with: sf org open --target-org ${ALIAS}"

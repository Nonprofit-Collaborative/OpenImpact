#!/usr/bin/env bash
# deploy-packages.sh <alias> [--core-only]
#
# Deploys the packages to an org in stages, smallest blast radius first.
#
# WHY IN STAGES. The first deploy this project ever attempted sent all 982 components in one
# request and came back with UNKNOWN_EXCEPTION, zero components deployed, zero component
# errors, and a Salesforce ErrorId. A failure with no component attached tells you nothing
# about which of 982 things caused it. Deploying the vendored tree separately from Open
# Impact's own source, and Core before Giving, means the next such failure names a stage.
#
# It also matches how the packages actually depend on each other: the vendored engine is
# self contained, Core does not call it yet, and Giving depends on Core.
#
# Exit codes: 0 = every stage deployed, non-zero = the first stage that failed.

set -uo pipefail

ALIAS="${1:-}"
if [[ -z "$ALIAS" ]]; then
  echo "Usage: deploy-packages.sh <alias> [--core-only]" >&2
  exit 1
fi
shift || true

CORE_ONLY=0
[[ "${1:-}" == "--core-only" ]] && CORE_ONLY=1

# Deploy one directory, and on failure ask the org what actually went wrong. A deploy can
# report only "Status: Failed" with no detail, which is why the report is asked for by job
# id and then again as JSON: the JSON carries errorMessage and every component error.
deploy_stage() {
  local label="$1"
  local dir="$2"

  if [[ ! -d "$dir" ]]; then
    echo "== Skipping ${label}: ${dir} does not exist =="
    return 0
  fi

  echo ""
  echo "== Deploying ${label} (${dir}) to ${ALIAS} =="
  local log status job_id
  log="$(mktemp)"
  sf project deploy start --source-dir "$dir" --wait 30 --ignore-conflicts --target-org "$ALIAS" 2>&1 | tee "$log"
  status="${PIPESTATUS[0]}"

  if [[ "$status" -ne 0 ]]; then
    echo ""
    echo "== ${label} failed. Asking the org for the component level detail =="
    job_id="$(grep -oE 'Deploy ID: [0-9A-Za-z]+' "$log" | head -1 | awk '{print $3}')"
    if [[ -n "$job_id" ]]; then
      sf project deploy report --job-id "$job_id" --target-org "$ALIAS" || true
      sf project deploy report --job-id "$job_id" --target-org "$ALIAS" --json || true
    else
      sf project deploy report --use-most-recent --target-org "$ALIAS" || true
    fi
    echo ""
    echo "The stage that failed is ${label}. An UNKNOWN_EXCEPTION with zero component errors"
    echo "is a Salesforce side failure: quote the ErrorId in the JSON above to support, and"
    echo "note that it is sometimes transient, so a re-run is worth one attempt."
    rm -f "$log"
    return "$status"
  fi

  rm -f "$log"
  return 0
}

deploy_stage "the vendored rollup engine" "packages/core/vendor" || exit $?
deploy_stage "Core" "packages/core/main" || exit $?

if [[ "$CORE_ONLY" -eq 0 ]]; then
  deploy_stage "Giving" "packages/giving" || exit $?
fi

# A deployment is not an install, so neither post-install script runs here and the shipped
# rollup definitions would not exist in a development org (ADR-0029). This is the same call
# CorePostInstall and GivingPostInstall make, run once the last stage is in, so a development
# org holds the rollups a real install would have. It creates only what is missing.
echo ""
echo "== Creating the shipped rollup definitions =="
if ! printf '%s\n' 'RollupService.ensureDefaults();' | sf apex run --target-org "$ALIAS"; then
  echo "The rollup definitions were not created. Nothing else is affected: the Restore shipped"
  echo "rollups button on the Rollups page runs exactly the same step."
fi

echo ""
echo "== Every stage deployed =="

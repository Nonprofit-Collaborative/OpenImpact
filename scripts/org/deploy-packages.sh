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
# WHY CORE ITSELF IS THREE STAGES. docs/contributor-guide/ci.md records this same failure
# hitting the undivided Core stage four times across four separate runs before 2026-09-09:
# always UNKNOWN_EXCEPTION, always zero components deployed, always zero component errors,
# always the same trailing code -315522575 behind a different leading number, which is why
# that page calls it a deterministic fault rather than a flake and says a re-run proves
# nothing. It recurred twice more on 2026-09-09, on two separate pushes to main, both times
# on the same undivided Core stage, which by then held 904 components in one request: the
# same shape as the original 982-component failure this file was written to avoid, just
# smaller. Nobody has identified which component, or whether it is about total size at all
# rather than something in one specific file, because a failure with nothing attached names
# nothing to investigate.
#
# Splitting Core further follows Salesforce's own deploy dependency order, so each stage is
# also a stage that can legally deploy on its own: data model first (objects, custom
# metadata, labels, static resources, custom permissions), then Apex (classes, triggers,
# which the data model must exist before), then everything that references Apex or wires the
# two together (permission sets and groups, layouts, flexipages, applications, tabs, quick
# actions, Lightning components). This is a narrowing attempt, not a confirmed fix: if the
# fault is about total payload size, three stages of a few hundred components each may simply
# not fail. If it is about one specific component, the next failure now names which third of
# Core that component is in, instead of naming all of Core. Either outcome is progress on a
# question that has otherwise gone six occurrences with no information at all.
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

# Deploy one or more directories as a single stage, and on failure ask the org what actually
# went wrong. A deploy can report only "Status: Failed" with no detail, which is why the
# report is asked for by job id and then again as JSON: the JSON carries errorMessage and
# every component error.
deploy_stage() {
  local label="$1"
  shift
  local dirs=()
  local dir
  for dir in "$@"; do
    if [[ -d "$dir" ]]; then
      dirs+=(--source-dir "$dir")
    fi
  done

  if [[ "${#dirs[@]}" -eq 0 ]]; then
    echo "== Skipping ${label}: none of the given directories exist =="
    return 0
  fi

  echo ""
  echo "== Deploying ${label} ($*) to ${ALIAS} =="
  local log status job_id
  log="$(mktemp)"
  sf project deploy start "${dirs[@]}" --wait 30 --ignore-conflicts --target-org "$ALIAS" 2>&1 | tee "$log"
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
    echo "is a Salesforce side failure, not a component to fix here: quote the ErrorId in the"
    echo "JSON above to Salesforce support. Re-running is not worth trying on its own account:"
    echo "this exact failure (same trailing code -315522575, zero components, zero errors) has"
    echo "hit the undivided Core stage at least six times. See docs/contributor-guide/ci.md,"
    echo "\"It is not transient here\", for the count as of the fourth. If this is one of the"
    echo "three stages Core was split into on 2026-09-09, that is new information: record which"
    echo "one, because narrowing it from all of Core to one third of Core is the point of the"
    echo "split, whether or not it turns out to also dodge the failure."
    rm -f "$log"
    return "$status"
  fi

  rm -f "$log"
  return 0
}

deploy_stage "the vendored rollup engine" "packages/core/vendor" || exit $?
deploy_stage "Core (data model)" \
  "packages/core/main/default/objects" \
  "packages/core/main/default/customMetadata" \
  "packages/core/main/default/labels" \
  "packages/core/main/default/staticresources" \
  "packages/core/main/default/customPermissions" || exit $?
deploy_stage "Core (Apex)" \
  "packages/core/main/default/classes" \
  "packages/core/main/default/triggers" || exit $?
deploy_stage "Core (UI and permissions)" \
  "packages/core/main/default/permissionsets" \
  "packages/core/main/default/permissionsetgroups" \
  "packages/core/main/default/layouts" \
  "packages/core/main/default/flexipages" \
  "packages/core/main/default/applications" \
  "packages/core/main/default/tabs" \
  "packages/core/main/default/quickActions" \
  "packages/core/main/default/lwc" || exit $?

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

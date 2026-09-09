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
# WHY CORE IS SEVERAL STAGES. docs/contributor-guide/ci.md records this same failure
# hitting the undivided Core stage four times across four separate runs before 2026-09-09:
# always UNKNOWN_EXCEPTION, always zero components deployed, always zero component errors,
# always the same trailing code -315522575 behind a different leading number, which is why
# that page calls it a deterministic fault rather than a flake and says a re-run proves
# nothing. It recurred twice more on 2026-09-09, on two separate pushes to main, both times
# on the same undivided Core stage, which by then held 904 components in one request: the
# same shape as the original 982-component failure this file was written to avoid, just
# smaller.
#
# Splitting Core into three (data model, Apex, UI and permissions) followed Salesforce's own
# deploy dependency order and named a stage instead of nothing: the very next run, still on
# 2026-09-09, failed on data model alone, at 853 components. That is the load-bearing data
# point. 853 is close enough to 904 and 982 that a specific bad component stopped being the
# more likely explanation: three deploys of very different content (mostly Apex classes the
# first time, mostly custom fields the second) all failed in the same shape once they got
# into the same few-hundred-to-thousand range. That reads as a size effect, not a component
# defect, though it is still not proven, because nothing about this failure can be proven
# from the client side. It just stopped being a coin flip.
#
# So data model is now three stages of its own: `balanced_split` divides
# packages/core/main/default/objects by file count into two roughly equal halves at runtime
# (a hand-written list of object names would go stale the first time someone adds one), and
# customMetadata, labels, static resources and custom permissions form a third, smaller
# stage. Apex and UI/permissions are unchanged from the first split, because neither has
# failed yet and there is no evidence pointing at either. If one of them fails next, split
# that one the same way this file has now split twice: narrower each time, on the evidence
# the previous stage actually produced, not on a guess about what the eventual safe size is.
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
    echo "hit an undivided or partly divided Core at least seven times now. See"
    echo "docs/contributor-guide/ci.md, \"It is not transient here\", for the count and the"
    echo "component totals each occurrence carried. If ${label} is small (comfortably under"
    echo "the few hundred components the smallest confirmed failure has carried so far), this"
    echo "is new evidence the effect is not purely about size, and the next step is to look at"
    echo "what is actually in this stage rather than splitting it again on faith. If it is"
    echo "still large, split it the same way the data model stage was split: narrower, by"
    echo "runtime file count where possible, on what this run actually showed."
    rm -f "$log"
    return "$status"
  fi

  rm -f "$log"
  return 0
}

# Splits the immediate subdirectories of one directory into two file-count-balanced
# groups, greedily: largest subdirectory first, each one going to whichever running total
# is currently smaller. File count is a proxy for the metadata component count Salesforce
# actually charges a deploy for, not the same number, but the two have moved together in
# every measurement this project has taken (982, then 904, then 853 components behind file
# counts of comparable size), so it is a proxy worth using.
#
# Dynamic on purpose. A hand-written list of object names goes stale the day a new object
# is added, silently piling onto whichever stage it happens to be typed after. This looks
# at the directory itself, so packages/core/main/default/objects splits itself in half
# again automatically as it grows, the same way this file's own history shows it needs to.
balanced_split() {
  local parent="$1"
  local -n out_a="$2"
  local -n out_b="$3"
  local total_a=0 total_b=0
  out_a=()
  out_b=()
  local line count dir
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    count="${line%% *}"
    dir="${line#* }"
    if (( total_a <= total_b )); then
      out_a+=("$dir")
      (( total_a += count ))
    else
      out_b+=("$dir")
      (( total_b += count ))
    fi
  done < <(
    for dir in "$parent"/*/; do
      [[ -d "$dir" ]] || continue
      echo "$(find "$dir" -type f | wc -l) $dir"
    done | sort -rn
  )
}

deploy_stage "the vendored rollup engine" "packages/core/vendor" || exit $?

OBJECTS_A=()
OBJECTS_B=()
balanced_split "packages/core/main/default/objects" OBJECTS_A OBJECTS_B
deploy_stage "Core (data model, objects A)" "${OBJECTS_A[@]}" || exit $?
deploy_stage "Core (data model, objects B)" "${OBJECTS_B[@]}" || exit $?
deploy_stage "Core (data model, config)" \
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

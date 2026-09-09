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
# So data model became three stages of its own: `balanced_split` divided
# packages/core/main/default/objects by file count into two roughly equal halves at runtime
# (a hand-written list of object names would go stale the first time someone adds one), and
# customMetadata, labels, static resources and custom permissions formed a third, smaller
# stage. That halving stopped being useful evidence on 2026-09-09: the two halves it produces
# are stable across runs (nothing but file *content* changed in between, and balanced_split
# only looks at file *counts*), and across four consecutive pushes that all fixed real
# component-level errors in "objects B" (139 files, 10 objects), that stage kept failing with
# the same zero-component UNKNOWN_EXCEPTION every single time, while "objects A" (144 files,
# 11 objects, comparable size) deployed clean every one of those four runs. Two same-sized
# groups behaving oppositely and consistently is not a size effect; it is evidence the fault
# tracks something specific to one or more objects inside "objects B".
#
# Objects now deploy one at a time, each its own stage, rather than split into another pair
# of same-content halves that would just repeat this result. With ~10 to 30 files per object,
# a per-object stage is nowhere near the few-hundred-component range any prior failure has
# carried, so the next run either names the exact object responsible (a stage newly failing
# alone) or clears every object individually, which would itself be new evidence: that the
# fault needs several specific objects deployed *together* in one request, not any one of them
# alone. Apex and UI/permissions are unchanged, because neither has failed yet and there is no
# evidence pointing at either.
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
    echo "hit an undivided or partly divided Core at least eight times now. See"
    echo "docs/contributor-guide/ci.md, \"It is not transient here\", for the count and the"
    echo "component totals each occurrence carried. If ${label} is small (comfortably under"
    echo "the few hundred components the smallest confirmed failure has carried so far), do not"
    echo "just split it again on faith: the objects data model stage already tried a same-size"
    echo "split four times running and it named nothing, because both halves stayed the same"
    echo "size and content on every run. Look at what is actually in this specific stage, or,"
    echo "if it is still large, split it narrower on the number this run actually carried."
    rm -f "$log"
    return "$status"
  fi

  rm -f "$log"
  return 0
}

deploy_stage "the vendored rollup engine" "packages/core/vendor" || exit $?

# One stage per object, not a file-count split. The two-way file-count split this replaced
# produced the same two groups every run, since only file content had been changing, not
# file counts, and one of those two groups (10 objects, 139 files) failed with the platform's
# zero-component UNKNOWN_EXCEPTION on four consecutive pushes while the other (11 objects, 144
# files, comparable size) deployed clean every time. Same size, opposite and consistent
# outcomes: that is evidence against a size effect, not for one, so splitting into another
# same-content pair would not have told us anything the last four runs did not already show.
# Each object is small enough on its own (a handful of files to a few dozen) that the next
# failure, if there is one, names the exact object; if every object deploys clean individually,
# that is itself the finding, that it takes several specific objects deployed together in one
# request to trigger this.
for dir in packages/core/main/default/objects/*/; do
  [[ -d "$dir" ]] || continue
  deploy_stage "Core (data model, $(basename "$dir"))" "$dir" || exit $?
done
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

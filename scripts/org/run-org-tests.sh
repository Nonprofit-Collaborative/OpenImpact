#!/usr/bin/env bash
# run-org-tests.sh <org alias>
#
# The merge gate for main. Deploys the commit you have checked out to an org, runs every
# local Apex test there, and posts the result to GitHub as the commit status
# "Org tests (local)" on that exact commit. The main branch ruleset requires that status,
# so a pull request that changes deployable source cannot merge until this has passed on
# its head commit. See docs/contributor-guide/ci.md, "The org test gate".
#
# WHY A LOCAL RUN POSTS THE STATUS. Org tests used to run in GitHub Actions on every push
# to main, against one shared org. They now run from a contributor's machine against an
# org the contributor controls, which is faster to iterate on and costs no CI minutes. A
# local run proves nothing to a reviewer unless it leaves a record, and a record is only
# worth trusting if it names the commit that was tested. A commit status is exactly that:
# it belongs to one SHA, so a later push has no status until someone runs this again.
#
# WHY IT REFUSES A DIRTY TREE. The status is posted on HEAD. If the working tree held
# changes, the code deployed and tested would not be the code at HEAD, and the status
# would vouch for a commit that was never run. The same goes for an unpushed commit, which
# GitHub cannot attach a status to anyway, so that is checked before the long part starts
# rather than after it.
#
# Exit codes: 0 = every test passed and the success status was posted; non-zero otherwise.

set -euo pipefail

ALIAS="${1:-}"
if [[ -z "$ALIAS" ]]; then
  echo "Usage: run-org-tests.sh <org alias>" >&2
  exit 2
fi

CONTEXT="Org tests (local)"
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "The working tree has uncommitted changes. Commit or stash them first: the status is" >&2
  echo "posted on HEAD, so the code tested has to be exactly the code at HEAD." >&2
  git status --short >&2
  exit 1
fi

SHA="$(git rev-parse HEAD)"
REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

if ! gh api "repos/${REPO}/commits/${SHA}" --silent 2>/dev/null; then
  echo "Commit ${SHA:0:7} is not on GitHub yet. Push it first, so the status has a commit to" >&2
  echo "attach to." >&2
  exit 1
fi

post_status() {
  local state="$1" description="$2"
  gh api "repos/${REPO}/statuses/${SHA}" --silent \
    -f state="$state" \
    -f context="$CONTEXT" \
    -f description="${description:0:140}"
}

echo "== Testing ${SHA:0:7} on ${ALIAS} =="
bash scripts/org/check-org-expiry.sh "$ALIAS"

if ! bash scripts/org/deploy-packages.sh "$ALIAS"; then
  post_status failure "Deploy to ${ALIAS} failed, so no test ran"
  exit 1
fi

# A real install gives the installing administrator the admin roles, and the tests run as
# that user in user mode, so they need the same roles here. "Duplicate" means the role is
# already assigned, which is the normal case after the first run.
for ps in Nonprofit_Admin Giving_Admin; do
  sf org assign permset --name "$ps" --target-org "$ALIAS" --json > "${TMPDIR:-/tmp}/assign.json" || true
  if jq -e '.result.failures[]? | select(.message | test("Duplicate") | not)' \
    "${TMPDIR:-/tmp}/assign.json" > /dev/null; then
    cat "${TMPDIR:-/tmp}/assign.json" >&2
    post_status failure "Could not assign ${ps} on ${ALIAS}, so no test ran"
    exit 1
  fi
done

RESULTS_DIR="test-results"
mkdir -p "$RESULTS_DIR"
sf apex run test \
  --target-org "$ALIAS" \
  --test-level RunLocalTests \
  --code-coverage \
  --result-format json \
  --wait 90 > "${RESULTS_DIR}/org-tests.json" || true

read -r OUTCOME RAN PASSING FAILING < <(jq -r \
  '.result.summary | "\(.outcome // "Unknown") \(.testsRan // 0) \(.passing // 0) \(.failing // 0)"' \
  "${RESULTS_DIR}/org-tests.json" 2>/dev/null || echo "Unknown 0 0 0")

if [[ "$OUTCOME" == "Passed" && "$FAILING" -eq 0 && "$RAN" -gt 0 ]]; then
  post_status success "${PASSING}/${RAN} passed on ${ALIAS}"
  echo "== ${PASSING}/${RAN} passed. Posted \"${CONTEXT}\": success on ${SHA:0:7} =="
  exit 0
fi

post_status failure "${FAILING} of ${RAN} failed on ${ALIAS}"
echo "== ${FAILING} of ${RAN} failed. Posted \"${CONTEXT}\": failure on ${SHA:0:7} ==" >&2
jq -r '.result.tests[] | select(.Outcome != "Pass") | "  \(.FullName): \(.Message // "")"' \
  "${RESULTS_DIR}/org-tests.json" 2>/dev/null | cut -c1-200 >&2 || true
echo "Full results: ${RESULTS_DIR}/org-tests.json" >&2
exit 1

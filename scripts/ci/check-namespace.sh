#!/usr/bin/env bash
# check-namespace.sh
#
# Fails (exit 1) if:
#   - any file under packages/ (excluding .gitkeep) contains the literal string "openimpact__"
#   - any file under packages/ contains an explicit namespace prefix on a custom component,
#     i.e. a double-underscore-prefixed name followed by another double underscore
#     (namespace__Object__suffix), matched as [A-Za-z0-9]+__[A-Za-z0-9_]+__(c|r|mdt|e|b)
#   - sfdx-project.json has a non-empty "namespace" value
#
# Prints offending lines. Namespace-agnostic development is a hard requirement until the
# namespace is registered (see docs/product-plan.md Section 4.3).

set -euo pipefail

FAILED=0

if [[ -d packages ]]; then
  echo "== Checking for literal 'openimpact__' =="
  if MATCHES=$(grep -rn "openimpact__" packages --include='*' --exclude='.gitkeep' 2>/dev/null); then
    echo "$MATCHES"
    echo "FAIL: found literal 'openimpact__' references above." >&2
    FAILED=1
  fi

  echo "== Checking for explicit namespace-prefixed custom components =="
  if MATCHES=$(grep -rnE '[A-Za-z0-9]+__[A-Za-z0-9_]+__(c|r|mdt|e|b)' packages --include='*' --exclude='.gitkeep' 2>/dev/null); then
    echo "$MATCHES"
    echo "FAIL: found explicit namespace-prefixed component references above." >&2
    FAILED=1
  fi
fi

echo "== Checking sfdx-project.json namespace =="
if [[ -f sfdx-project.json ]]; then
  NS=$(node -e "const p=require('./sfdx-project.json'); process.stdout.write(p.namespace === undefined ? '' : String(p.namespace));")
  if [[ -n "$NS" ]]; then
    echo "FAIL: sfdx-project.json namespace is non-empty: '${NS}'" >&2
    FAILED=1
  fi
fi

if [[ "$FAILED" -eq 1 ]]; then
  echo "check-namespace.sh: FAILED" >&2
  exit 1
fi

echo "check-namespace.sh: OK"

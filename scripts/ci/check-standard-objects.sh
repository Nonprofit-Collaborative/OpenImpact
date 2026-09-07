#!/usr/bin/env bash
# check-standard-objects.sh
#
# Fails (exit 1) if any file under packages/core, packages/giving, packages/volunteers,
# packages/programs, or packages/funders (excluding README.md files) references, as whole
# words, case-sensitive: Opportunity, Campaign, Lead, Case, OpportunityContactRole,
# CampaignMember, PersonAccount, IsPersonAccount, or any Industries GiftTransaction / __dlm
# name. Those objects and fields may only be referenced from packages/connect, and even there
# behind dynamic Apex (see docs/product-plan.md Section 4.2).

set -euo pipefail

DIRS=(packages/core packages/giving packages/volunteers packages/programs packages/funders)

PATTERN='\b(Opportunity|OpportunityContactRole|Campaign|CampaignMember|Lead|Case|PersonAccount|IsPersonAccount|GiftTransaction)\b|__dlm\b'

FAILED=0

for DIR in "${DIRS[@]}"; do
  [[ -d "$DIR" ]] || continue
  if MATCHES=$(grep -rnwE "$PATTERN" "$DIR" --include='*' --exclude='README.md' 2>/dev/null); then
    echo "$MATCHES"
    echo "FAIL: forbidden standard/Industries object reference(s) found under ${DIR} above." >&2
    FAILED=1
  fi
done

if [[ "$FAILED" -eq 1 ]]; then
  echo "check-standard-objects.sh: FAILED" >&2
  exit 1
fi

echo "check-standard-objects.sh: OK"

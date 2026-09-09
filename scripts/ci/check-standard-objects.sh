#!/usr/bin/env bash
# check-standard-objects.sh
#
# Fails (exit 1) if any file under packages/core, packages/giving, packages/volunteers,
# packages/programs, or packages/funders (excluding README.md files) references, as whole
# words, case-sensitive: Opportunity, Campaign, Lead, Case, OpportunityContactRole,
# CampaignMember, PersonAccount, IsPersonAccount, or any Industries GiftTransaction / __dlm
# name. Those objects and fields may only be referenced from packages/connect, and even there
# behind dynamic Apex (see docs/product-plan.md Section 4.2).
#
# A second pattern covers the Nonprofit Cloud surface: the fundraising objects, the objects a
# household is actually built out of there (PartyRelationshipGroup and AccountContactRelation),
# and the contact point objects that are its answer to an address. It is checked in Apex and
# metadata only, because a Lightning component's JavaScript cannot reference an SObject and
# our own component class names collide with several of these words.
#
# This half was added after an audit found the gate matched GiftTransaction alone. Core could
# have named PartyRelationshipGroup, the object that decides whether an Account is a Nonprofit
# Cloud household, and CI would have passed it.
#
# Detection-only exemptions
# -------------------------
# Detecting that an object exists is not depending on it. Core has to be able to tell an
# administrator what is installed in their org (Health Check, plan Section 4.8), and that
# means holding a few of these names as String constants passed to Schema.getGlobalDescribe
# or to a field map, never as a compile-time reference.
#
# An Apex line (*.cls or *.trigger) that carries the comment
#
#     // detection-only: <reason>
#
# is exempt from this check. Every exempted line is printed on each run so a reviewer sees
# the whole list without going looking for it. The marker is only honored in Apex, only on
# the line it appears on, and it never exempts a compile-time reference: writing
# Opportunity.Name with the marker appended still means Core will not deploy on a
# Platform-only org. Use it on constant declarations and nowhere else, and keep the reason
# specific enough that the next reader can judge it.
#
# See docs/contributor-guide/ci.md, "Detection-only exemptions".

set -euo pipefail

DIRS=(packages/core packages/giving packages/volunteers packages/programs packages/funders)

PATTERN='\b(Opportunity|OpportunityContactRole|Campaign|CampaignMember|Lead|Case|PersonAccount|IsPersonAccount|GiftTransaction)\b|__dlm\b'

# Apex and metadata only. See the note above on JavaScript.
NPC_PATTERN='\b(PartyRelationshipGroup|PartyRoleRelation|AccountAccountRelation|AccountContactRelation|ContactContactRelation|ContactPointAddress|ContactPointEmail|ContactPointPhone|ContactPointConsent|PersonLifeEvent|GiftTransactionDesignation|GiftDesignation|GiftDefaultDesignation|GiftCommitment|GiftCommitmentSchedule|GiftSoftCredit|GiftTribute|GiftRefund|GiftEntry|GiftBatch|OutreachSourceCode|OutreachSummary|DonorGiftSummary|ProgramEnrollment|BenefitAssignment|BenefitDisbursement|RecordAggregationDefinition)\b'
NPC_INCLUDES=(--include='*.cls' --include='*.trigger' --include='*.xml')

# The vendored rollup engine is third party source, not ours to rewrite line by line, and it
# names ContactPointAddress and Individual in its own test classes. That is a real open
# question about whether Core deploys on a Platform-only org, not something to hide, so it is
# excluded here and tracked as a follow-up rather than silently passed.
NPC_EXCLUDE_DIR='vendor'

MARKER='// detection-only:'

FAILED=0
EXEMPTED=()
VIOLATIONS=()

for DIR in "${DIRS[@]}"; do
  [[ -d "$DIR" ]] || continue
  MATCHES=$(grep -rnwE "$PATTERN" "$DIR" --include='*' --exclude='README.md' 2>/dev/null || true)
  NPC_MATCHES=$(grep -rnwE "$NPC_PATTERN" "$DIR" "${NPC_INCLUDES[@]}" \
    --exclude='README.md' --exclude-dir="$NPC_EXCLUDE_DIR" 2>/dev/null || true)
  if [[ -n "$NPC_MATCHES" ]]; then
    MATCHES=$(printf '%s\n%s' "$MATCHES" "$NPC_MATCHES")
  fi
  [[ -n "$MATCHES" ]] || continue
  while IFS= read -r LINE; do
    [[ -n "$LINE" ]] || continue
    FILE="${LINE%%:*}"
    if [[ "$FILE" == *.cls || "$FILE" == *.trigger ]] && [[ "$LINE" == *"$MARKER"* ]]; then
      EXEMPTED+=("$LINE")
    else
      VIOLATIONS+=("$LINE")
    fi
  done <<< "$MATCHES"
done

if [[ "${#EXEMPTED[@]}" -gt 0 ]]; then
  echo "== Detection-only exemptions (${#EXEMPTED[@]}), review each one =="
  printf '%s\n' "${EXEMPTED[@]}"
fi

if [[ "${#VIOLATIONS[@]}" -gt 0 ]]; then
  printf '%s\n' "${VIOLATIONS[@]}"
  echo "FAIL: forbidden standard/Industries object reference(s) found above." >&2
  echo "  If the reference is a String constant used only to detect what is installed," >&2
  echo "  append '${MARKER} <reason>' to that Apex line." >&2
  FAILED=1
fi

if [[ "$FAILED" -eq 1 ]]; then
  echo "check-standard-objects.sh: FAILED" >&2
  exit 1
fi

echo "check-standard-objects.sh: OK"

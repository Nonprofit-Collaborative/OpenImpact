#!/usr/bin/env bash
# report-org-shape.sh <alias>
#
# Prints which org shape the test org actually is, by asking the org rather than trusting a
# note somewhere.
#
# Continuous integration used to create a scratch org per shape from a definition file, so the
# shape of the org a result came from was whatever the matrix said. It now deploys into one
# long lived org named only by an auth URL in a secret, and nothing records which definition
# that org was created from. Every Apex result this project ever gets will come from that one
# org, so "which shape was that" has to be answerable from the build log, not from memory.
#
# The five facts below are the ones the shapes differ by, and they are the same facts
# OrgShapeDetector reads at run time. They are read here instead through the Tooling API,
# because this has to work before the packages deploy, which is exactly when it is needed.
#
# Exit codes: 0 always. This reports; it does not fail a build. An org that answers nothing
# still gets a line saying so, which is itself the finding.

set -uo pipefail

ALIAS="${1:-testorg}"

# Asks whether an object exists in the org. Prints "yes" or "no".
entity_exists() {
  local api_name="$1"
  local count
  count="$(sf data query \
    --target-org "$ALIAS" \
    --use-tooling-api \
    --query "SELECT QualifiedApiName FROM EntityDefinition WHERE QualifiedApiName = '${api_name}'" \
    --json 2>/dev/null |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["totalSize"])' 2>/dev/null || echo "")"
  if [[ "$count" == "1" ]]; then echo "yes"; else echo "no"; fi
}

# Asks whether a field exists on an object. Prints "yes" or "no".
field_exists() {
  local entity="$1"
  local field="$2"
  local count
  count="$(sf data query \
    --target-org "$ALIAS" \
    --use-tooling-api \
    --query "SELECT QualifiedApiName FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName = '${entity}' AND QualifiedApiName = '${field}'" \
    --json 2>/dev/null |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["totalSize"])' 2>/dev/null || echo "")"
  if [[ "$count" == "1" ]]; then echo "yes"; else echo "no"; fi
}

ORG_TYPE="$(sf data query \
  --target-org "$ALIAS" \
  --query "SELECT OrganizationType FROM Organization LIMIT 1" \
  --json 2>/dev/null |
  python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["records"][0]["OrganizationType"])' 2>/dev/null || echo "unknown")"

PERSON_ACCOUNTS="$(field_exists Account IsPersonAccount)"
NONPROFIT_CLOUD="$(entity_exists GiftTransaction)"
NPSP="$(entity_exists npsp__Household__c)"
SALES_CLOUD="$(entity_exists Opportunity)"

echo "Test org '${ALIAS}' shape, read from the org:"
echo "  Edition:          ${ORG_TYPE}"
echo "  Person Accounts:  ${PERSON_ACCOUNTS}"
echo "  Nonprofit Cloud:  ${NONPROFIT_CLOUD}"
echo "  NPSP:             ${NPSP}"
echo "  Sales Cloud:      ${SALES_CLOUD}"

# Names the shape, using the same precedence OrgShapeDetector uses: the most specific
# nonprofit product wins, then Person Accounts, then Sales Cloud, then Platform only.
if [[ "$NONPROFIT_CLOUD" == "yes" ]]; then
  SHAPE="nonprofit-cloud"
elif [[ "$NPSP" == "yes" ]]; then
  SHAPE="npsp"
elif [[ "$PERSON_ACCOUNTS" == "yes" ]]; then
  SHAPE="person-accounts"
elif [[ "$SALES_CLOUD" == "yes" ]]; then
  SHAPE="sales-cloud"
else
  SHAPE="platform-only"
fi

echo "  Closest definition in config/scratch-defs: ${SHAPE}.json"
echo ""
echo "Everything this run proves, it proves about that shape and no other. A result from"
echo "this org says nothing about the four shapes it is not."

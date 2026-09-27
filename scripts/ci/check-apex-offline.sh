#!/usr/bin/env bash
# check-apex-offline.sh
#
# Offline Apex compile check using apex-ls (nawforce/apex-dev-tools) CheckForIssues.
# Requires no Salesforce org or Dev Hub. Requires Java 21+ and Maven (both already
# present in the standard dev/CI environment) to resolve the tool from Maven Central
# on first run; results are cached under .tools/ so later runs are fast and, once
# cached, work fully offline.
#
# Exit codes: 0 = no errors found, non-zero = errors found or the tool could not run.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS_DIR="$REPO_ROOT/.tools/apex-ls"
APEX_LS_VERSION="6.2.0"
SCALA_BINARY="2.13"
ARTIFACT="apex-ls_${SCALA_BINARY}"
CP_FILE="$TOOLS_DIR/classpath.txt"
POM_FILE="$TOOLS_DIR/pom.xml"

mkdir -p "$TOOLS_DIR"

if ! command -v java >/dev/null 2>&1; then
  echo "check-apex-offline: java is required but not found on PATH." >&2
  exit 1
fi

if [[ ! -s "$CP_FILE" ]]; then
  if ! command -v mvn >/dev/null 2>&1; then
    echo "check-apex-offline: maven is required (first run only, to fetch apex-ls" >&2
    echo "  from Maven Central) but 'mvn' was not found on PATH." >&2
    exit 1
  fi

  echo "check-apex-offline: resolving apex-ls ${APEX_LS_VERSION} from Maven Central (first run only)..."

  cat > "$POM_FILE" <<EOF
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>barncrm.tools</groupId>
  <artifactId>apex-ls-runner</artifactId>
  <version>1.0</version>
  <dependencies>
    <dependency>
      <groupId>io.github.apex-dev-tools</groupId>
      <artifactId>${ARTIFACT}</artifactId>
      <version>${APEX_LS_VERSION}</version>
    </dependency>
  </dependencies>
</project>
EOF

  if ! mvn -q -f "$POM_FILE" dependency:build-classpath -Dmdep.outputFile="$CP_FILE"; then
    echo "check-apex-offline: failed to resolve apex-ls from Maven Central." >&2
    rm -f "$CP_FILE"
    exit 1
  fi
fi

APEX_LS_JAR="$(find "$HOME/.m2/repository/io/github/apex-dev-tools/${ARTIFACT}/${APEX_LS_VERSION}" -maxdepth 1 -name "${ARTIFACT}-${APEX_LS_VERSION}.jar" | head -1)"
if [[ -z "$APEX_LS_JAR" ]]; then
  echo "check-apex-offline: could not locate the resolved apex-ls jar under ~/.m2." >&2
  exit 1
fi

CLASSPATH="${APEX_LS_JAR}:$(cat "$CP_FILE")"

# Two passes. The first checks every package together, as they deploy. The second checks Core
# alone, as the Community Suite installs it (ADR-0046, ADR-0059): Core must never name a
# Giving, Connect or other module class at compile time, and in the first pass those classes
# are present, so a reference to one compiles there and fails only in an org without them.
# The second pass copies packages/core into a temporary workspace whose sfdx-project.json
# lists Core only.
run_check() {
  local workspace="$1" label="$2" status
  set +e
  java -cp "$CLASSPATH" io.github.apexdevtools.apexls.CheckForIssues \
    --workspace "$workspace" --detail errors --format text
  status=$?
  set -e
  case "$status" in
    0)
      echo "check-apex-offline: ${label}: no compile-level errors found."
      ;;
    4)
      echo "check-apex-offline: FAILED, apex-ls reported compile-level errors above (${label})." >&2
      return 1
      ;;
    *)
      echo "check-apex-offline: apex-ls exited with unexpected status $status (${label})." >&2
      return 1
      ;;
  esac
}

run_check "$REPO_ROOT" "all packages" || exit 1

CORE_ONLY="$(mktemp -d)"
trap 'rm -rf "$CORE_ONLY"' EXIT
mkdir -p "$CORE_ONLY/packages"
cp -R "$REPO_ROOT/packages/core" "$CORE_ONLY/packages/core"
API_VERSION="$(sed -n 's/.*"sourceApiVersion": *"\([0-9.]*\)".*/\1/p' "$REPO_ROOT/sfdx-project.json" | head -1)"
cat > "$CORE_ONLY/sfdx-project.json" <<EOF
{
  "namespace": "",
  "sourceApiVersion": "${API_VERSION}",
  "packageDirectories": [{ "path": "packages/core", "default": true }]
}
EOF
run_check "$CORE_ONLY" "Core alone" || exit 1
exit 0

#!/usr/bin/env bash
# check-symlinks.sh
#
# Fails when a tracked file is a symlink pointing outside the repository, or at an
# absolute path.
#
# Such a link resolves on the machine that committed it and dangles everywhere else, so
# every local check passes and CI fails. That is exactly how a stray ".tools" symlink,
# left in an agent worktree and swept in by "git add -A", broke the offline Apex compile
# check on main: the step runs "mkdir -p .tools/apex-ls" and a dangling symlink of that
# name makes it fail with "File exists".
#
# Exit codes: 0 = clean, 1 = a bad link is tracked.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

problems=0

# Mode 120000 is a symlink. The blob's content is the link target.
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  target="$(git cat-file blob ":$path")"
  case "$target" in
    /*)
      echo "check-symlinks: '$path' is a symlink to the absolute path '$target'." >&2
      problems=$((problems + 1))
      ;;
    *)
      resolved="$(cd "$(dirname "$path")" 2>/dev/null && cd "$(dirname "$target")" 2>/dev/null && pwd || true)"
      if [[ -n "$resolved" && "$resolved" != "$REPO_ROOT" && "$resolved" != "$REPO_ROOT"/* ]]; then
        echo "check-symlinks: '$path' is a symlink to '$target', outside the repository." >&2
        problems=$((problems + 1))
      fi
      ;;
  esac
done < <(git ls-files -s | awk '$1 == "120000" { $1=""; $2=""; $3=""; sub(/^[ \t]+/, ""); print }')

if (( problems > 0 )); then
  echo "check-symlinks.sh: FAILED, $problems problem(s) above" >&2
  exit 1
fi

echo "check-symlinks.sh: OK, no tracked symlink leaves the repository"

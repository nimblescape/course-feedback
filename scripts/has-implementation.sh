#!/usr/bin/env bash
# Prints the assignment folders (relative to 20-assignments/) that contain
# student work, i.e. whose workspace/ folder differs from the version the
# template added (changed or new files).
#
# Usage: has-implementation.sh [assignment ...]
#
# With assignment arguments, only these assignments are checked. Whether the
# feedback of an assignment is missing or outdated decides
# `scripts/feedback.py outdated`.

set -euo pipefail

workspace_changed_since_template() {
  local dir="$1"
  # new files that the template did not ship
  if [ -n "$(git ls-files --others --exclude-standard -- "$dir")" ]; then
    return 0
  fi
  local file added
  while IFS= read -r file; do
    added=$(git log --diff-filter=A --format=%H -- "$file" | tail -n 1)
    [ -n "$added" ] || return 0
    if ! git diff --quiet "$added" HEAD -- "$file"; then
      return 0
    fi
  done < <(git ls-files -- "$dir")
  return 1
}

check() {
  local assignment_path="$1"
  [ -f "$assignment_path/README.md" ] && [ -d "$assignment_path/workspace" ] || return 0
  if workspace_changed_since_template "$assignment_path/workspace"; then
    echo "${assignment_path#20-assignments/}"
  fi
}

if [ "$#" -gt 0 ]; then
  for assignment in "$@"; do
    check "20-assignments/$assignment"
  done
else
  while IFS= read -r -d '' readme_path; do
    check "$(dirname "$readme_path")"
  done < <(find 20-assignments -mindepth 3 -maxdepth 3 -type f -name README.md -print0 | sort -z)
fi

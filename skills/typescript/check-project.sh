#!/usr/bin/env bash
# Automatic check of a workspace that is its own npm project (for example the
# Vite game of oop-2 15.01): `npm run check` of the project, as the students run
# it, with the project's own npm packages. Prints Markdown facts for the prompt
# (see scripts/check-lib.sh).
#
# Usage: check-project.sh <assignment-path> <commit>   (called by check.sh)
#
# <commit> is the template copy of the class repository (its newest root
# commit). package.json, package-lock.json and tsconfig.json lie in the
# student-writable workspace, so they count in the version of that commit: the
# template sync never changes workspace files later.

set -uo pipefail

# shellcheck source=/dev/null
source "$FEEDBACK_CENTRAL/scripts/check-lib.sh"

assignment="${1%/}"
root="$2"
workspace="$assignment/workspace"
work="$FEEDBACK_WORK/typescript"
copy="$work/project"
rm -rf "$work"
mkdir -p "$work"
cp -r "$workspace" "$copy"
rm -rf "$copy/node_modules" "$copy/dist"

notes=()
for file in package.json package-lock.json tsconfig.json; do
  rm -f "$copy/$file"
  git cat-file -e "$root:$workspace/$file" 2>/dev/null || continue
  git show "$root:$workspace/$file" > "$copy/$file"
  # The lock file changes with every `npm install`: no note for it
  if [ "$file" != package-lock.json ] && ! git diff --quiet "$root" HEAD -- "$workspace/$file"; then
    notes+=("The student changed \`workspace/$file\`: the check uses the course's version.")
  fi
done

script=$(jq -r '.scripts.check // empty' "$copy/package.json" 2>/dev/null)
if [ -z "$script" ]; then
  echo "The workspace is its own npm project without a \`check\` script: no automatic check."
  exit 0
fi
if [ ! -f "$copy/package-lock.json" ]; then
  echo "The workspace is its own npm project without \`package-lock.json\`: no automatic check."
  exit 0
fi

# Like `npm ci` in the workspace: the exact versions of the lock file,
# installed outside the checkout without install scripts
mkdir -p "$work/npm"
cp "$copy/package.json" "$copy/package-lock.json" "$work/npm/"
key=$(cat "$copy/package.json" "$copy/package-lock.json" | sha256sum | cut -c 1-16)
packages=$(install_tools "$work/npm" "project-$key")
if [ ! -f "$packages/.installed" ]; then
  echo "The project's npm packages could not be installed (\`npm ci\` with its \`package-lock.json\`): no automatic check."
  exit 0
fi
ln -s "$packages/node_modules" "$copy/node_modules"

echo "### Type check (\`npm run check\` of the project: \`$script\`)"
echo
for note in "${notes[@]}"; do
  echo "$note"
  echo
done
SANDBOX_CHDIR="$copy" bash "$FEEDBACK_CENTRAL/scripts/sandbox.sh" "$work" "$packages" -- \
  timeout 120 npm run check --silent --no-update-notifier > "$work/check.txt" 2>&1
status=$?
sed -i -e "s#$copy/##g; s#$packages/##g" "$work/check.txt"
if [ "$status" -eq 0 ]; then
  echo "No errors."
else
  block "$work/check.txt" 40
  echo "exit code: $status"
  does_not_run typecheck
fi
echo
echo "The work is its own npm project: it was checked with \`npm run check\`, not run."

#!/usr/bin/env bash
# Automatic check of a workspace that is its own npm project (a Vite project,
# for example the game of oop-2 15.01 or the React projects of react-2):
# `npm run build` of the project, as the students run it before every push, with
# the project's own npm packages. The build script of a standard Vite project
# type-checks first (`tsc && vite build` or `tsc -b && vite build`). Prints
# Markdown facts for the prompt (see scripts/check-lib.sh).
#
# Usage: check-project.sh <assignment-path> <commit>   (called by check.sh)
#        check-project.sh <assignment-path> own
#
# <commit> is the template copy of the class repository (its newest root
# commit). The configuration of the project (package.json, package-lock.json,
# tsconfig*.json, jsconfig*.json, vite.config.*) lies in the student-writable
# workspace, so it counts in the version of that commit: the template sync never
# changes workspace files later.
#
# `own`: the student set up the npm project (the README asks for it, for
# example react-2 04.01 "Swap the Engine"): the template has no package.json, so
# the student's configuration counts.

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

configuration() {
  case "$1" in
    package.json | package-lock.json | tsconfig*.json | jsconfig*.json | vite.config.*) return 0 ;;
  esac
  return 1
}

notes=()
if [ "$root" = own ]; then
  notes+=("The student set up this npm project (the course gives no \`package.json\`): the check uses the student's \`package.json\`, \`package-lock.json\` and configuration.")
else
  for path in "$copy"/*; do
    file=$(basename "$path")
    if [ -f "$path" ] && configuration "$file" && ! git cat-file -e "$root:$workspace/$file" 2>/dev/null; then
      rm -f "$path"
      notes+=("The student added \`workspace/$file\`: the check ignores it.")
    fi
  done
  while IFS= read -r file; do
    configuration "$file" || continue
    rm -f "$copy/$file"
    git show "$root:$workspace/$file" > "$copy/$file"
    # The lock file changes with every `npm install`: no note for it
    if [ "$file" != package-lock.json ] && ! git diff --quiet "$root" HEAD -- "$workspace/$file"; then
      notes+=("The student changed \`workspace/$file\`: the check uses the course's version.")
    fi
  done < <(git ls-tree --name-only "$root:$workspace")
fi

script=$(jq -r '.scripts.build // empty' "$copy/package.json" 2>/dev/null)
if [ -z "$script" ]; then
  echo "The workspace is its own npm project without a \`build\` script: no automatic check."
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
# A writable node_modules with one link per installed package and npm's bin
# folder: `tsc -b` writes its build information to node_modules/.tmp, and Vite
# bundles vite.config.ts to node_modules/.vite-temp
mkdir "$copy/node_modules"
for package in "$packages/node_modules"/* "$packages/node_modules"/.bin; do
  [ ! -e "$package" ] || ln -s "$package" "$copy/node_modules/"
done

echo "### Build (\`npm run build\` of the project: \`$script\`)"
echo
for note in "${notes[@]}"; do
  echo "$note"
  echo
done
SANDBOX_CHDIR="$copy" bash "$FEEDBACK_CENTRAL/scripts/sandbox.sh" "$work" "$packages" -- \
  timeout 120 npm run build --silent --no-update-notifier > "$work/check.txt" 2>&1
status=$?
sed -i -e "s#$copy/##g; s#$packages/##g" "$work/check.txt"
if [ "$status" -eq 0 ]; then
  echo "No errors."
else
  block "$work/check.txt" 40
  echo "exit code: $status"
  does_not_run build
fi
echo
echo "The work is its own npm project: it was built with \`npm run build\` (the type check, then the build), not run."

# The linter of the project (`npm run lint`, oxlint in the Vite templates):
# facts for the feedback, never a reason for "does not run". oxlint lints the
# files in parallel, so its problems come in a random order: with
# --format=unix, one line per problem, sorted by file and position, the text is
# the same in every run.
lint=$(jq -r '.scripts.lint // empty' "$copy/package.json" 2>/dev/null)
[ -n "$lint" ] || exit 0
echo
echo "### Lint (\`npm run lint\` of the project: \`$lint\`)"
echo
options=()
case "$lint" in
  oxlint | "oxlint "*) options=(-- --format=unix) ;;
esac
SANDBOX_CHDIR="$copy" bash "$FEEDBACK_CENTRAL/scripts/sandbox.sh" "$work" "$packages" -- \
  timeout 60 npm run lint --silent --no-update-notifier "${options[@]}" > "$work/lint.txt" 2>&1
status=$?
sed -i -e "s#$copy/##g; s#$packages/##g" -e '/^Finished in [0-9.]*m\?s /d' "$work/lint.txt"
problem='^[^[:space:]][^:]*:[0-9]+:[0-9]+: '
{
  grep -E "$problem" "$work/lint.txt" | LC_ALL=C sort -t : -k 1,1 -k 2,2n -k 3,3n
  grep -vE "$problem" "$work/lint.txt" | sed '/^[[:space:]]*$/d'
} > "$work/lint-sorted.txt"
if [ "$status" -eq 0 ] && [ ! -s "$work/lint-sorted.txt" ]; then
  echo "No problems."
else
  block "$work/lint-sorted.txt" 40
  echo "exit code: $status (the linter lists code that is probably wrong; it does not stop the build)"
fi

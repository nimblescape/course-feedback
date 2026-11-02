#!/usr/bin/env bash
# Automatic checks for JavaScript that runs as it is, without a build: a syntax
# check of every JavaScript file with `node --check` (a type annotation in a
# .js file is a syntax error), then, for a Node.js program (`main.js` and no
# `index.html`), one run with `node main.js`. Prints Markdown facts for the
# prompt (see scripts/check-lib.sh).
#
# Usage: check.sh <assignment-path>   (relative to the course repository)
#
# Environment: FEEDBACK_CENTRAL, FEEDBACK_STATUS, FEEDBACK_WORK
#
# The checks work on a copy of the workspace and run in the sandbox
# (scripts/sandbox.sh). Math.random() is repeatable
# (skills/typescript/tools/seed-random.mjs).

set -uo pipefail

# shellcheck source=/dev/null
source "$FEEDBACK_CENTRAL/scripts/check-lib.sh"

assignment="${1%/}"
workspace="$assignment/workspace"
work="$FEEDBACK_WORK/javascript"
copy="$work/workspace"
rm -rf "$work"
mkdir -p "$work"
cp -r "$workspace" "$copy"
rm -rf "$copy/node_modules" "$copy/dist"
cp "$FEEDBACK_CENTRAL/skills/typescript/tools/seed-random.mjs" "$work/"

mapfile -t files < <(cd "$copy" && find . \( -name '*.js' -o -name '*.mjs' -o -name '*.cjs' \) -type f | sed 's#^\./##' | LC_ALL=C sort)
[ "${#files[@]}" -gt 0 ] || exit 0

clean() { # <file>: short paths, no Node.js internals
  sed -i -e "s#file://$copy/##g; s#$copy/##g; s#$work/##g" \
    -e '/^ *at .*node:internal\//d; /^Node\.js v[0-9]/d' "$1"
}

echo "### Syntax check (\`node --check\`)"
echo
failed=0
for file in "${files[@]}"; do
  SANDBOX_CHDIR="$copy" bash "$FEEDBACK_CENTRAL/scripts/sandbox.sh" "$work" -- \
    timeout 30 node --check "$file" > "$work/syntax.txt" 2>&1
  status=$?
  if [ "$status" -ne 0 ]; then
    failed=$((failed + 1))
    clean "$work/syntax.txt"
    echo "\`$file\`:"
    echo
    block "$work/syntax.txt" 20
    echo
  fi
done
if [ "$failed" -eq 0 ]; then
  echo "No errors in $(printf '`%s`, ' "${files[@]}" | sed 's/, $//')."
else
  does_not_run syntax
  echo "A file with a syntax error does not run at all: the browser or Node.js stops before its first line."
fi
echo

if [ -f "$copy/index.html" ]; then
  echo "The work is a page (\`index.html\`): its JavaScript was checked for syntax errors, not run in a browser."
  exit 0
fi
[ -f "$copy/main.js" ] || exit 0
if [ "$failed" -gt 0 ]; then
  echo "The program was not run: it has syntax errors."
  exit 0
fi

echo "### Run of \`main.js\` (\`node main.js\`)"
echo
SANDBOX_CHDIR="$copy" bash "$FEEDBACK_CENTRAL/scripts/sandbox.sh" "$work" -- \
  timeout 10 node --import "$work/seed-random.mjs" main.js < /dev/null > "$work/run.txt" 2>&1
status=$?
clean "$work/run.txt"
block "$work/run.txt" 80
case "$status" in
  0) echo "exit code: 0" ;;
  124)
    echo "exit code: 124 – stopped after 10 seconds"
    does_not_run timeout
    ;;
  *)
    echo "exit code: $status – the program stopped with an error"
    does_not_run crash
    ;;
esac

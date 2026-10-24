#!/usr/bin/env bash
# Automatic checks for TypeScript work with Microsoft's TypeScript compiler and
# Node.js, no Deno: the type check, then one program run per prepared set of
# answers for prompt(). Prints Markdown facts for the prompt (see
# scripts/check-lib.sh).
#
# Usage: check.sh <assignment-path>
#
# Environment: FEEDBACK_CENTRAL, FEEDBACK_TOOLS, FEEDBACK_STATUS, FEEDBACK_WORK
# (temporary folder of this assignment), FEEDBACK_INPUTS (folder with 1.txt,
# 2.txt, …: one answer per line; the first set is the README's example run).
#
# Deno-style programs run unchanged: tools/deno-compat.mjs provides prompt(),
# the Deno file functions that the courses teach and jsr: imports, and makes
# Math.random() repeatable.

set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=/dev/null
source "$FEEDBACK_CENTRAL/scripts/check-lib.sh"

workspace="$1/workspace"
work="$FEEDBACK_WORK/typescript"
copy="$work/workspace"
out="$work/out"
rm -rf "$work"
mkdir -p "$work"

tools=$(install_tools "$here/tools" typescript)
if [ ! -x "$tools/node_modules/.bin/tsc" ]; then
  echo "The TypeScript tools could not be installed: no automatic check."
  exit 0
fi
[ -f "$tools/jsr-modules.d.ts" ] || node "$tools/jsr-types.mjs"

# The checks work on a copy: they never change the checkout, and every run
# starts with the same files.
cp -r "$workspace" "$copy"
rm -rf "$copy/node_modules" "$copy/dist"

# Like `deno check main.ts`: main.ts and everything it imports, otherwise every
# .ts file. A workspace with index.html is a browser program: type check only.
if [ -f "$copy/main.ts" ]; then
  entries=("$copy/main.ts")
else
  mapfile -t entries < <(find "$copy" -name '*.ts' -type f | sort)
fi
[ "${#entries[@]}" -gt 0 ] || exit 0
browser=false
[ ! -f "$copy/index.html" ] || browser=true

files=$(printf '%s\n' "$tools/deno-compat.d.ts" "$tools/jsr-modules.d.ts" "${entries[@]}" | jq -R . | jq -s .)
jq -n --arg root "$copy" --arg out "$out" --argjson files "$files" --argjson browser "$browser" '{
  compilerOptions: {
    strict: true, target: "ES2024", module: "esnext", moduleResolution: "bundler",
    moduleDetection: "force", allowImportingTsExtensions: true,
    rewriteRelativeImportExtensions: true, lib: ["ES2024", "DOM", "DOM.Iterable"],
    types: [], skipLibCheck: true, noEmitOnError: true, sourceMap: true,
    rootDir: $root, outDir: $out, noEmit: $browser
  },
  files: $files
}' > "$work/tsconfig.json"

echo "### Type check (\`tsc\`, strict, like \`deno check\`)"
echo
(cd "$copy" && timeout 120 "$tools/node_modules/.bin/tsc" -p "$work/tsconfig.json" --pretty false) > "$work/tsc.txt" 2>&1
status=$?
sed -i "s#$copy/##g" "$work/tsc.txt"
if [ "$status" -eq 0 ]; then
  echo "No errors."
else
  block "$work/tsc.txt" 40
  echo "exit code: $status"
  does_not_run typecheck
  echo
  echo "The program was not run: it has type errors (like F5 in VS Code)."
  exit 0
fi
echo

if $browser; then
  echo "The work is a browser program (\`index.html\`): it was type-checked, not run."
  exit 0
fi
[ -f "$copy/main.ts" ] || exit 0
echo '{ "type": "module" }' > "$out/package.json"

inputs=()
for file in "${FEEDBACK_INPUTS:-/nonexistent}"/*.txt; do
  [ -f "$file" ] && inputs+=("$file")
done
if [ "${#inputs[@]}" -eq 0 ]; then
  inputs=(/dev/null)
  if grep -q 'prompt(' "$copy"/*.ts 2>/dev/null; then
    echo "There are no prepared answers for this assignment: the run stops at the first \`prompt()\`."
    echo
  fi
fi

number=0
for input in "${inputs[@]}"; do
  number=$((number + 1))
  run="$work/run-$number"
  cp -r "$copy" "$run"
  if [ "$input" = /dev/null ]; then
    echo "### Run of \`main.ts\`"
  else
    answers=$(sed 's/^$/(empty)/' "$input" | paste -sd '|' - | sed 's/|/ · /g')
    if [ "$number" -eq 1 ]; then
      echo "### Run $number: example run of the README"
    else
      echo "### Run $number"
    fi
    echo
    echo "Answers for \`prompt()\`, in this order: $answers"
  fi
  echo
  bash "$FEEDBACK_CENTRAL/scripts/sandbox.sh" "$run" "$tools" "$out" -- \
    timeout 10 node --enable-source-maps --import "$tools/deno-compat.mjs" "$out/main.js" \
    < "$input" > "$work/run-$number.txt" 2>&1
  status=$?
  sed -i -e "s#$run/##g; s#$copy/##g; s#$out/##g" -e '/^ *at .*(node:internal\//d; /^ *at node:internal\//d; /^Node\.js v[0-9]/d' "$work/run-$number.txt"
  block "$work/run-$number.txt" 80
  case "$status" in
    0) echo "exit code: 0" ;;
    124)
      echo "exit code: 124 – stopped after 10 seconds"
      [ "$number" -gt 1 ] || does_not_run timeout
      ;;
    *)
      echo "exit code: $status – the program stopped with an error"
      [ "$number" -gt 1 ] || does_not_run crash
      ;;
  esac
  echo
done

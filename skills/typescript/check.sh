#!/usr/bin/env bash
# Automatic checks for TypeScript work with Microsoft's TypeScript compiler and
# Node.js, no Deno: the type check, then one program run per prepared set of
# answers for prompt(). Prints Markdown facts for the prompt (see
# scripts/check-lib.sh).
#
# Usage: check.sh <assignment-path>   (relative to the course repository)
#
# Environment: FEEDBACK_CENTRAL, FEEDBACK_REPOSITORY, FEEDBACK_TOOLS,
# FEEDBACK_STATUS, FEEDBACK_WORK (temporary folder of this assignment),
# FEEDBACK_INPUTS (folder with 1.txt, 2.txt, …: one answer per line; the first
# set is the README's example run).
#
# The course file .github/feedback.yml says how the students run their code:
#   runtime: node            exactly as the students' `npm start`: the course's
#                            own npm packages (package-lock.json: TypeScript,
#                            tsx, @majikmate/ts-utils, …), tsc with a tsconfig
#                            that extends the course's root tsconfig.json, then
#                            tsx runs main.ts.
#   runtime: deno (default)  Deno-style programs run unchanged:
#                            tools/deno-compat.mjs provides prompt(), the Deno
#                            file functions that the courses teach and jsr:
#                            imports; tsc checks like `deno check`.
# Both make Math.random() repeatable (tools/seed-random.mjs). The type check and
# the runs happen in the sandbox (scripts/sandbox.sh).

set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=/dev/null
source "$FEEDBACK_CENTRAL/scripts/check-lib.sh"

runtime=$(python3 "$FEEDBACK_CENTRAL/scripts/feedback.py" course runtime)
runtime="${runtime:-deno}"
assignment="${1%/}"
workspace="$assignment/workspace"
work="$FEEDBACK_WORK/typescript"
# The checks work on a copy with the layout of the course repository, so that
# relative paths in tsconfig.json files work. They never change the checkout,
# and every run starts with the same files.
repo="$work/repo"
copy="$repo/$workspace"
out="$work/out"
rm -rf "$work"
mkdir -p "$repo/$assignment" "$out"

# A workspace that is its own npm project (Vite, React) needs its own
# dependencies and scripts: not covered by this check yet.
if [ -f "$workspace/package.json" ]; then
  echo "The workspace is its own npm project (\`package.json\`): the automatic TypeScript check does not cover it yet."
  exit 0
fi

tools=$(install_tools "$here/tools" typescript)
if [ "$runtime" = node ]; then
  # The course's own npm packages in the exact versions of its package-lock.json
  # (a course file), like `npm ci`, installed outside the checkout without
  # install scripts
  if [ ! -f package-lock.json ]; then
    echo "The course has no \`package-lock.json\`: no automatic TypeScript check."
    exit 0
  fi
  mkdir -p "$work/npm"
  cp package.json package-lock.json "$work/npm/"
  key=$(cat package.json package-lock.json | sha256sum | cut -c 1-16)
  packages=$(install_tools "$work/npm" "course-$key")
else
  packages="$tools"
fi
if [ ! -f "$packages/node_modules/typescript/bin/tsc" ]; then
  if [ "$runtime" = node ]; then
    echo "The course's npm packages could not be installed (\`npm ci\` with its \`package-lock.json\`): no automatic check."
  else
    echo "The TypeScript tools could not be installed: no automatic check."
  fi
  exit 0
fi
[ "$runtime" = node ] || [ -f "$tools/jsr-modules.d.ts" ] || node "$tools/jsr-types.mjs"

cp -r "$workspace" "$copy"
rm -rf "$copy/node_modules" "$copy/dist"
if [ "$runtime" = node ]; then
  # Like `npm start`: the root package.json (module type) and tsconfig.json; a
  # tsconfig.json in the workspace does not count.
  rm -f "$copy"/tsconfig*.json
  for file in package.json tsconfig.json; do
    [ ! -f "$file" ] || cp "$file" "$repo/"
  done
  ln -s "$packages/node_modules" "$repo/node_modules"
fi

# Like `deno check main.ts` or `npx tsc`: main.ts and everything it imports,
# otherwise every .ts file. A workspace with index.html is a browser program:
# type check only.
if [ -f "$copy/main.ts" ]; then
  entries=("$copy/main.ts")
else
  mapfile -t entries < <(find "$copy" -name '*.ts' -type f | sort)
fi
[ "${#entries[@]}" -gt 0 ] || exit 0
browser=false
[ ! -f "$copy/index.html" ] || browser=true

if [ "$runtime" = node ]; then
  # The course's root tsconfig.json, limited to the files of this workspace
  files=$(printf '%s\n' "${entries[@]}" | jq -R . | jq -s .)
  if [ -f "$repo/tsconfig.json" ]; then
    base=$(jq -n --arg config "$repo/tsconfig.json" '{extends: $config}')
    heading="### Type check (\`tsc\` with the course's \`tsconfig.json\`, like \`npm start\`)"
  else
    base='{"compilerOptions": {"strict": true, "target": "ES2024", "module": "nodenext", "lib": ["ES2024"],
      "types": ["node"], "noEmit": true, "allowImportingTsExtensions": true,
      "verbatimModuleSyntax": true}}'
    heading="### Type check (\`tsc\`, strict; the course has no \`tsconfig.json\`)"
  fi
  # The DOM types for a browser program
  dom=$browser
  jq -n --argjson base "$base" --arg types "$packages/node_modules/@types" --argjson files "$files" \
    --argjson dom "$dom" '$base * {
    compilerOptions: ({noEmit: true, typeRoots: [$types]}
      + (if $dom then {lib: ["ES2024", "DOM", "DOM.Iterable"]} else {} end)),
    files: $files, include: []
  }' > "$work/tsconfig.json"
else
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
  heading="### Type check (\`tsc\`, strict, like \`deno check\`)"
fi

echo "$heading"
echo
SANDBOX_CHDIR="$copy" bash "$FEEDBACK_CENTRAL/scripts/sandbox.sh" "$work" "$tools" "$packages" -- \
  timeout 120 node "$packages/node_modules/typescript/bin/tsc" -p "$work/tsconfig.json" --pretty false \
  > "$work/tsc.txt" 2>&1
status=$?
sed -i -e "s#$copy/##g; s#$repo/##g; s#$packages/##g" "$work/tsc.txt"
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
if [ "$runtime" = node ]; then
  # tsx of the course (found through node_modules next to the copy)
  command=(node --import "$tools/seed-random.mjs" --import tsx main.ts)
  no_input="\`prompt()\` gets no input and returns \`null\`."
else
  echo '{ "type": "module" }' > "$out/package.json"
  command=(node --enable-source-maps --import "$tools/deno-compat.mjs" "$out/main.js")
  no_input="the run stops at the first \`prompt()\`."
fi

inputs=()
for file in "${FEEDBACK_INPUTS:-/nonexistent}"/*.txt; do
  [ -f "$file" ] && inputs+=("$file")
done
if [ "${#inputs[@]}" -eq 0 ]; then
  inputs=(/dev/null)
  if grep -q 'prompt(' "$copy"/*.ts 2>/dev/null; then
    echo "There are no prepared answers for this assignment: $no_input"
    echo
  fi
fi

number=0
for input in "${inputs[@]}"; do
  number=$((number + 1))
  # A fresh copy of the repository layout for every run, started in the workspace
  run="$work/run-$number"
  mkdir -p "$run"
  cp -a "$repo" "$run/repo"
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
  SANDBOX_CHDIR="$run/repo/$workspace" bash "$FEEDBACK_CENTRAL/scripts/sandbox.sh" "$run" "$tools" "$packages" "$out" -- \
    timeout 10 "${command[@]}" < "$input" > "$work/run-$number.txt" 2>&1
  status=$?
  sed -i -e "s#$run/repo/$workspace/##g; s#$run/repo/##g; s#$copy/##g; s#$out/##g; s#$packages/##g; s#$tools/##g" \
    -e '/^ *at .*(node:internal\//d; /^ *at node:internal\//d; /^Node\.js v[0-9]/d' "$work/run-$number.txt"
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

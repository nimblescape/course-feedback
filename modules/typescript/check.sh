#!/usr/bin/env bash
# Automatic checks for TypeScript work. Prints Markdown facts for the prompt.
# Never fails: a failing check is a fact for the feedback, not an error.
#
# Usage: check.sh <assignment-path>

set -uo pipefail

workspace="$1/workspace"
cd "$workspace" || exit 0

limit() { head -n "${1:-40}"; }

# Student programs may read and write files in their workspace, nothing else
# (no environment variables, no network, no other programs).
PERMISSIONS=(--allow-read=. --allow-write=.)

if [ -f deno.json ] || [ -f deno.jsonc ]; then
  if deno task 2>&1 | grep -q '^- check'; then
    echo "### \`deno task check\`"
    echo '```text'
    timeout 120 deno task check 2>&1 | limit 40
    echo "exit code: ${PIPESTATUS[0]}"
    echo '```'
  fi
  if deno task 2>&1 | grep -q '^- build'; then
    echo "### \`deno task build\`"
    echo '```text'
    timeout 120 deno task build 2>&1 | limit 20
    echo "exit code: ${PIPESTATUS[0]}"
    echo '```'
  fi
fi

[ -f main.ts ] || exit 0

echo "### \`deno check main.ts\`"
echo '```text'
timeout 60 deno check main.ts 2>&1 | limit 40
echo "exit code: ${PIPESTATUS[0]}"
echo '```'

if grep -q 'prompt(' ./*.ts 2>/dev/null; then
  echo "The program uses \`prompt()\`: it was not run here. Run it with"
  echo "\`python3 .feedback/scripts/run-with-input.py $workspace/main.ts <answers…>\`."
else
  echo "### \`deno run ${PERMISSIONS[*]} main.ts\`"
  echo '```text'
  timeout 30 deno run "${PERMISSIONS[@]}" main.ts 2>&1 | limit 60
  echo "exit code: ${PIPESTATUS[0]} (124 = stopped after 30 s)"
  echo '```'
fi

#!/usr/bin/env bash
# Automatic checks for HTML/CSS work. Prints Markdown facts for the prompt.
# Never fails: a failing check is a fact for the feedback, not an error.
#
# Usage: check.sh <assignment-path>

set -uo pipefail

workspace="$1/workspace"
[ -d "$workspace" ] || exit 0

shopt -s nullglob
html_files=("$workspace"/*.html)
[ "${#html_files[@]}" -gt 0 ] || { echo "No HTML file in \`$workspace\`."; exit 0; }

echo "### HTML-validate (presets recommended, prettier)"
echo '```text'
# Own installation (once per run, outside the repository) and own config file:
# files in the student repository (.htmlvalidate.json, package.json,
# node_modules) cannot change the check.
validator="${RUNNER_TEMP:-/tmp}/feedback-html-validate"
mkdir -p "$validator"
echo '{ "root": true, "extends": ["html-validate:recommended", "html-validate:prettier"] }' > "$validator/htmlvalidate.json"
if [ -x "$validator/node_modules/.bin/html-validate" ] \
  || timeout 120 npm install --silent --no-audit --no-fund --prefix "$validator" html-validate >/dev/null 2>&1; then
  timeout 120 "$validator/node_modules/.bin/html-validate" --config "$validator/htmlvalidate.json" "${html_files[@]}" 2>&1 | head -n 60
  echo "exit code: ${PIPESTATUS[0]} (0 = valid)"
else
  echo "html-validate could not be installed."
fi
echo '```'

browser=$(command -v google-chrome || command -v chromium || command -v chromium-browser || true)
if [ -n "$browser" ] && [ -f "$workspace/index.html" ]; then
  screenshot=/tmp/feedback-screenshot.png
  rm -f "$screenshot"
  timeout 60 "$browser" --headless --disable-gpu --no-sandbox --hide-scrollbars \
    --window-size=1280,900 --screenshot="$screenshot" \
    "file://$(realpath "$workspace/index.html")" >/dev/null 2>&1
  if [ -f "$screenshot" ]; then
    echo "A screenshot of \`index.html\` (1280×900) is in \`$screenshot\`; the"
    echo "design reference is in \`$1/static/\`."
  fi
fi

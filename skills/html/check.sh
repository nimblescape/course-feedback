#!/usr/bin/env bash
# Automatic checks for HTML/CSS work: whether the page can render at all and
# html-validate with the presets the students see in VS Code. Prints Markdown
# facts for the prompt (see scripts/check-lib.sh).
#
# Usage: check.sh <assignment-path>
#
# Environment: FEEDBACK_CENTRAL, FEEDBACK_TOOLS, FEEDBACK_STATUS

set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=/dev/null
source "$FEEDBACK_CENTRAL/scripts/check-lib.sh"

workspace="$1/workspace"
shopt -s nullglob
html_files=("$workspace"/*.html)

echo "### Page"
echo
if [ ! -f "$workspace/index.html" ]; then
  echo "\`index.html\` is missing."
  does_not_run no-page
else
  # Does index.html use a stylesheet of the workspace? Without one, no CSS rule
  # of the student applies. In a Vite project, a module of the page imports the
  # stylesheet instead (`import "./index.css";` in src/main.tsx).
  python3 - "$workspace" <<'EOF'
import re, sys
from html.parser import HTMLParser
from pathlib import Path

workspace = Path(sys.argv[1])
SKIPPED = {"node_modules", "dist"}

def files(pattern):
    return sorted(p for p in workspace.rglob(pattern)
                  if p.is_file() and not SKIPPED.intersection(p.relative_to(workspace).parts))

class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.sheets, self.style = [], False
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "link" and "stylesheet" in (attrs.get("rel") or "").lower().split():
            self.sheets.append(attrs.get("href") or "")
        if tag == "style":
            self.style = True

page = Links()
page.feed((workspace / "index.html").read_text(encoding="utf-8", errors="replace"))
# A path that starts with / is relative to the workspace (the root of a Vite project)
found = [href for href in page.sheets if (workspace / href.split("?")[0].split("#")[0].lstrip("/")).is_file()]
own_css = [p for p in files("*.css") if "{" in p.read_text(encoding="utf-8", errors="replace")]
print(f"Stylesheets linked in `index.html`: {', '.join(f'`{h}`' for h in page.sheets) or 'none'}"
      + (f" (missing files: {', '.join(f'`{h}`' for h in page.sheets if h not in found)})" if len(found) < len(page.sheets) else ""))
imported = []
for pattern in ["*.ts", "*.tsx", "*.mts", "*.js", "*.jsx", "*.mjs"]:
    for module in files(pattern):
        text = module.read_text(encoding="utf-8", errors="replace")
        for path in re.findall(r"""^\s*import\s+["']([^"']+\.css)["']""", text, re.M):
            target = workspace / path.lstrip("/") if path.startswith("/") else module.parent / path
            if target.is_file() and workspace.resolve() in target.resolve().parents:
                imported.append(f"`{target.resolve().relative_to(workspace.resolve())}` (in `{module.relative_to(workspace)}`)")
if imported:
    print(f"Stylesheets imported by modules: {', '.join(imported)}")
if own_css and not found and not imported and not page.style:
    print("The stylesheet is not linked: none of the CSS rules applies.")
    sys.exit(1)
EOF
  [ $? -ne 1 ] || does_not_run no-stylesheet
fi
echo
[ "${#html_files[@]}" -gt 0 ] || exit 0

echo "### HTML-validate (presets recommended and prettier, as in VS Code)"
echo
# Own installation and own config file: files in the student repository
# (.htmlvalidate.json, package.json, node_modules) cannot change the check.
tools=$(install_tools "$here/tools" html)
if [ ! -x "$tools/node_modules/.bin/html-validate" ]; then
  echo "html-validate could not be installed: no validation."
  exit 0
fi
work=$(mktemp -d)
(cd "$workspace" && timeout 120 "$tools/node_modules/.bin/html-validate" --config "$tools/htmlvalidate.json" \
  --formatter text ./*.html) > "$work/validate.txt" 2>&1
status=$?
if [ "$status" -eq 0 ]; then
  echo "No errors."
else
  block "$work/validate.txt" 60
  echo "exit code: $status (validation errors do not stop the page from rendering)"
fi
rm -rf "$work"

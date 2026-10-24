# shellcheck shell=bash
# Helpers for the check scripts of the feedback skills (source this file).
#
# A check script prints Markdown facts for the prompt and never fails: a failing
# check is a fact for the feedback, not an error. When the work does not run, it
# writes a line `does-not-run <reason>` to "$FEEDBACK_STATUS"; the reasons are
# named in locales/*.yml.

# Prints a file as a fenced text block that its content cannot close, at most
# <lines> lines, with terminal colour codes shown as ␛ and no other control
# characters.
block() {
  local file="$1" lines="${2:-60}" fence='```' text
  text=$(head -n "$lines" "$file" | head -c 12000 | sed 's/\x1b/␛/g' | tr -d '\000-\010\013\014\016-\037')
  while printf '%s' "$text" | grep -qF -- "$fence"; do fence="$fence\`"; done
  printf '%stext\n%s\n' "$fence" "$text"
  [ "$(wc -l < "$file")" -le "$lines" ] || echo "[… $(($(wc -l < "$file") - lines)) more lines]"
  printf '%s\n' "$fence"
}

does_not_run() {
  echo "does-not-run $1" >> "${FEEDBACK_STATUS:-/dev/null}"
}

# Installs the tools of a check (tools/package.json and package-lock.json next
# to the check script) once per run, outside the course checkout, with the
# exact versions of the lock file. Prints the installation folder.
install_tools() {
  local source="$1" target="$FEEDBACK_TOOLS/$2"
  if [ ! -f "$target/.installed" ]; then
    rm -rf "$target"
    mkdir -p "$target"
    cp -r "$source"/. "$target/"
    (cd "$target" && timeout 300 npm ci --ignore-scripts --no-audit --no-fund --silent >/dev/null 2>&1) \
      && touch "$target/.installed"
  fi
  echo "$target"
}

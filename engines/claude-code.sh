#!/usr/bin/env bash
# Engine: Claude Code. Billed through the Claude Max plan of the OAuth token
# (or, with ANTHROPIC_API_KEY, through an Anthropic API account).
#
# Usage: claude-code.sh secrets   (names of the secrets this engine needs)
#        claude-code.sh install
#        claude-code.sh run <model> <prompt-file>
#
# Needs the secret CLAUDE_CODE_OAUTH_TOKEN (created once with
# `claude setup-token`) or ANTHROPIC_API_KEY.

set -euo pipefail

case "${1:-}" in
  secrets)
    echo CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY
    ;;
  install)
    if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
      echo "::error::The engine 'claude-code' needs the secret CLAUDE_CODE_OAUTH_TOKEN (or ANTHROPIC_API_KEY)."
      exit 1
    fi
    command -v claude >/dev/null 2>&1 || npm install --global @anthropic-ai/claude-code
    # The credential scrub (see run) needs bubblewrap. Ubuntu 24.04 blocks the
    # user namespaces that bubblewrap uses unless this AppArmor switch is off.
    command -v bwrap >/dev/null 2>&1 || sudo apt-get install -y -qq bubblewrap >/dev/null
    sudo sysctl -q -w kernel.apparmor_restrict_unprivileged_userns=0 2>/dev/null || true
    if ! bwrap --ro-bind / / --dev /dev --proc /proc --unshare-pid true; then
      echo "::error::bubblewrap does not work on this runner; the engine 'claude-code' cannot hide its secret from the agent's commands."
      exit 1
    fi
    ;;
  run)
    model="$2"
    prompt_file="$3"
    # Claude Code has no agent files in .github/agents: pass the agent text
    # (without its front matter) as system prompt.
    agent="$(awk 'NR == 1 && /^---$/ { fm = 1; next } fm { if (/^---$/) fm = 0; next } { print }' .github/agents/Feedback.agent.md)"
    # CLAUDE_CODE_SUBPROCESS_ENV_SCRUB removes the token from every command the
    # agent runs, so a student program cannot read it. With the scrub, Claude
    # Code ignores --dangerously-skip-permissions: the allowed tools are listed,
    # everything else is denied. Edit rules also cover creating files.
    CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1 claude \
      --print \
      --model "$model" \
      --append-system-prompt "$agent" \
      --allowedTools \
      "Read" "Grep" "Glob" "TodoWrite" \
      "Edit(./20-assignments/**/FEEDBACK.md)" "Edit(//tmp/**)" \
      "Bash(deno check *)" "Bash(deno run *)" \
      "Bash(python3 .feedback/scripts/run-with-input.py *)" \
      "Bash(git log *)" "Bash(git diff *)" "Bash(git show *)" \
      "Bash(google-chrome *)" "Bash(chromium *)" \
      --disallowedTools \
      "WebFetch" "WebSearch" \
      "Bash(deno task *)" "Bash(npm *)" "Bash(npx *)" "Bash(curl *)" "Bash(wget *)" \
      < "$prompt_file"
    ;;
  *)
    echo "Usage: $0 secrets | install | run <model> <prompt-file>" >&2
    exit 2
    ;;
esac

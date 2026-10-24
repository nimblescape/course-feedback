#!/usr/bin/env bash
# Engine: GitHub Copilot CLI. Billed through the Copilot account of the token.
#
# Usage: copilot.sh secrets   (names of the secrets this engine needs)
#        copilot.sh install
#        copilot.sh run <model> <prompt-file>
#
# Needs the secret COPILOT_GITHUB_TOKEN (a token with Copilot access).

set -euo pipefail

case "${1:-}" in
  secrets)
    echo COPILOT_GITHUB_TOKEN
    ;;
  install)
    if [ -z "${COPILOT_GITHUB_TOKEN:-}" ]; then
      echo "::error::The engine 'copilot' needs the secret COPILOT_GITHUB_TOKEN."
      exit 1
    fi
    command -v copilot >/dev/null 2>&1 || curl -fsSL https://gh.io/copilot-install | sudo bash
    ;;
  run)
    model="$2"
    prompt_file="$3"
    # The agent is found by name in .github/agents/Feedback.agent.md.
    # --secret-env-vars removes the token from every command the agent runs, so
    # a student program cannot read it. No URL is allowed (no --allow-all-urls),
    # and the deny rules win over --allow-all-tools. --no-custom-instructions
    # skips AGENTS.md, CLAUDE.md and similar files, which students can write;
    # the agent reads its instruction files itself.
    copilot \
      --agent=Feedback \
      --no-custom-instructions \
      --model "$model" \
      --prompt "$(cat "$prompt_file")" \
      --allow-all-tools \
      --allow-all-paths \
      --secret-env-vars=COPILOT_GITHUB_TOKEN \
      --excluded-tools=web_fetch \
      --deny-tool='shell(deno task:*)' \
      --deny-tool='shell(npm:*)' \
      --deny-tool='shell(npx:*)' \
      --deny-tool='shell(curl:*)' \
      --deny-tool='shell(wget:*)'
    ;;
  *)
    echo "Usage: $0 secrets | install | run <model> <prompt-file>" >&2
    exit 2
    ;;
esac

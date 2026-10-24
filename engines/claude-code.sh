#!/usr/bin/env bash
# Engine: Claude Code. Billed through the Claude Max plan of the OAuth token
# (or, with ANTHROPIC_API_KEY, through an Anthropic API account).
#
# Usage: claude-code.sh secrets                    names of the secrets it needs
#        claude-code.sh install <version>          CLI version from config.yml
#        claude-code.sh run <model> <prompt-file>  prints the model's answer
#
# Needs the secret CLAUDE_CODE_OAUTH_TOKEN (created once with
# `claude setup-token`) or ANTHROPIC_API_KEY.
#
# The model gets the prompt and nothing else: no tools (it cannot run commands
# or read files), no MCP servers, no project settings, CLAUDE.md or skills, and
# it runs in an empty folder, so nothing from the student repository reaches it.

set -euo pipefail

case "${1:-}" in
  secrets)
    echo CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY
    ;;
  install)
    version="$2"
    if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
      echo "::error::The engine 'claude-code' needs the secret CLAUDE_CODE_OAUTH_TOKEN (or ANTHROPIC_API_KEY)."
      exit 1
    fi
    if [ "$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)" != "$version" ]; then
      npm install --global --silent "@anthropic-ai/claude-code@$version"
    fi
    claude --version | head -n 1
    ;;
  run)
    model="$2"
    prompt_file="$(realpath "$3")"
    cd "$(mktemp -d)"
    DISABLE_AUTOUPDATER=1 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 claude \
      --print \
      --model "$model" \
      --tools "" \
      --strict-mcp-config \
      --setting-sources user \
      --no-session-persistence \
      --system-prompt "You give feedback on a student's assignment as the prompt describes. Answer only with the JSON object that the prompt asks for." \
      < "$prompt_file"
    ;;
  *)
    echo "Usage: $0 secrets | install <version> | run <model> <prompt-file>" >&2
    exit 2
    ;;
esac

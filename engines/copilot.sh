#!/usr/bin/env bash
# Engine: GitHub Copilot CLI. Billed through the Copilot account of the token.
#
# Usage: copilot.sh secrets                    names of the secrets it needs
#        copilot.sh install <version>          CLI version from config.yml
#        copilot.sh run <model> <prompt-file>  prints the model's answer
#
# Needs the secret COPILOT_GITHUB_TOKEN (a token with Copilot access).
#
# The model gets the prompt and nothing else: no tools (it cannot run commands
# or read files), no MCP servers, no custom instructions, and it runs in an
# empty folder, so nothing from the student repository reaches it.

set -euo pipefail

case "${1:-}" in
  secrets)
    echo COPILOT_GITHUB_TOKEN
    ;;
  install)
    version="$2"
    if [ -z "${COPILOT_GITHUB_TOKEN:-}" ]; then
      echo "::error::The engine 'copilot' needs the secret COPILOT_GITHUB_TOKEN."
      exit 1
    fi
    if [ "$(copilot --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)" != "$version" ]; then
      npm install --global --silent "@github/copilot@$version"
    fi
    copilot --version | head -n 1
    ;;
  run)
    model="$2"
    prompt_file="$(realpath "$3")"
    cd "$(mktemp -d)"
    copilot \
      --model "$model" \
      --available-tools=none \
      --disable-builtin-mcps \
      --no-custom-instructions \
      --no-color \
      --silent \
      < "$prompt_file"
    ;;
  *)
    echo "Usage: $0 secrets | install <version> | run <model> <prompt-file>" >&2
    exit 2
    ;;
esac

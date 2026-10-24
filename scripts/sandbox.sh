#!/usr/bin/env bash
# Runs a student program without network, without secrets and without access
# to the repository: only the given folder is writable, the tool folders are
# read-only, everything else is the read-only system.
#
# Usage: sandbox.sh <writable-folder> [<read-only-folder> ...] -- <command> [<arg> ...]
#
# The environment is empty except PATH, HOME, LANG and TZ (Europe/Vienna, the
# time of the students). Hidden: /tmp, the home folder, the runner's temporary
# folder (credentials of actions/checkout) and the course checkout (git
# credentials). stdin is passed on, so prepared answers can be piped in. The
# program starts in the writable folder, or in SANDBOX_CHDIR when set (a folder
# inside it).

set -euo pipefail

writable="$1"
shift
args=(--ro-bind / / --dev /dev --proc /proc --tmpfs /tmp --tmpfs "$HOME")
[ -z "${RUNNER_TEMP:-}" ] || args+=(--tmpfs "$RUNNER_TEMP")
args+=(--tmpfs "${FEEDBACK_REPOSITORY:-$PWD}")
while [ "$1" != "--" ]; do
  args+=(--ro-bind "$1" "$1")
  shift
done
shift
args+=(--bind "$writable" "$writable" --chdir "${SANDBOX_CHDIR:-$writable}")
args+=(--unshare-all --die-with-parent --new-session)
args+=(--clearenv --setenv PATH "$PATH" --setenv HOME "$writable" --setenv LANG C.UTF-8)
args+=(--setenv TZ Europe/Vienna)
exec bwrap "${args[@]}" "$@"

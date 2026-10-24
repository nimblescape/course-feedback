#!/usr/bin/env bash
# Pushes the feedback commits that scripts/run.sh made with FEEDBACK_PUSH=later.
#
# Runs from the root of the course checkout, as the last step of the course
# workflow, also when the feedback step failed (the finished feedback is kept).
#
# Usage: .feedback/scripts/push.sh
#
# Environment: BRANCH; optionally PUSH_TOKEN, a token of an organisation admin.
# The organisation ruleset lets only its bypass actors change FEEDBACK.md, and
# GITHUB_TOKEN cannot be one. Without PUSH_TOKEN, the credentials that
# actions/checkout stored for the course are used (GITHUB_TOKEN).

set -euo pipefail

if [ -n "${PUSH_TOKEN:-}" ]; then
  # Replace the stored Authorization header for github.com; an empty value
  # first clears the list of extra headers. Environment config is used instead
  # of -c, so the token never appears in a command line.
  header="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$PUSH_TOKEN" | base64 -w0)"
  export GIT_CONFIG_COUNT=2
  export GIT_CONFIG_KEY_0="http.https://github.com/.extraheader" GIT_CONFIG_VALUE_0=""
  export GIT_CONFIG_KEY_1="http.https://github.com/.extraheader" GIT_CONFIG_VALUE_1="$header"
fi

git fetch --quiet origin "$BRANCH"
if [ "$(git rev-list --count "origin/$BRANCH..HEAD")" -eq 0 ]; then
  echo "No feedback to push."
  exit 0
fi
echo "Feedback commits to push:"
git log --format='- %s' "origin/$BRANCH..HEAD"

for attempt in 1 2 3; do
  # Students may push meanwhile; they cannot change FEEDBACK.md, so the rebase
  # has no conflicts.
  if git -c rebase.autoStash=true pull --quiet --rebase origin "$BRANCH" \
    && git push --quiet origin "HEAD:$BRANCH"; then
    echo "✅ Pushed the feedback."
    exit 0
  fi
  echo "⚠️ Push failed (attempt $attempt/3)."
  [ "$attempt" -lt 3 ] && sleep 3
done
echo "::error::The feedback could not be pushed."
exit 1

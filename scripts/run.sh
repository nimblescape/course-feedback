#!/usr/bin/env bash
# Generates FEEDBACK.md files for the assignments of a course repository.
#
# Runs from the root of the course checkout; this repository is checked out in
# .feedback/. Called by the course workflow .github/workflows/feedback.yml.
#
# Usage: .feedback/scripts/run.sh changed|missing|all
#
#   changed  assignments whose workspace changed in the pushed commits
#   missing  assignments with student work but no FEEDBACK.md (nightly)
#   all      every assignment with student work (manual run)
#
# Environment: BRANCH, BEFORE and SHA (mode changed), the secret of the chosen
# engine (see engines/), FEEDBACK_CONFIG (path of the central config.yml).
# Pushing uses the credentials that actions/checkout stored for the course.
#
# Per assignment: automatic checks → prompt → model (no tools) → the answer is
# checked → FEEDBACK.md is written by scripts/feedback.py. See ARCHITECTURE.md.

set -euo pipefail

MODE="${1:-changed}"
export FEEDBACK_CENTRAL=".feedback"
export FEEDBACK_CONFIG="${FEEDBACK_CONFIG:-$FEEDBACK_CENTRAL/config.yml}"
export FEEDBACK_REPOSITORY="$PWD"
WORK="$(mktemp -d)"
export FEEDBACK_TOOLS="${RUNNER_TEMP:-$WORK}/feedback-tools"

if [ ! -f .github/feedback.yml ]; then
  echo "::error::.github/feedback.yml is missing (course id and language)."
  exit 1
fi

# PyYAML for feedback.py, bubblewrap for the sandbox of student programs.
# Ubuntu 24.04 blocks the user namespaces of bubblewrap unless this AppArmor
# switch is off.
python3 -c 'import yaml' 2>/dev/null || sudo apt-get install -y -qq python3-yaml >/dev/null
command -v bwrap >/dev/null 2>&1 || sudo apt-get install -y -qq bubblewrap >/dev/null
sudo sysctl -q -w kernel.apparmor_restrict_unprivileged_userns=0 2>/dev/null || true
if ! bwrap --ro-bind / / --dev /dev --proc /proc --unshare-all true; then
  echo "::error::bubblewrap does not work on this runner: student programs cannot run safely."
  exit 1
fi

feedback() { python3 "$FEEDBACK_CENTRAL/scripts/feedback.py" "$@"; }

# --- Settings ---------------------------------------------------------------

COURSE=$(python3 -c 'import yaml; print(yaml.safe_load(open(".github/feedback.yml"))["course"])')
ENABLED=$(feedback setting enabled)
ENGINE=$(feedback setting engine)
MODEL=$(feedback setting "models.$ENGINE")
ENGINE_VERSION=$(feedback setting "versions.$ENGINE")
MAX_ASSIGNMENTS=$(feedback setting max_assignments_per_run)

echo "Course: $COURSE · engine: $ENGINE $ENGINE_VERSION · model: $MODEL · node: $(node --version)"

if [ "$ENABLED" != "true" ]; then
  echo "Feedback is switched off in config.yml."
  exit 0
fi
ENGINE_SCRIPT="$FEEDBACK_CENTRAL/engines/$ENGINE.sh"
if [ ! -x "$ENGINE_SCRIPT" ]; then
  echo "::error::Unknown engine '$ENGINE' (no $ENGINE_SCRIPT)."
  exit 1
fi
if [ -z "$MODEL" ] || [ -z "$ENGINE_VERSION" ]; then
  echo "::error::config.yml needs models.$ENGINE and versions.$ENGINE."
  exit 1
fi

# Secrets: the chosen engine sees only its own secrets, the checks and student
# programs see none.
ALL_SECRETS="GH_TOKEN GITHUB_TOKEN"
for engine_script in "$FEEDBACK_CENTRAL"/engines/*.sh; do
  ALL_SECRETS="$ALL_SECRETS $(bash "$engine_script" secrets)"
done
ENGINE_SECRETS=$(bash "$ENGINE_SCRIPT" secrets)
for secret in $ALL_SECRETS; do
  case " $ENGINE_SECRETS " in
    *" $secret "*) ;;
    *) unset "$secret" ;;
  esac
done
export FEEDBACK_SECRETS="$ENGINE_SECRETS"

without_secrets() {
  local args=() secret
  for secret in $ENGINE_SECRETS; do args+=(-u "$secret"); done
  env "${args[@]}" "$@"
}

# --- Assignments ------------------------------------------------------------

case "$MODE" in
  changed)
    BASE="${BEFORE:-}"
    # New branch, or a force push whose old commit is gone: compare with the parent
    if [ -z "$BASE" ] || ! git cat-file -e "$BASE^{commit}" 2>/dev/null; then
      BASE=$(git rev-parse HEAD^ 2>/dev/null || git rev-parse HEAD)
    fi
    # Everything between 20-assignments/ and /workspace/ is the assignment folder
    CHANGED=$(git diff --name-only "$BASE" "${SHA:-HEAD}" \
      | sed -n 's|^20-assignments/\(.*\)/workspace/.*|\1|p' | sort -u)
    # shellcheck disable=SC2086
    ASSIGNMENTS=$([ -z "$CHANGED" ] || bash "$FEEDBACK_CENTRAL/scripts/has-implementation.sh" $CHANGED)
    ;;
  missing) ASSIGNMENTS=$(bash "$FEEDBACK_CENTRAL/scripts/has-implementation.sh" --missing-feedback-only) ;;
  all) ASSIGNMENTS=$(bash "$FEEDBACK_CENTRAL/scripts/has-implementation.sh") ;;
  *)
    echo "::error::Unknown mode '$MODE' (changed, missing or all)."
    exit 1
    ;;
esac

if [ -z "$ASSIGNMENTS" ]; then
  echo "No assignments with student work to process."
  exit 0
fi
COUNT=$(echo "$ASSIGNMENTS" | wc -l)
if [ "$COUNT" -gt "$MAX_ASSIGNMENTS" ]; then
  echo "::warning::$COUNT assignments, but max_assignments_per_run is $MAX_ASSIGNMENTS; the others are skipped in this run."
  ASSIGNMENTS=$(echo "$ASSIGNMENTS" | head -n "$MAX_ASSIGNMENTS")
fi
echo "Assignments:"
echo "$ASSIGNMENTS" | sed 's/^/- /'

echo "$FEEDBACK_CENTRAL/" >> .git/info/exclude
bash "$ENGINE_SCRIPT" install "$ENGINE_VERSION"
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

# --- Feedback ---------------------------------------------------------------

# Automatic checks of the feedback skills that match the work. Their Markdown
# goes into the prompt, their "does-not-run" lines into the status file.
run_checks() {
  local assignment_path="$1" folder
  export FEEDBACK_WORK="$WORK/checks"
  export FEEDBACK_STATUS="$WORK/status.txt"
  export FEEDBACK_INPUTS="$WORK/inputs"
  rm -rf "$FEEDBACK_WORK" "$FEEDBACK_INPUTS" "$FEEDBACK_STATUS"
  mkdir -p "$FEEDBACK_WORK"
  touch "$FEEDBACK_STATUS"
  feedback inputs "$assignment_path" "$FEEDBACK_INPUTS"
  while IFS=$'\t' read -r _ folder; do
    [ -f "$folder/check.sh" ] || continue
    without_secrets timeout 15m bash "$folder/check.sh" "$assignment_path" || true
  done < <(feedback skills "$assignment_path")
}

FAILED=""
for ASSIGNMENT in $ASSIGNMENTS; do
  ASSIGNMENT_PATH="20-assignments/$ASSIGNMENT"
  FEEDBACK="$ASSIGNMENT_PATH/FEEDBACK.md"
  echo "::group::$ASSIGNMENT"

  git -c rebase.autoStash=true pull --quiet --rebase origin "$BRANCH" || echo "Pull completed with warnings (ignored)"

  # Unchanged work since the last feedback needs no model run
  LAST=$(git log -1 --format=%H -- "$FEEDBACK" 2>/dev/null || true)
  if [ -f "$FEEDBACK" ] && [ -n "$LAST" ] && git diff --quiet "$LAST" HEAD -- "$ASSIGNMENT_PATH/workspace"; then
    echo "ℹ️ No changes since the last feedback."
    echo "::endgroup::"
    continue
  fi

  export FEEDBACK_TIME
  FEEDBACK_TIME=$(TZ=Europe/Vienna date '+%d.%m.%Y %H:%M')
  run_checks "$ASSIGNMENT_PATH" > "$WORK/checks.md"
  echo "Skills: $(feedback skills "$ASSIGNMENT_PATH" | cut -f1 | tr '\n' ' ')· status: $(tr '\n' ' ' < "$WORK/status.txt")"

  SUCCESS=false
  if feedback prompt "$ASSIGNMENT_PATH" "$WORK/checks.md" > "$WORK/prompt.md"; then
    echo "Prompt: $(wc -c < "$WORK/prompt.md") bytes"
    for ATTEMPT in 1 2 3; do
      if timeout 15m bash "$ENGINE_SCRIPT" run "$MODEL" "$WORK/prompt.md" > "$WORK/answer.txt" \
        && feedback render "$ASSIGNMENT_PATH" "$WORK/answer.txt" "$WORK/status.txt"; then
        SUCCESS=true
        break
      fi
      echo "⚠️ Attempt $ATTEMPT/3 failed for $ASSIGNMENT."
      [ "$ATTEMPT" -lt 3 ] && sleep 5
    done
  fi

  if [ "$SUCCESS" != true ]; then
    echo "❌ Giving up on $ASSIGNMENT"
    FAILED="$FAILED $ASSIGNMENT"
    echo "::endgroup::"
    continue
  fi

  PUSHED=false
  git add -- "$FEEDBACK"
  git commit --quiet -m "chore: update feedback for $ASSIGNMENT"
  for ATTEMPT in 1 2 3; do
    if git -c rebase.autoStash=true pull --quiet --rebase origin "$BRANCH" && git push --quiet origin "HEAD:$BRANCH"; then
      PUSHED=true
      echo "✅ Pushed feedback for $ASSIGNMENT"
      break
    fi
    echo "⚠️ Push failed for $ASSIGNMENT (attempt $ATTEMPT/3)."
    [ "$ATTEMPT" -lt 3 ] && sleep 3
  done
  [ "$PUSHED" = true ] || FAILED="$FAILED $ASSIGNMENT"
  echo "::endgroup::"
done

{
  echo "### Feedback ($MODE) · engine \`$ENGINE $ENGINE_VERSION\` · model \`$MODEL\`"
  echo
  echo "$ASSIGNMENTS" | sed 's/^/- `/; s/$/`/'
  [ -z "$FAILED" ] || printf '\n❌ Failed:%s\n' "$FAILED"
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"

if [ -n "$FAILED" ]; then
  echo "::error::Feedback could not be generated or pushed for:$FAILED"
  exit 1
fi

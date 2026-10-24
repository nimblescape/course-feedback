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

set -euo pipefail

MODE="${1:-changed}"
CENTRAL=".feedback"
CONFIG="${FEEDBACK_CONFIG:-$CENTRAL/config.yml}"
COURSE_CONFIG=".github/feedback.yml"
WORK="$(mktemp -d)"

# --- Settings ---------------------------------------------------------------

if [ ! -f "$COURSE_CONFIG" ]; then
  echo "::error::$COURSE_CONFIG is missing (course id and modules)."
  exit 1
fi
COURSE=$(yq -r '.course' "$COURSE_CONFIG")
MODULES=$(yq -r '.modules[]' "$COURSE_CONFIG")

# A course entry in config.yml replaces the global value (also when it is false)
setting() {
  local value
  value=$(yq -r ".courses.\"$COURSE\".$1" "$CONFIG")
  [ "$value" != null ] || value=$(yq -r ".$1" "$CONFIG")
  echo "$value"
}
ENABLED=$(setting enabled)
ENGINE=$(setting engine)
MODEL=$(setting "models.\"$ENGINE\"")
MAX_ASSIGNMENTS=$(setting max_assignments_per_run)

echo "Course: $COURSE · modules: $(echo "$MODULES" | tr '\n' ' ')· engine: $ENGINE · model: $MODEL"

if [ "$ENABLED" != "true" ]; then
  echo "Feedback is switched off in config.yml."
  exit 0
fi
ENGINE_SCRIPT="$CENTRAL/engines/$ENGINE.sh"
if [ ! -x "$ENGINE_SCRIPT" ]; then
  echo "::error::Unknown engine '$ENGINE' (no $ENGINE_SCRIPT)."
  exit 1
fi
if [ -z "$MODEL" ] || [ "$MODEL" = null ]; then
  echo "::error::config.yml has no model for the engine '$ENGINE' (models.$ENGINE)."
  exit 1
fi

# Secrets: the chosen engine sees only its own secrets, student programs and
# check scripts see none.
ALL_SECRETS="GH_TOKEN GITHUB_TOKEN"
for engine_script in "$CENTRAL"/engines/*.sh; do
  ALL_SECRETS="$ALL_SECRETS $(bash "$engine_script" secrets)"
done
ENGINE_SECRETS=$(bash "$ENGINE_SCRIPT" secrets)
for secret in $ALL_SECRETS; do
  case " $ENGINE_SECRETS " in
    *" $secret "*) ;;
    *) unset "$secret" ;;
  esac
done

# Runs a command without any secret in its environment
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
    ASSIGNMENTS=$([ -z "$CHANGED" ] || bash "$CENTRAL/scripts/has-implementation.sh" $CHANGED)
    ;;
  missing) ASSIGNMENTS=$(bash "$CENTRAL/scripts/has-implementation.sh" --missing-feedback-only) ;;
  all) ASSIGNMENTS=$(bash "$CENTRAL/scripts/has-implementation.sh") ;;
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

# --- Agent files ------------------------------------------------------------

# The central agent and rules are copied into the course checkout, where the
# engines expect them. They are never committed.
install_agent_files() {
  mkdir -p .github/agents .github/instructions
  cp "$CENTRAL/agent/Feedback.agent.md" .github/agents/Feedback.agent.md
  cp "$CENTRAL/agent/feedback-format.instructions.md" .github/instructions/
  local module
  for module in $MODULES; do
    if [ ! -f "$CENTRAL/modules/$module/rules.instructions.md" ]; then
      echo "::error::Unknown module '$module' in $COURSE_CONFIG."
      exit 1
    fi
    cp "$CENTRAL/modules/$module/rules.instructions.md" ".github/instructions/best-practices-$module.instructions.md"
  done
}

{
  echo "$CENTRAL/"
  echo ".github/agents/Feedback.agent.md"
  echo ".github/instructions/feedback-format.instructions.md"
  for module in $MODULES; do echo ".github/instructions/best-practices-$module.instructions.md"; done
} >> .git/info/exclude

bash "$ENGINE_SCRIPT" install
install_agent_files

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

# --- Helpers ----------------------------------------------------------------

# Undo every change except the given FEEDBACK.md (keep) or including it (drop).
# Ignored files (the agent files, .feedback/) stay.
reset_worktree() {
  local feedback="$1" keep="$2"
  if [ "$keep" = keep ] && [ -f "$feedback" ]; then cp "$feedback" "$WORK/FEEDBACK.md"; fi
  git reset --quiet --hard HEAD
  git clean --quiet -fd
  if [ "$keep" = keep ] && [ -f "$WORK/FEEDBACK.md" ]; then mv "$WORK/FEEDBACK.md" "$feedback"; fi
  install_agent_files
}

# Earlier feedback must stay untouched (only appending is allowed), the new
# part needs a score and the four sections, and no secret may appear in it.
valid_feedback() {
  local feedback="$1" old new part secret
  new=$(cat "$feedback")
  if git cat-file -e "HEAD:$feedback" 2>/dev/null; then
    old=$(git show "HEAD:$feedback")
    if [ "${new#"$old"}" = "$new" ] && [ -n "$old" ]; then
      echo "Earlier feedback was changed."
      return 1
    fi
    part="${new#"$old"}"
  else
    part="$new"
  fi
  # Non-breaking spaces (German typography) count as spaces
  part=$(printf '%s' "$part" | sed 's/\xc2\xa0/ /g; s/\xe2\x80\xaf/ /g')
  printf '%s\n' "$part" | grep -qE '[0-9] ?%' || { echo "No score in percent."; return 1; }
  [ "$(printf '%s\n' "$part" | grep -cE '^#{2,3} ')" -ge 4 ] || { echo "Fewer than four sections."; return 1; }
  for secret in $ENGINE_SECRETS; do
    if [ -n "${!secret:-}" ] && grep -qF -- "${!secret}" "$feedback"; then
      echo "FEEDBACK.md contains the secret $secret."
      return 1
    fi
  done
}

build_prompt() {
  local assignment_path="$1" feedback="$1/FEEDBACK.md" last module
  echo "Assignment path: $assignment_path"
  echo "Current time (Europe/Vienna): $(TZ=Europe/Vienna date '+%d.%m.%Y %H:%M')"
  echo "Course: $COURSE · modules: $(echo "$MODULES" | tr '\n' ' ')"
  echo
  last=$(git log -1 --format=%H -- "$feedback" 2>/dev/null || true)
  if [ -f "$feedback" ] && [ -n "$last" ]; then
    echo "FEEDBACK.md exists (last feedback commit ${last::7}). Changes in workspace/ since then:"
    echo '```text'
    git log --oneline "$last..HEAD" -- "$assignment_path/workspace" | head -n 30
    git diff --stat "$last" HEAD -- "$assignment_path/workspace" | tail -n 30
    echo '```'
  else
    echo "There is no FEEDBACK.md yet."
  fi
  echo
  echo "## Automatic checks (already run)"
  echo
  for module in $MODULES; do
    if [ -x "$CENTRAL/modules/$module/check.sh" ]; then
      without_secrets bash "$CENTRAL/modules/$module/check.sh" "$assignment_path" || true
    fi
  done
  echo
  echo "Use the Feedback agent: follow .github/agents/Feedback.agent.md and the"
  echo "instruction files it names, and create or update FEEDBACK.md in the"
  echo "assignment folder."
}

# --- Feedback ---------------------------------------------------------------

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

  build_prompt "$ASSIGNMENT_PATH" > "$WORK/prompt.md"
  reset_worktree "$FEEDBACK" drop # the checks may have written files

  SUCCESS=false
  for ATTEMPT in 1 2 3; do
    if timeout 15m bash "$ENGINE_SCRIPT" run "$MODEL" "$WORK/prompt.md"; then
      if ! git status --porcelain -- "$FEEDBACK" | grep -q .; then
        SUCCESS=true
        echo "ℹ️ The agent wrote no feedback (no student work or nothing changed)."
        break
      fi
      if valid_feedback "$FEEDBACK"; then
        SUCCESS=true
        break
      fi
    fi
    echo "⚠️ Attempt $ATTEMPT/3 failed for $ASSIGNMENT."
    reset_worktree "$FEEDBACK" drop
    [ "$ATTEMPT" -lt 3 ] && sleep 5
  done
  reset_worktree "$FEEDBACK" keep

  if [ "$SUCCESS" != true ]; then
    echo "❌ Giving up on $ASSIGNMENT"
    FAILED="$FAILED $ASSIGNMENT"
    reset_worktree "$FEEDBACK" drop
    echo "::endgroup::"
    continue
  fi

  if git status --porcelain -- "$FEEDBACK" | grep -q .; then
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
  fi
  echo "::endgroup::"
done

{
  echo "### Feedback ($MODE) · engine \`$ENGINE\` · model \`$MODEL\`"
  echo
  echo "$ASSIGNMENTS" | sed 's/^/- `/; s/$/`/'
  [ -z "$FAILED" ] || printf '\n❌ Failed:%s\n' "$FAILED"
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"

if [ -n "$FAILED" ]; then
  echo "::error::Feedback could not be generated or pushed for:$FAILED"
  exit 1
fi

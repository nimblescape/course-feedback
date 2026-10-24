#!/usr/bin/env bash
# Local end-to-end test of scripts/run.sh with a fake engine and the small
# course in tests/fixture/. Needs git, python3 with PyYAML, node, npm, jq and
# bubblewrap (the checks run for real).
#
# Usage: tests/run-tests.sh

set -uo pipefail

CENTRAL=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
PASSED=0
FAILED=0

expect() { # <description> <command…>
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    PASSED=$((PASSED + 1))
    echo "  ✅ $description"
  else
    FAILED=$((FAILED + 1))
    echo "  ❌ $description"
  fi
}

# Central repository with the fake engine
mkdir -p "$T/central"
tar -C "$CENTRAL" --exclude=./.git --exclude=./tests -cf - . | tar -C "$T/central" -xf -
cat > "$T/central/engines/fake.sh" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  secrets) echo FAKE_TOKEN ;;
  install) [ -n "${FAKE_TOKEN:-}" ] ;;
  run) python3 "$FAKE_ENGINE" "$3" ;;
esac
FAKE
chmod +x "$T/central/engines/fake.sh"
sed -e 's/^engine: copilot/engine: fake/' -e 's/^models:/models:\n  fake: fake-model/' \
  -e 's/^versions:/versions:\n  fake: "1"/' "$CENTRAL/config.yml" > "$T/config.yml"

# Course remote (the template state) and the student's clone
git init -q -b main "$T/template"
tar -C "$CENTRAL/tests/fixture" -cf - . | tar -C "$T/template" -xf -
git -C "$T/template" add -A
git -C "$T/template" -c user.name=t -c user.email=t@t commit -qm "Initial commit"
git clone -q --bare "$T/template" "$T/remote.git"
git clone -q "$T/remote.git" "$T/course"
cd "$T/course" || exit 1
git config user.name student
git config user.email s@s

TS=20-assignments/04-input/04.01-greeting
HTML=20-assignments/30-css-basics/30.01-card
GAME=20-assignments/15-project/15.01-game

student() { # <file> <content>
  git reset -q --hard origin/main
  git pull -q --rebase origin main
  printf '%s\n' "$2" > "$1"
  git add -A && git commit -qm "student: $1" && git push -q origin HEAD:main
}

run() { # <mode> <fake mode>
  rm -rf .feedback && cp -r "$T/central" .feedback
  env FAKE_TOKEN=fake-secret-1234567890 COPILOT_GITHUB_TOKEN=copilot-secret GH_TOKEN=gh-secret \
    FAKE_MODE="$2" FAKE_ENGINE="$CENTRAL/tests/fake-engine.py" FAKE_LOG="$T/prompts.log" \
    FEEDBACK_CONFIG="$T/config.yml" RUNNER_TEMP="$T/runner" BRANCH=main FEEDBACK_PUSH="${PUSH:-now}" \
    BEFORE="$(git rev-parse HEAD~1)" SHA="$(git rev-parse HEAD)" \
    bash .feedback/scripts/run.sh "$1" > "$T/run.log" 2>&1
  echo $? > "$T/exit"
  # With PUSH=later the commits stay local for scripts/push.sh
  [ "${PUSH:-now}" = later ] || { git fetch -q origin && git reset -q --hard origin/main; }
}

remote_file() { git -C "$T/remote.git" show "main:$1" 2>/dev/null; }
contains() { remote_file "$1" | grep -qF -- "$2"; }
count() { remote_file "$1" | grep -cF -- "$2"; }
last_prompt() { awk 'BEGIN{RS="=====PROMPT-END=====\n"} {p=$0} END{print p}' "$T/prompts.log"; }
exit_code() { [ "$(cat "$T/exit")" = "$1" ]; }

echo "1. First feedback for working TypeScript (all met)"
student "$TS/workspace/main.ts" 'const name = prompt("Your name?") ?? "";
const number = Number(prompt("A number?"));
console.log(`Hello ${name}! Twice your number is ${number * 2}.`);'
run changed good
expect "run succeeds" exit_code 0
expect "title with assignment title" contains "$TS/FEEDBACK.md" "# Feedback: Greeting – "
expect "German headings" contains "$TS/FEEDBACK.md" "## Zusammenfassung"
expect "score 100 %" contains "$TS/FEEDBACK.md" "**Ergebnis: 100 %**"
expect "requirement line with short text" contains "$TS/FEEDBACK.md" '- ✅ **1. Zwei `prompt()`-Aufrufe: Name, dann Zahl.** – Gut gemacht (R1).'
expect "criteria lines" contains "$TS/FEEDBACK.md" "- **Codequalität:** Passt (C2)."
expect "commit count" contains "$TS/FEEDBACK.md" '- **Commits in `workspace/`:** 1'
expect "multi-line text joined" contains "$TS/FEEDBACK.md" "Template Literals verwenden."
expect "prompt: tsc passed" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'No errors.'"
expect "prompt: example run with answers" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'Hello Mia! Twice your number is 6.'"
expect "prompt: second run with wrong input" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'Twice your number is NaN'"
expect "prompt: typescript skill, no oop skill" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q '^## Skill: typescript' && ! last_prompt | grep -q '^## Skill: oop'"
expect "prompt: no secret" bash -c "! grep -q fake-secret '$T/prompts.log'"

echo "2. No change: no model run"
before=$(grep -c PROMPT-END "$T/prompts.log")
run changed good
expect "no new prompt" test "$(grep -c PROMPT-END "$T/prompts.log")" = "$before"

echo "3. Update with a type error: capped at 50 %"
student "$TS/workspace/main.ts" 'const name: number = prompt("Your name?") ?? "";
console.log(name);'
run changed good
expect "update section" contains "$TS/FEEDBACK.md" "## Update – "
expect "update headings are level 3" contains "$TS/FEEDBACK.md" "### Bewertung"
expect "changes sentence" contains "$TS/FEEDBACK.md" "Du hast den NaN-Fall ergänzt."
expect "capped score" contains "$TS/FEEDBACK.md" "**Ergebnis: 50 %**"
expect "cap reason" contains "$TS/FEEDBACK.md" "die Typprüfung meldet Fehler"
expect "first feedback unchanged" contains "$TS/FEEDBACK.md" "**Ergebnis: 100 %**"
expect "prompt: earlier feedback included" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'This is an update'"

echo "4. Crash in the example run, partly met: score and cap"
student "$TS/workspace/main.ts" 'const name = prompt("Your name?") ?? "";
if (name === "Mia") { throw new Error("boom"); }'
run changed partly
expect "score from statuses (1 + ½ + 0 of 3 = 50 %)" contains "$TS/FEEDBACK.md" "**Ergebnis: 50 %**"
expect "crash reason" contains "$TS/FEEDBACK.md" "das Programm bricht beim Beispiellauf ab"
expect "status icons" contains "$TS/FEEDBACK.md" "- ⚠️ **1."
expect "two update sections" test "$(count "$TS/FEEDBACK.md" "## Update – ")" = 2

echo "5. Invalid answers are rejected (3 attempts), nothing is written"
for mode in nojson wrongids percent secret; do
  student "$TS/workspace/main.ts" "console.log(\"$mode\");"
  run changed "$mode"
  expect "$mode: run fails" exit_code 1
  expect "$mode: no new update" test "$(count "$TS/FEEDBACK.md" "## Update – ")" = 2
  expect "$mode: secret never on the remote" bash -c "! git -C '$T/remote.git' log -p --all | grep -q fake-secret"
done

echo "6. HTML: stylesheet not linked → capped; nested requirement items"
student "$HTML/workspace/styles.css" '.card { border: 1px solid; padding: 1rem; }'
run changed good
expect "run succeeds" exit_code 0
expect "headings" contains "$HTML/FEEDBACK.md" "## Bewertung"
expect "cap reason" contains "$HTML/FEEDBACK.md" "das Stylesheet ist nicht eingebunden"
expect "score capped" contains "$HTML/FEEDBACK.md" "**Ergebnis: 50 %**"
expect "prompt: grouped requirement with sub-items" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q '^- R2 (Struktur): Die Karte ist ein'"
expect "prompt: html and css skills" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q '^## Skill: css' && last_prompt | grep -q '^## Skill: html'"
expect "prompt: html-validate ran" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'HTML-validate'"

echo "7. Mode missing: nothing left without feedback"
before=$(grep -c PROMPT-END "$T/prompts.log")
run missing good
expect "no new prompt" test "$(grep -c PROMPT-END "$T/prompts.log")" = "$before"

echo "8. FEEDBACK_PUSH=later: run.sh only commits, push.sh pushes after a student push"
student "$TS/workspace/main.ts" 'console.log("later");'
PUSH=later run changed good
expect "run succeeds" exit_code 0
expect "nothing pushed by run.sh" test "$(count "$TS/FEEDBACK.md" "## Update – ")" = 2
git clone -q "$T/remote.git" "$T/other"
printf 'meanwhile\n' > "$T/other/notes.txt"
git -C "$T/other" add notes.txt
git -C "$T/other" -c user.name=s -c user.email=s@s commit -qm "student: meanwhile"
git -C "$T/other" push -q origin HEAD:main
env PUSH_TOKEN=test-token BRANCH=main bash .feedback/scripts/push.sh > "$T/push.log" 2>&1
echo $? > "$T/exit"
expect "push succeeds" exit_code 0
expect "feedback pushed" test "$(count "$TS/FEEDBACK.md" "## Update – ")" = 3
expect "student commit kept" contains notes.txt meanwhile
env BRANCH=main bash .feedback/scripts/push.sh > "$T/push.log" 2>&1
expect "second push: nothing to push" grep -q "No feedback to push." "$T/push.log"
git fetch -q origin && git reset -q --hard origin/main

echo "9. runtime: node: the course's package-lock.json, tsc with its tsconfig.json, tsx, ts-utils"
git reset -q --hard origin/main
# @majikmate/ts-utils as a git dependency, like in the courses (here a local
# repository with the dist files of majikmate/ts-utils)
cp -r "$CENTRAL/tests/node-course/ts-utils" "$T/ts-utils"
git -C "$T/ts-utils" init -q -b main
git -C "$T/ts-utils" add -A
git -C "$T/ts-utils" -c user.name=t -c user.email=t@t commit -qm "ts-utils"
printf 'course: test\nlanguage: de\nruntime: node\n' > .github/feedback.yml
cp "$CENTRAL/tests/node-course/tsconfig.json" .
sed "s#TS_UTILS#git+file://$T/ts-utils#" "$CENTRAL/tests/node-course/package.json" > package.json
npm install --package-lock-only --ignore-scripts --no-audit --no-fund --silent > /dev/null 2>&1
git add -A && git -c user.name=t -c user.email=t@t commit -qm "teacher: switch to Node" && git push -q origin HEAD:main
student "$TS/workspace/main.ts" 'import { readFileSync, writeFileSync } from "node:fs";
import { maxBy } from "es-toolkit";
import { green } from "yoctocolors";
import { prompt } from "@majikmate/ts-utils";

const name = prompt("Your name?") ?? "";
const number = Number(prompt("A number?"));
writeFileSync("twice.txt", `${number * 2}`);
console.log(green(`Hello ${name}! Twice your number is ${readFileSync("twice.txt", "utf8")}.`));
console.log(`Largest: ${maxBy([{ n: 1 }, { n: 5 }], (item) => item.n)?.n}`);'
run changed good
expect "run succeeds" exit_code 0
expect "course packages installed from its package-lock.json (TypeScript 6.0.3)" \
  bash -c "grep -q '\"version\": \"6.0.3\"' '$T'/runner/feedback-tools/course-*/node_modules/typescript/package.json"
expect "prompt: course tsconfig.json used" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -qF 'with the course'\''s \`tsconfig.json\`, like \`npm start\`'"
expect "prompt: tsc passed" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'No errors.'"
expect "prompt: ts-utils prompt() echoes the piped answer" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'Your name? Mia'"
expect "prompt: node:fs and yoctocolors" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'Hello Mia! Twice your number is 6.'"
expect "prompt: es-toolkit" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'Largest: 5'"
expect "prompt: second run" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'Twice your number is NaN'"
student "$TS/workspace/main.ts" 'import { prompt } from "@majikmate/ts-utils";

enum Mood { Happy, Sad }

class Greeter {
  constructor(private readonly name: string, private mood: Mood) {}

  greet(): string {
    return `Hello ${this.name}! (${Mood[this.mood]})`;
  }
}

console.log(new Greeter(prompt("Your name?") ?? "", Mood.Happy).greet());'
run changed good
expect "tsx: enum and parameter properties run" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'Hello Mia! (Happy)'"
student "$TS/workspace/main.ts" 'const name: string = prompt("Your name?") ?? "";
console.log(name);'
run changed good
expect "missing import: type error" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q \"Cannot find name 'prompt'\""
expect "missing import: not run, capped" contains "$TS/FEEDBACK.md" "die Typprüfung meldet Fehler"
student "$TS/workspace/main.ts" 'import { prompt } from "@majikmate/ts-utils";
function twice(value) {
  return value * 2;
}
console.log(twice(Number(prompt("A number?"))));'
run changed good
expect "root tsconfig.json strict: implicit any" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'TS7006'"
student "$TS/workspace/tsconfig.json" '{ "extends": "../../../../tsconfig.json", "compilerOptions": { "strict": false } }'
run changed good
expect "workspace tsconfig.json of the student ignored, like npm start" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'TS7006'"
student "$GAME/workspace/main.ts" 'enum State { Running, Won }
const state: State = State.Won;
document.querySelector("#state")!.textContent = State[state];'
run changed good
expect "browser program: DOM types, type-checked, not run" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'No errors.' && last_prompt | grep -q 'type-checked, not run'"
student "$GAME/workspace/package.json" '{ "type": "module", "scripts": { "dev": "vite" } }'
run changed good
expect "workspace as its own npm project: not checked yet" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'its own npm project'"
student "$TS/workspace/main.ts" 'import { prompt } from "@majikmate/ts-utils";
while (true) {
  const answer = prompt("Again?");
  if (answer === "stop") break;
}'
run changed good
expect "end of input: null, endless loop stopped" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'stopped after 10 seconds'"
git rm -q package-lock.json && git -c user.name=t -c user.email=t@t commit -qm "teacher: no lock" && git push -q origin HEAD:main
student "$TS/workspace/main.ts" 'console.log("no lock");'
run changed good
expect "no package-lock.json: no check, told" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'The course has no .package-lock.json.'"

echo
echo "$PASSED passed, $FAILED failed (logs in $T)"
[ "$FAILED" -eq 0 ]

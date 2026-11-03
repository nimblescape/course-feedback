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

# The command of the course module at the version or commit of config.yml, as
# run.sh starts it, unless FEEDBACK_CS names one (for example a local build of
# course-vscode).
if [ -z "${FEEDBACK_CS:-}" ]; then
  CS_VERSION=$(python3 -c 'import sys, yaml; print(yaml.safe_load(open(sys.argv[1]))["versions"]["course"])' "$CENTRAL/config.yml")
  if [[ "$CS_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+].*)?$ ]]; then
    FEEDBACK_CS="npx -y @nimblescape/course@$CS_VERSION"
  else
    mkdir -p "$T/course-vscode"
    git -C "$T/course-vscode" init --quiet
    git -C "$T/course-vscode" fetch --quiet --depth 1 https://github.com/nimblescape/course-vscode.git "$CS_VERSION"
    git -C "$T/course-vscode" checkout --quiet FETCH_HEAD
    (cd "$T/course-vscode" && npm ci --ignore-scripts --no-audit --no-fund --loglevel=error && node esbuild.mjs --production > /dev/null) || exit 1
    FEEDBACK_CS="node $T/course-vscode/cli/dist/cs.js"
  fi
fi
export FEEDBACK_CS

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
PROJECT=20-assignments/15-project/15.02-vite-game

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
expect "feedback commit in Austrian time (Europe/Vienna)" \
  test "$(git -C "$T/remote.git" log -1 --format=%ai main | cut -c 21-)" = "$(TZ=Europe/Vienna date +%z)"

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
printf 'runtime: node\n' > .github/feedback.yml
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
student "$TS/workspace/main.ts" 'console.log(`Zone: ${Intl.DateTimeFormat().resolvedOptions().timeZone}`);'
run changed good
expect "student program runs in Austrian time (Europe/Vienna)" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'Zone: Europe/Vienna'"
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
student "$GAME/workspace/package.json" '{ "type": "module", "scripts": { "check": "echo ok" } }'
run changed good
expect "package.json added by the student: ignored (note), normal check" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'workspace/package.json. is not a file of the course' && last_prompt | grep -q 'type-checked, not run'"
student "$PROJECT/workspace/main.ts" 'class Score {
  private points = 0;

  add(points: number): void {
    this.points += points;
  }

  getPoints(): number {
    return this.points;
  }
}

const score = new Score();
score.add(3);
document.querySelector("#score")!.textContent = `${score.getPoints()}`;'
run changed good
expect "own npm project of the course: npm run build, no errors" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -qF '(\`npm run build\` of the project: \`tsc -b && vite build\`)' && last_prompt | grep -q 'No errors.' && last_prompt | grep -q 'built with .npm run build. (the type check, then the build), not run'"
expect "own npm project: its lock file installed (TypeScript 6.0.3)" \
  bash -c "grep -q '\"version\": \"6.0.3\"' '$T'/runner/feedback-tools/project-*/node_modules/typescript/package.json"
student "$PROJECT/workspace/main.ts" 'const points: number = "three";
document.querySelector("#score")!.textContent = `${points}`;'
run changed good
expect "own npm project: type error reported and capped" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'TS2322'"
expect "own npm project: type error caps the score" contains "$PROJECT/FEEDBACK.md" "\`npm run build\` meldet Fehler"
student "$PROJECT/workspace/tsconfig.json" '{ "compilerOptions": { "strict": false, "noEmit": true, "lib": ["ES2023", "DOM"] } }'
student "$PROJECT/workspace/main.ts" 'function twice(value) {
  return value * 2;
}
document.querySelector("#score")!.textContent = `${twice(2)}`;'
run changed good
expect "own npm project: student change of tsconfig.json (note), course version used" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'The student changed .workspace/tsconfig.json.: the check uses the course' && last_prompt | grep -q 'TS7006'"
student "$PROJECT/workspace/package.json" '{ "private": true, "scripts": { "build": "echo ok" } }'
run changed good
expect "own npm project: student change of the build script (note), course script used" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'The student changed .workspace/package.json.' && last_prompt | grep -q 'TS7006'"
student "$PROJECT/workspace/main.ts" 'const points: number = 3;
document.querySelector("#score")!.textContent = `${points}`;'
student "$PROJECT/workspace/index.html" '<!doctype html>
<html lang="de">
  <body>
    <p id="score"></p>
    <script type="module" src="./missing.ts"></script>
  </body>
</html>'
student "$PROJECT/workspace/vite.config.ts" 'export default { build: { emptyOutDir: false } };'
run changed good
expect "own npm project: the type check passes, the Vite build fails and is reported" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'Failed to resolve ./missing.ts from index.html' && ! last_prompt | grep -q 'No errors.'"
expect "own npm project: a failing Vite build caps the score" contains "$PROJECT/FEEDBACK.md" "\`npm run build\` meldet Fehler"
expect "own npm project: configuration added by the student ignored (note)" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'The student added .workspace/vite.config.ts.: the check ignores it.'"
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

echo "10. runtime: ts: the command ts, no package.json, the TypeScript that ts installs"
git reset -q --hard origin/main
# No package.json and no tsconfig.json (also not the one that section 9 added
# to the workspace): the defaults of ts
git rm -q package.json tsconfig.json "$TS/workspace/tsconfig.json"
printf 'runtime: ts\n' > .github/feedback.yml
git add -A && git -c user.name=t -c user.email=t@t commit -qm "teacher: switch to ts" && git push -q origin HEAD:main
student "$TS/workspace/main.ts" 'import { readFileSync, writeFileSync } from "node:fs";

const name = prompt("Your name?") ?? "";
const number = Number(prompt("A number?"));
writeFileSync("twice.txt", `${number * 2}`);
console.log(`Hello ${name}! Twice your number is ${readFileSync("twice.txt", "utf8")}.`);
console.log(`Random: ${Math.random()}`);'
run changed good
expect "run succeeds" exit_code 0
expect "ts from its package-lock.json (0.3.0)" \
  bash -c "grep -q '\"version\": \"0.3.0\"' '$T'/runner/feedback-tools/ts/node_modules/@nimblescape/typescript/package.json"
expect "log: ts installed TypeScript and names the versions" bash -c "grep -q '^ts 0.3.0' '$T/run.log' && grep -q '^TypeScript [0-9.]* (global' '$T/run.log'"
expect "prompt: ts check" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -qF '(\`ts check\`, like the students'\'' \`ts main.ts\`)'"
expect "prompt: no errors" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'No errors.'"
expect "prompt: global prompt() echoes the piped answer" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'Your name? Mia'"
expect "prompt: node:fs" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'Hello Mia! Twice your number is 6.'"
expect "prompt: second run" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'Twice your number is NaN'"
expect "prompt: Math.random() seeded in both runs" \
  bash -c "$(declare -f last_prompt); T=$T; test \"\$(last_prompt | grep -c 'Random: 0.28407089272513986')\" = 2"
student "$TS/workspace/main.ts" 'enum Mood { Happy, Sad }

class Greeter {
  constructor(private readonly name: string, private mood: Mood) {}

  greet(): string {
    return `Hello ${this.name}! (${Mood[this.mood]})`;
  }
}

console.log(new Greeter(prompt("Your name?") ?? "", Mood.Happy).greet());'
run changed good
expect "ts: enum and parameter properties run" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'Hello Mia! (Happy)'"
student "$TS/workspace/main.ts" 'function twice(value) {
  return value * 2;
}
console.log(twice(Number(prompt("A number?"))));'
run changed good
expect "defaults of ts strict: implicit any, not run" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'main.ts(1,16): error TS7006' && last_prompt | grep -q 'The program was not run'"
expect "type error caps the score" contains "$TS/FEEDBACK.md" "die Typprüfung meldet Fehler"
student "$TS/workspace/main.ts" 'function fail(): never {
  throw new Error("boom");
}
console.log(`Zone: ${Intl.DateTimeFormat().resolvedOptions().timeZone}`);
fail();'
run changed good
expect "student program runs in Austrian time (Europe/Vienna)" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'Zone: Europe/Vienna'"
expect "crash: the line of main.ts, short path" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q '^    at fail (main.ts:2:9)' && last_prompt | grep -q 'the program stopped with an error'"
student "$TS/workspace/main.ts" 'while (true) {
  const answer = prompt("Again?");
  if (answer === "stop") break;
}'
run changed good
expect "end of input: null, endless loop stopped" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'stopped after 10 seconds'"

# npm install yoctocolors in the workspace (ts-2 chapter 12): a package.json
# without "type" and its package-lock.json, written by the student
mkdir -p "$T/npm-yoctocolors"
(cd "$T/npm-yoctocolors" && npm install --package-lock-only --no-audit --no-fund --silent yoctocolors@2.2.0)
student "$TS/workspace/package.json" "$(cat "$T/npm-yoctocolors/package.json")"
student "$TS/workspace/package-lock.json" "$(cat "$T/npm-yoctocolors/package-lock.json")"
student "$TS/workspace/main.ts" 'import { green } from "yoctocolors";

const name = prompt("Your name?") ?? "";
console.log(green(`Correct, ${name}!`));'
run changed good
expect "workspace package.json of the student: its packages installed" \
  bash -c "grep -q '\"version\": \"2.2.0\"' '$T'/runner/feedback-tools/workspace-*/node_modules/yoctocolors/package.json"
expect "workspace packages: no errors, the program runs" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'No errors.' && last_prompt | grep -q 'Correct, Mia!'"
expect "workspace packages: no note" bash -c "$(declare -f last_prompt); T=$T; ! last_prompt | grep -q 'could not be installed\\|no .workspace/package-lock.json.\\|is not a file of the course'"
git rm -q "$TS/workspace/package-lock.json" && git -c user.name=t -c user.email=t@t commit -qm "student: no lock" && git push -q origin HEAD:main
student "$TS/workspace/main.ts" 'import { green } from "yoctocolors";
console.log(green("no lock"));'
run changed good
expect "workspace package.json without package-lock.json: note, not installed" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'there is no .workspace/package-lock.json.' && last_prompt | grep -q 'yoctocolors'"

echo "11. JavaScript without a build: syntax check, Node.js run, JavaScript skill"
JS=20-assignments/01-dom/01.01-menu
NODE=20-assignments/03-node/03.01-printer
student "$JS/workspace/main.js" 'const dishes = ["Pizza", "Pasta"];
const menu = document.querySelector("#menu");
if (menu === null) {
  throw new Error("No element matches #menu.");
}
for (const dish of dishes) {
  const item = document.createElement("li");
  item.textContent = dish;
  menu.append(item);
}'
run changed good
expect "page: javascript, html and css skills, no typescript skill" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q '^## Skill: javascript' && last_prompt | grep -q '^## Skill: html' && ! last_prompt | grep -q '^## Skill: typescript'"
expect "page: syntax check passed, not run" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'No errors in .main.js.' && last_prompt | grep -q 'checked for syntax errors, not run in a browser'"
expect "page: not capped" contains "$JS/FEEDBACK.md" "**Ergebnis: 100 %**"
student "$JS/workspace/main.js" 'const menu: HTMLElement | null = document.querySelector("#menu");
console.log(menu);'
run changed good
expect "type annotation in a .js file: syntax error" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'SyntaxError' && last_prompt | grep -q '^main.js:1$'"
expect "syntax error caps the score" contains "$JS/FEEDBACK.md" "eine JavaScript-Datei hat einen Syntaxfehler"
student "$NODE/workspace/main.js" 'const dishes = ["Pizza"];
console.log("<ul>");
for (const dish of dishes) {
  console.log(`  <li>${dish}</li>`);
}
console.log("</ul>");
console.log(`Random: ${Math.random()}`);'
run changed good
expect "Node.js program: javascript skill only" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q '^## Skill: javascript' && ! last_prompt | grep -q '^## Skill: html'"
expect "Node.js program: run with node main.js, seeded" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q '  <li>Pizza</li>' && last_prompt | grep -q 'Random: 0.28407089272513986' && last_prompt | grep -q 'exit code: 0'"
student "$NODE/workspace/main.js" 'function fail() {
  throw new Error("boom");
}
fail();'
run changed good
expect "Node.js program: crash with a short path, capped" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q '^    at fail (main.js:2:9)' && ! last_prompt | grep -q 'node:internal'"
expect "Node.js program: crash caps the score" contains "$NODE/FEEDBACK.md" "das Programm bricht beim Beispiellauf ab"

echo "12. React: the React skill, a stylesheet imported by main.tsx, lint facts, a README in parts"
REACT=20-assignments/16-react/16.01-counter
student "$REACT/workspace/src/app.tsx" 'import { useState } from "react";

// The count starts at 0 and grows with every click.
export function App() {
  const [count, setCount] = useState(0);

  function handleClick() {
    setCount((c) => c + 1);
  }

  return (
    <main className="counter">
      <button type="button" onClick={handleClick}>
        {count}
      </button>
    </main>
  );
}'
run changed good
expect "React project: react, typescript, html and css skills" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q '^## Skill: react' && last_prompt | grep -q '^## Skill: typescript' && last_prompt | grep -q '^## Skill: html'"
expect "React project: the stylesheet imported by src/main.tsx counts" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -qF 'Stylesheets imported by modules: \`src/index.css\` (in \`src/main.tsx\`)'"
expect "React project: build and lint without problems" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -qF '(\`npm run build\` of the project: \`tsc -b && vite build\`)' && last_prompt | grep -q 'No errors.' && last_prompt | grep -qF '### Lint (\`npm run lint\` of the project: \`oxlint\`)' && last_prompt | grep -q 'No problems.'"
expect "React project: not capped" contains "$REACT/FEEDBACK.md" "**Ergebnis: 100 %**"
expect "requirements in groups: the group of each requirement" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q '^- R1 (Teil A – Der Fehler): Ein Kommentar' && last_prompt | grep -q '^- R3 (Teil B – Code): Die Zahl ist ein State'"
student "$REACT/workspace/src/app.tsx" 'import { useState } from "react";

export function App() {
  const [count, setCount] = useState(0);

  function handleClick() {
    const [clicks, setClicks] = useState(0);
    setClicks(clicks + 1);
    setCount(count + 1);
  }

  return (
    <main className="counter">
      <button type="button" onClick={handleClick}>
        {count}
      </button>
    </main>
  );
}'
run changed good
expect "React project: lint reports the hook in a handler, one line per problem" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q '^src/app.tsx:7:[0-9]*: React Hook \"useState\" is called in function \"handleClick\".*rules-of-hooks' && ! last_prompt | grep -q '^Finished in'"
expect "React project: lint never caps the score" test "$(count "$REACT/FEEDBACK.md" "**Ergebnis: 100 %**")" = 2
student "$REACT/workspace/src/main.tsx" 'import { createRoot } from "react-dom/client";
import { App } from "./app.tsx";

createRoot(document.querySelector("#root")!).render(<App />);'
run changed good
expect "React project: without the import of the stylesheet, capped" contains "$REACT/FEEDBACK.md" "das Stylesheet ist nicht eingebunden"

echo "13. An npm project that the student set up (no package.json in the template)"
student "$GAME/workspace/package.json" "$(cat "$CENTRAL/tests/fixture/$PROJECT/workspace/package.json")"
student "$GAME/workspace/package-lock.json" "$(cat "$CENTRAL/tests/fixture/$PROJECT/workspace/package-lock.json")"
student "$GAME/workspace/tsconfig.json" "$(cat "$CENTRAL/tests/fixture/$PROJECT/workspace/tsconfig.json")"
student "$GAME/workspace/main.ts" 'const state: string = "Won";
document.querySelector("#state")!.textContent = state;'
run changed good
expect "own npm project of the student: npm run build with the student's configuration" bash -c "$(declare -f last_prompt); T=$T; last_prompt | grep -q 'The student set up this npm project' && last_prompt | grep -qF '(\`npm run build\` of the project: \`tsc -b && vite build\`)' && last_prompt | grep -q 'No errors.'"
student "$GAME/workspace/main.ts" 'const state: number = "Won";
document.querySelector("#state")!.textContent = `${state}`;'
run changed good
expect "own npm project of the student: a type error caps the score" contains "$GAME/FEEDBACK.md" "\`npm run build\` meldet Fehler"
echo
echo "$PASSED passed, $FAILED failed (logs in $T)"
[ "$FAILED" -eq 0 ]

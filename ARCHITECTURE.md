# Feedback Architecture

After every push of a student, the feedback compares the work with the
assignment README and writes or extends `FEEDBACK.md` next to the README.

**Principle:** the feedback is consistent and deterministic. Scripts decide
everything that can be decided without judgement. The only variable part is the
model's judgement of the student's code: one status and one comment per
requirement, best practices, suggestions and a summary.

## Pipeline

```text
student pushes 20-assignments/<chapter>/<assignment>/workspace/…
   │
   ▼
.github/workflows/feedback.yml (course repo, copied from templates/)
   │  checks out the student repo, and this repo (tag v2) into .feedback/
   ▼
scripts/run.sh builds the command cs of the course module (nimblescape/
course-vscode at versions.course of config.yml), then for each assignment
with student work and with changes:
   1. checks   skills/<skill>/check.sh       Markdown facts, "does-not-run" lines
   2. prompt   scripts/feedback.py prompt    one prompt from fixed parts and
                                             cs read, cs instructions feedback,
                                             cs feedback --form
   3. model    engines/<engine>.sh run       JSON answer, model has no tools
   4. answer   scripts/feedback.py render    cs feedback checks the answer,
                                             computes the score, writes
                                             FEEDBACK.md
   5. commit   one commit per FEEDBACK.md
   │
   ▼
last step: scripts/push.sh pushes all feedback commits with FEEDBACK_PUSH_TOKEN,
a fine-grained token of an organisation admin (students cannot push FEEDBACK.md)
```

An invalid answer is rejected and the model is asked again (at most three
attempts); nothing is written before an answer is valid.

## Who Decides What

| Part                                                                     | Decided by                                                       |
| ------------------------------------------------------------------------ | ---------------------------------------------------------------- |
| Assignments that get feedback                                            | `scripts/has-implementation.sh`: workspace differs from template |
| Feedback skills for the work                                             | `metadata.files` and `metadata.contains` in each `SKILL.md`      |
| Type check, syntax check, build, lint, program runs, HTML validation     | check scripts; tools pinned by a `package-lock.json`             |
| Answers for `prompt()`, random numbers                                   | course file `.github/feedback/inputs.yml`; fixed random seed     |
| "Does not run" (score cap 50 %)                                          | check results                                                    |
| Prompt text and order                                                    | `scripts/feedback.py`                                            |
| Requirements, criteria, title and chapter of an assignment               | the course module: `cs read`                                     |
| Rules of judging, statuses, tone                                         | the course module: `cs instructions feedback`                    |
| Engine, model, CLI and Node.js versions                                  | `config.yml` (always read from `main`)                           |
| Status and comment per requirement, best practices, suggestions, summary | **the model**                                                    |
| Score                                                                    | `cs feedback` from the statuses: ✅ 1, ⚠️ ½, ❌ 0                |
| Layout, headings, fixed texts of `FEEDBACK.md`                           | `cs feedback` (section 8 of the format of the course module)     |
| Time, commits, texts of the reasons for "does not run"                   | `scripts/feedback.py` and `locales/<language>.yml`               |

## The Prompt

Always the same parts in the same order, identical for every engine:

1. [`agent/feedback-rules.md`](agent/feedback-rules.md): role, the order of the
   prompt, safety, the automatic checks.
2. `cs instructions feedback`: the format of the files of a course with its
   rules of judging, the statuses, the best practices and the tone (section 8),
   then the course's own rules, `.course/instructions/all.md` and
   `.course/instructions/feedback.md` (students, language, conventions, chapter
   mapping of the skills).
3. Feedback skills: the `SKILL.md` text of every matching skill, sorted by name.
4. The assignment as `cs read` reads it: README, the requirements checklist
   numbered R1…Rn with the third-level heading above each as its group, the
   criteria numbered C1…Cm.
5. The student's work: student commits and every file of `workspace/` (files
   that are unchanged from the template are marked as given).
6. The results of the automatic checks.
7. For an update: the earlier `FEEDBACK.md` and the changes since then.
8. The answer format: `cs feedback --form`.

## The Answer and FEEDBACK.md

The model answers with one JSON object: `requirements` (id, `met` / `partly` /
`missing`, comment), `criteria` (id, comment), `run`, `best_practices`,
`suggestions` (at most three), `changes` (updates only) and `summary`.

`feedback.py render` rejects the answer when a secret or token appears, and
hands it to `cs feedback`. The course module rejects the answer when an id is
missing or repeated, a status is unknown, a required text is empty or the
summary contains a percentage. Otherwise it computes the score (rounded half up;
at most 50 % when a check reported "does not run") and writes the sections
Assessment, Best Practices, Suggestions and Summary in the course language. The
first feedback starts with `# Feedback: <title> – <time>`; an update appends
`---` and `## Update – <time>` and never changes earlier text. Every time is
Austrian time (`TZ=Europe/Vienna`): `FEEDBACK.md`, the commit dates, the checks
and the student programs.

## Checks Without Deno

- `typescript`: a type check with `tsc` (Microsoft TypeScript), then one run
  with `node` per answer set of `inputs.yml` (run 1 = the README's example run).
  Browser programs (`index.html`) are type-checked only. The course file
  `.github/feedback.yml` says how the students run their code:
  - `runtime: ts`: exactly as the students' `ts main.ts`. The command `ts` of
    nimblescape TypeScript comes from
    [`ts/package-lock.json`](skills/typescript/ts/package-lock.json) (`npm ci
    --ignore-scripts`); once per run, `ts install --global` installs the
    TypeScript that `ts` uses outside VS Code (the TypeScript of the newest VS
    Code) globally, and the log shows the versions. `ts check` checks
    `main.ts` and its imports with the nearest `tsconfig.json` (the workspace,
    then the course root) or the defaults of `ts`, then `ts main.ts` runs the
    program with the global `prompt()`. Node.js takes `seed-random.mjs` from
    `NODE_OPTIONS`.
  - `runtime: node`: exactly as the students' `npm start`. The course's own
    npm packages (TypeScript, tsx, `@majikmate/ts-utils`, …) are installed from
    its root `package-lock.json` with `npm ci --ignore-scripts`, outside the
    checkout. `tsc` checks `main.ts` and its imports with a `tsconfig.json` that
    extends the course's root `tsconfig.json` (a workspace `tsconfig.json` does
    not count), then tsx runs the program.
  - `runtime: deno` (default, while a course still teaches Deno): `tsc` checks
    like `deno check main.ts`, and `node` runs the emitted JavaScript.
    [`deno-compat.mjs`](skills/typescript/tools/deno-compat.mjs) provides
    `prompt()`, the taught `Deno.readTextFileSync` and `Deno.writeTextFileSync`,
    and `jsr:` imports (packages pinned from npm.jsr.io); it echoes the prepared
    answers and stops the program when they are used up.

  For repeatable runs, all three seed `Math.random()`
  ([`seed-random.mjs`](skills/typescript/tools/seed-random.mjs)).

  A workspace that is its own npm project (its `package.json` is in the
  template copy of the class repository, for example a Vite project) gets
  `npm run build` of the project instead
  ([`check-project.sh`](skills/typescript/check-project.sh)): `package.json`,
  `package-lock.json`, `tsconfig*.json`, `jsconfig*.json` and `vite.config.*`
  in the version of the template copy (a student change gets a note, a
  configuration file that a student adds is ignored), `npm ci --ignore-scripts`,
  a writable `node_modules` with one link per package (`tsc -b` and Vite write
  to it), the build in the sandbox, not run. A failing build caps the score
  (reason `build`). When the project has a `lint` script (oxlint in the Vite
  templates), `npm run lint` runs too: its problems are facts for the feedback,
  one line per problem sorted by file and position, and never cap the score.

  A workspace that the student turns into an npm project (the template has no
  `package.json`, the student's has a `build` script or uses Vite, for example
  react-2 04.01 "Swap the Engine") gets the same check with the student's own
  `package.json`, `package-lock.json` and configuration, with a note. Any other
  `package.json` that a student adds to a workspace without one of the template
  is ignored (with `runtime: ts`, its packages are installed, as for `ts`).

- `javascript`: JavaScript that runs without a build (`*.js`, `*.mjs`,
  `*.cjs`): `node --check` per file (a type annotation in a `.js` file is a
  syntax error; reason `syntax`), then, for a Node.js program (`main.js` without
  `index.html`), one run of `node main.js` in the sandbox (reasons `crash` and
  `timeout`). A page (`index.html`) is not run.

- `react`: no check of its own. A React project is an npm project (see
  `typescript`); the skill adds the rules of React to the prompt.

- `html`: `index.html` exists and uses a stylesheet of the workspace: linked in
  `index.html`, or imported by a module of the page (`import "./index.css";` in
  `src/main.tsx` of a Vite project); `html-validate` with the presets the
  students see in VS Code.

## Where Things Live

| Central (this repository)                                  | Course repository (`.github/` and `.course/`, protected for students) |
| ---------------------------------------------------------- | ------------------------------------------------------ |
| `config.yml`: engine, models, versions, per-course values  | `feedback.yml`: the runtime of the student programs    |
| `agent/feedback-rules.md`: the frame of the prompt         | `.course/course.yml`: course id and language (course module) |
| (rules of judging: the course module)                      | `.course/instructions/feedback.md`: the course's feedback rules |
| `skills/<skill>/`: `SKILL.md`, `check.sh`, `tools/`        | `feedback-skills/<skill>/` (optional own skills)       |
| `locales/<language>.yml`: the reasons of "does not run"    | `feedback/inputs.yml`: answers for `prompt()`          |
| `engines/`, `scripts/`, `templates/feedback.yml`, `tests/` | `workflows/feedback.yml` (copy of the template)        |

## Security

- **The model gets text, nothing else.** No tools, no MCP servers, no project
  settings or instruction files, and it runs in an empty folder. Student files
  reach it only as data inside the prompt.
- **Student programs and the type check run in a sandbox**
  (`scripts/sandbox.sh`, bubblewrap): no network, no environment variables, no
  access to the repository, the home folder or the runner's temporary folder;
  writes only in a copy of the workspace; 10 seconds per run. npm packages are
  installed before, without install scripts.
- **Secrets only where needed.** The engine sees only its own secret; checks and
  student programs see none. A `FEEDBACK.md` with a secret value or a token is
  rejected.
- **Only `FEEDBACK.md` is written and committed.** The checks work on copies.
- **Students cannot change `FEEDBACK.md`.** The organisation ruleset protects
  it; the feedback pushes with a fine-grained token of an organisation admin
  (a bypass actor; "Contents: Read and write" only), and only the last step
  gets it, after the model and the student programs have finished.
- **Students cannot change the rules.** The push ruleset of HTLD-STH-SWP allows
  students only `20-assignments/*/*/workspace/` and `30-playground/`, so the
  workflow, the course rules in `.course/`, the READMEs and the prepared inputs
  stay as the course defines them.

## Tests

[`tests/run-tests.sh`](tests/run-tests.sh) runs the whole pipeline on the small
course in `tests/fixture/` with a fake engine and real checks: first feedback,
update, score and cap, rejected answers, secrets, HTML.

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
   │  checks out the student repo, and this repo (tag v1) into .feedback/
   ▼
scripts/run.sh, for each assignment with student work and with changes
   1. checks   skills/<skill>/check.sh       Markdown facts, "does-not-run" lines
   2. prompt   scripts/feedback.py prompt    one prompt from fixed parts
   3. model    engines/<engine>.sh run       JSON answer, model has no tools
   4. answer   scripts/feedback.py render    checks the answer, computes the
                                             score, writes FEEDBACK.md
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
| Type check, program runs, HTML validation                                | check scripts; tools pinned by a `package-lock.json`             |
| Answers for `prompt()`, random numbers                                   | course file `.github/feedback/inputs.yml`; fixed random seed     |
| "Does not run" (score cap 50 %)                                          | check results                                                    |
| Prompt text and order                                                    | `scripts/feedback.py`                                            |
| Engine, model, CLI and Node.js versions                                  | `config.yml` (always read from `main`)                           |
| Status and comment per requirement, best practices, suggestions, summary | **the model**                                                    |
| Score                                                                    | `scripts/feedback.py` from the statuses: ✅ 1, ⚠️ ½, ❌ 0        |
| Layout, headings, fixed texts, time                                      | `scripts/feedback.py` and `locales/<language>.yml`               |

## The Prompt

Always the same parts in the same order, identical for every engine:

1. [`agent/feedback-rules.md`](agent/feedback-rules.md): role, safety, how to
   judge, tone, answer fields.
2. Course rules: `.github/instructions/feedback-course.instructions.md` of the
   course (students, language, conventions, chapter mapping of the skills).
3. Feedback skills: the `SKILL.md` text of every matching skill, sorted by name.
4. The assignment: README, the requirements checklist numbered R1…Rn, the
   criteria numbered C1…Cm.
5. The student's work: student commits and every file of `workspace/` (files
   that are unchanged from the template are marked as given).
6. The results of the automatic checks.
7. For an update: the earlier `FEEDBACK.md` and the changes since then.
8. The answer format.

## The Answer and FEEDBACK.md

The model answers with one JSON object: `requirements` (id, `met` / `partly` /
`missing`, comment), `criteria` (id, comment), `run`, `best_practices`,
`suggestions` (at most three), `changes` (updates only) and `summary`.

`feedback.py render` rejects the answer when an id is missing or repeated, a
status is unknown, a required text is empty, the summary contains a percentage,
or a secret or token appears. Otherwise it computes the score (rounded half up;
at most 50 % when a check reported "does not run") and writes the sections
Assessment, Best Practices, Suggestions and Summary in the course language. The
first feedback starts with `# Feedback: <title> – <time>`; an update appends
`---` and `## Update – <time>` and never changes earlier text.

## Checks Without Deno

- `typescript`: a type check with `tsc` (Microsoft TypeScript), then one run
  with `node` per answer set of `inputs.yml` (run 1 = the README's example run).
  Browser programs (`index.html`) are type-checked only. The course file
  `.github/feedback.yml` says how the students run their code:
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

  For repeatable runs, both seed `Math.random()`
  ([`seed-random.mjs`](skills/typescript/tools/seed-random.mjs)).

  A workspace that is its own npm project (its `package.json` is in the
  template copy of the class repository, for example a Vite game) gets
  `npm run check` of the project instead
  ([`check-project.sh`](skills/typescript/check-project.sh)): `package.json`,
  `package-lock.json` and `tsconfig.json` in the version of the template copy
  (a student change gets a note), `npm ci --ignore-scripts`, the check in the
  sandbox, not run. A `package.json` that a student adds is ignored.

- `html`: `index.html` exists and links a stylesheet of the workspace;
  `html-validate` with the presets the students see in VS Code.

## Where Things Live

| Central (this repository)                                  | Course repository (`.github/`, protected for students) |
| ---------------------------------------------------------- | ------------------------------------------------------ |
| `config.yml`: engine, models, versions, per-course values  | `feedback.yml`: course id and language                 |
| `agent/feedback-rules.md`                                  | `instructions/feedback-course.instructions.md`         |
| `skills/<skill>/`: `SKILL.md`, `check.sh`, `tools/`        | `feedback-skills/<skill>/` (optional own skills)       |
| `locales/<language>.yml`: headings and fixed texts         | `feedback/inputs.yml`: answers for `prompt()`          |
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
- **Students cannot change the rules.** The organisation ruleset of HTLD-STH-SWP
  protects `.github/`, so the workflow, the course rules and the prepared inputs
  stay as the course defines them.

## Tests

[`tests/run-tests.sh`](tests/run-tests.sh) runs the whole pipeline on the small
course in `tests/fixture/` with a fake engine and real checks: first feedback,
update, score and cap, rejected answers, secrets, HTML.

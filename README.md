# Course Feedback

Central feedback automation for the courses in the format of the nimblescape
course module. After every push of a student, the work is checked and run, a
model judges it against the assignment README, and the course module writes or
extends `FEEDBACK.md` next to the README.

The course module [`@nimblescape/course`](https://github.com/nimblescape/course-vscode)
owns the files of a course. The program runs its command with
`npx -y @nimblescape/course@<version>` and installs nothing globally: `read`
reads each assignment, `instructions feedback` prints the rules of judging and
the course's own feedback rules (`.course/instructions/feedback.md`),
`feedback --form` prints the form of the model's answer, and `feedback` checks
the answer, computes the score and writes `FEEDBACK.md`. This repository keeps the program: the settings,
the engines, the skills, the automatic checks and the prompt.

This repository holds everything that is the same for all courses. One central
file, [`config.yml`](config.yml), decides which engine, which model and which
tool versions run – so costs and billing are controlled in one place.

## How It Works

Read [ARCHITECTURE.md](ARCHITECTURE.md): the pipeline, which parts are fixed and
which part comes from the model, the prompt, the answer, the checks and the
security layers. In short: scripts run the checks and build one fixed prompt,
the command `feedback` of the course module writes `FEEDBACK.md` with the
score; the model has no tools and only judges the student's code.

## Central Config

[`config.yml`](config.yml):

| Key                       | Meaning                                                     |
| ------------------------- | ----------------------------------------------------------- |
| `enabled`                 | `false` stops all feedback runs                             |
| `engine`                  | File in `engines/`: `copilot` or `claude-code`              |
| `models.<engine>`         | Exact model name per engine (no alias)                      |
| `versions`                | Node.js major version, exact CLI version per engine, and `course`: the version of the npm package `@nimblescape/course` that the runs start with npx, or a commit of nimblescape/course-vscode that the runs build |
| `max_assignments_per_run` | Cost limit per run; the rest follow in the nightly run      |
| `courses.<course-id>`     | Optional values for one course, for example a smaller model |

A change on `main` applies to every student repo at its next run.

## Engines

| Engine        | Billed through                      | Secret                                             |
| ------------- | ----------------------------------- | -------------------------------------------------- |
| `copilot`     | GitHub Copilot account of the token | `COPILOT_GITHUB_TOKEN`                             |
| `claude-code` | Claude Max plan (or an API account) | `CLAUDE_CODE_OAUTH_TOKEN` (or `ANTHROPIC_API_KEY`) |

A new engine is one new file `engines/<name>.sh` with three commands:

- `secrets` prints the names of its secrets (`run.sh` removes every other
  engine's secrets from the environment);
- `install <version>` installs that exact CLI version and checks its secret;
- `run <model> <prompt-file>` gives the prompt to the model without any tools,
  from an empty folder, and prints the model's answer (exit code 0 on success).

Add its secret and its version (`versions.<name>`) to `config.yml` and the
course workflow template.

## Feedback Skills

The best practices of each technology are skills in the
[Agent Skills](https://agentskills.io) format: general rules that any project
can combine. The script selects them by the files of the work; a course does not
list them.

| Skill        | Selected for                                    | Check script                                                                                  |
| ------------ | ----------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `typescript` | `*.ts *.tsx *.mts`                              | `tsc` type check, program runs with Node.js; npm projects: `npm run build` and `npm run lint` |
| `javascript` | `*.js *.mjs *.cjs`                              | `node --check` syntax check, `node main.js` for a Node.js program                             |
| `react`      | script files that import `react` or `react-dom` | – (the npm project check of `typescript`)                                                     |
| `oop`        | `.ts` or `.md` files with a class/interface     | –                                                                                             |
| `html`       | `*.html *.htm`                                  | page renders (stylesheet linked or imported), html-validate                                   |
| `css`        | `*.css`                                         | –                                                                                             |

A skill is a folder `skills/<name>/` with:

- `SKILL.md`: front matter with `name`, `description` and `metadata.files` (file
  name patterns, separated by spaces) and optionally `metadata.contains` (a
  regular expression that a matching file must contain); then the rules (no
  chapter numbers: the course rules say from which chapter a topic applies). The
  whole text goes into the prompt.
- optionally `check.sh <assignment-path>`: prints Markdown facts for the prompt,
  writes `does-not-run <reason>` to `$FEEDBACK_STATUS` when the work does not
  run (the texts of the reasons are in `locales/`) and never fails. Helpers are in
  [`scripts/check-lib.sh`](scripts/check-lib.sh); student programs run only
  through [`scripts/sandbox.sh`](scripts/sandbox.sh).
- optionally `tools/` with `package.json` and `package-lock.json`: the tools of
  the check with exact versions, installed once per run with `npm ci`.

A new technology is a new skill folder. A course can also bring its own skill
in `.github/feedback-skills/<name>/` (same structure); it replaces a central
skill of the same name. Move it here when a second course needs it.

## Security

The layers are described in [ARCHITECTURE.md](ARCHITECTURE.md#security). One of
them lives outside this repository: a push ruleset of HTLD-STH-SWP for the
student and class repositories of the courses restricts every path (`**/*`,
`**/.*`, `.*/**/*`) and allows only `20-assignments/*/*/workspace/**` and
`30-playground/**`; its bypass actors are the organisation and repository
admins. Without it, a student could add a workflow that prints the organisation
secrets, or change the course rules (`.course/`), the READMEs and the prepared
inputs. Keep `.github/` and `.course/` restricted in that ruleset.

Students must not change `FEEDBACK.md` either. The ruleset restricts it, so
only its bypass actors can push the file, and `GITHUB_TOKEN` cannot be one. The course workflow therefore pushes in its last
step with the secret `FEEDBACK_PUSH_TOKEN` (see below); `scripts/run.sh` only
commits (`FEEDBACK_PUSH: later`).

## Secrets in the Student Organisation (HTLD-STH-SWP)

Organisation secrets, available to all student repositories (stored the same way
as `COPILOT_GITHUB_TOKEN` today):

| Secret                    | When                 | Content                                                                                      |
| ------------------------- | -------------------- | -------------------------------------------------------------------------------------------- |
| `COPILOT_GITHUB_TOKEN`    | engine `copilot`     | Token of the account whose Copilot subscription pays, with the "Copilot Requests" permission |
| `CLAUDE_CODE_OAUTH_TOKEN` | engine `claude-code` | Output of `claude setup-token` (Claude Max plan)                                             |
| `FEEDBACK_PUSH_TOKEN`     | always               | Pushes `FEEDBACK.md`, see below                                                              |

This repository and nimblescape/course-vscode are public: the course workflow
checks them out without a token. The workflow reads no secret
`FEEDBACK_WORKFLOW_TOKEN` (old name `FEEDBACK_CENTRAL_TOKEN`) any more; the
secret is deleted.

### Push token (pushes FEEDBACK.md)

Organisation secret `FEEDBACK_PUSH_TOKEN`: a fine-grained personal access token
of an organisation admin of HTLD-STH-SWP (organisation admins are bypass actors
of the rulesets):

- Resource owner HTLD-STH-SWP, "All repositories" (so new class repositories
  and student forks are included).
- Repository permission "Contents: Read and write" only (GitHub adds "Metadata:
  Read-only"). The token can push commits, but it cannot change settings,
  rulesets, secrets, members or workflow files ("Workflows" permission
  missing), although the account is an admin.
- An expiry date. An expired token makes the push step fail (no fallback):
  renew it before it expires. HTLD-STH-SWP must allow fine-grained personal
  access tokens.

Set the secret before the ruleset protects `FEEDBACK.md`. Without it, the
workflow pushes with `GITHUB_TOKEN`, which works only while students may also
change `FEEDBACK.md`. The token is passed only to the push step, after the model
and the student programs have finished; the checks, the student programs and
the model never see it.

## Adding a Course

1. Copy [`templates/feedback.yml`](templates/feedback.yml) to
   `.github/workflows/feedback.yml` of the course repository.
2. Put the course into the format of the course module: `.course/course.yml`
   with `course` (selects the course values in `config.yml`) and `language`
   (`de` or `en`), and the comment of the format in each file (`cs format`,
   `cs check`). Then add `.github/feedback.yml` with the settings of this
   program:

   ```yaml
   runtime: ts # how students run TypeScript: ts, node or deno (default)
   ```

   With `runtime: ts`, the TypeScript check works like the students'
   `ts main.ts` (the command `ts` of
   [nimblescape TypeScript](https://www.npmjs.com/package/@nimblescape/typescript),
   in the exact version of
   [`skills/typescript/ts/package-lock.json`](skills/typescript/ts/package-lock.json)):
   `ts check` checks `main.ts` and its imports with the nearest
   `tsconfig.json` (the workspace, then the course root) or, without one, the
   defaults of `ts`; then `ts` runs the program, and `prompt()` is global. The
   TypeScript is the one that `ts` installs outside VS Code: the TypeScript of
   the newest VS Code (`ts install --global`, once per run; the log shows
   the versions). The course needs no `package.json`. A `package.json` in the
   workspace counts, as it does for `ts`: when the students install a package
   there with `npm install` (for example in ts-2 chapter 12), the check first
   installs the packages of the workspace's `package-lock.json`
   (`npm ci --ignore-scripts`, outside the checkout).

   With `runtime: node`, the TypeScript check works like the students'
   `npm start`: it installs the course's own npm packages from its root
   `package-lock.json` (`npm ci --ignore-scripts`, outside the checkout; git
   dependencies such as `@majikmate/ts-utils` must be public), type-checks
   `main.ts` and its imports with a `tsconfig.json` that extends the course's
   root `tsconfig.json`, and runs the program with tsx. A `tsconfig.json` in the
   workspace does not count.

   A workspace that is its own npm project (a `package.json` of the template,
   for example a Vite project) gets `npm run build` of the project instead,
   with its own `package-lock.json`, in both runtimes. The project needs a
   `build` script; in a standard Vite project it type-checks first
   (`tsc -b && vite build` or `tsc && vite build`). The configuration of the
   project counts in the version of the template (`package.json`,
   `package-lock.json`, `tsconfig*.json`, `jsconfig*.json`, `vite.config.*`).
   The check installs the exact versions of the course's `package-lock.json`,
   also when students ran `npm install`. With a `lint` script, `npm run lint`
   runs too; its problems are facts for the feedback and never cap the score.
   When the README asks the students to set up the npm project themselves (no
   `package.json` in the template), the check builds it with the student's own
   `package.json`, `package-lock.json` and configuration.

3. Add `.course/instructions/feedback.md` with the course's own feedback rules
   (`npx -y @nimblescape/course instructions feedback` prints them after the
   rules of judging and after `.course/instructions/all.md`): what the
   automatic checks mean for this course, from which chapter a skill applies
   (for example: `oop` from chapter 02 on), course conventions and equivalent
   approaches.
4. For programs that use `prompt()`: add `.github/feedback/inputs.yml` with one
   list of answers per run; the first run is the example run of the README.

   ```yaml
   04.02-split-the-bill:
     - ["84.60", "4", "10"]
     - [abc, "4", "10"]
   ```

5. Optionally add course skills in `.github/feedback-skills/<name>/`.

A new language needs the course module to know it and a new file in
`locales/` with the texts of the reasons why a work does not run.

## First Rollout

The template sync copies a course change into every class and student
repository, so the central side must be ready first:

1. Merge the central changes into `main` and move the tag `v1` to the new
   version.
2. Set the secrets in HTLD-STH-SWP.
3. Merge the course changes. The template sync then brings the new workflow to
   the class and student repositories; it pushes with `TEMPLATE_SYNC_TOKEN`,
   which must belong to an admin, because the ruleset protects `.github/`.

## Versions

Course workflows use `FEEDBACK_VERSION: v1`. The tag `v1` names the version
with the course module: the course in `.course/` and the command `cs`. It was
moved on 03.11.2026 from the version before the course module, because every
course moved to the format at the same time. After a compatible change to
scripts, rules or skills, move the tag so that the courses get it:

```bash
git tag -f v1 && git push -f origin v1
```

A change that needs new course files gets a new tag (`v2`), and the course
workflows switch to it together with the new course files. `config.yml` is
always read from `main` and needs no tag.

## Tests

```bash
tests/run-tests.sh
```

Runs the whole pipeline on `tests/fixture/` with a fake engine and the real
checks (needs git, Python with PyYAML, Node.js with npm, jq and bubblewrap).

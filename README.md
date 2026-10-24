# Course Feedback

Central feedback automation for the majikmate courses. After every push of a
student, the work is checked and run, a model judges it against the assignment
README, and a script writes or extends `FEEDBACK.md` next to the README.

This repository holds everything that is the same for all courses. One central
file, [`config.yml`](config.yml), decides which engine, which model and which
tool versions run – so costs and billing are controlled in one place.

## How It Works

Read [ARCHITECTURE.md](ARCHITECTURE.md): the pipeline, which parts are fixed and
which part comes from the model, the prompt, the answer, the checks and the
security layers. In short: scripts run the checks, build one fixed prompt and
write `FEEDBACK.md` with the score; the model has no tools and only judges the
student's code.

## Central Config

[`config.yml`](config.yml):

| Key                       | Meaning                                                     |
| ------------------------- | ----------------------------------------------------------- |
| `enabled`                 | `false` stops all feedback runs                             |
| `engine`                  | File in `engines/`: `copilot` or `claude-code`              |
| `models.<engine>`         | Exact model name per engine (no alias)                      |
| `versions`                | Node.js major version and exact CLI version per engine      |
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

| Skill        | Selected for                                | Check script                                    |
| ------------ | ------------------------------------------- | ----------------------------------------------- |
| `typescript` | `*.ts *.tsx *.mts`                          | `tsc` type check, program runs with Node.js     |
| `oop`        | `.ts` or `.md` files with a class/interface | –                                               |
| `html`       | `*.html *.htm`                              | page renders (stylesheet linked), html-validate |
| `css`        | `*.css`                                     | –                                               |

A skill is a folder `skills/<name>/` with:

- `SKILL.md`: front matter with `name`, `description` and `metadata.files` (file
  name patterns, separated by spaces) and optionally `metadata.contains` (a
  regular expression that a matching file must contain); then the rules (no
  chapter numbers: the course rules say from which chapter a topic applies). The
  whole text goes into the prompt.
- optionally `check.sh <assignment-path>`: prints Markdown facts for the prompt,
  writes `does-not-run <reason>` to `$FEEDBACK_STATUS` when the work does not
  run (reasons are named in `locales/`) and never fails. Helpers are in
  [`scripts/check-lib.sh`](scripts/check-lib.sh); student programs run only
  through [`scripts/sandbox.sh`](scripts/sandbox.sh).
- optionally `tools/` with `package.json` and `package-lock.json`: the tools of
  the check with exact versions, installed once per run with `npm ci`.

A new technology (for example React) is a new skill folder. A course can also
bring its own skill in `.github/feedback-skills/<name>/` (same structure); it
replaces a central skill of the same name. Move it here when a second course
needs it.

## Security

The layers are described in [ARCHITECTURE.md](ARCHITECTURE.md#security). One of
them lives outside this repository: the organisation ruleset "Protected Folders"
of HTLD-STH-SWP rejects student pushes to `.github/`, `.devcontainer/`,
`10-course/`, `10-tutorials/`, `reference-material/` and `00-grading/`. Without
it, a student could add a workflow that prints the organisation secrets, or
change the course rules and the prepared inputs. Keep `.github/**/*` in that
ruleset.

## Secrets in the Student Organisation (HTLD-STH-SWP)

Organisation secrets, available to all student repositories (stored the same way
as `COPILOT_GITHUB_TOKEN` today):

| Secret                    | When                 | Content                                                                                      |
| ------------------------- | -------------------- | -------------------------------------------------------------------------------------------- |
| `FEEDBACK_CENTRAL_TOKEN`  | always               | Fine-grained token, owner `majikmate`, only this repository, "Contents: Read-only"           |
| `COPILOT_GITHUB_TOKEN`    | engine `copilot`     | Token of the account whose Copilot subscription pays, with the "Copilot Requests" permission |
| `CLAUDE_CODE_OAUTH_TOKEN` | engine `claude-code` | Output of `claude setup-token` (Claude Max plan)                                             |

`FEEDBACK_CENTRAL_TOKEN` needs an organisation policy in majikmate that allows
fine-grained personal access tokens, and possibly the approval of the token
there. Set an expiry date and renew the token before it expires.

## Adding a Course

1. Copy [`templates/feedback.yml`](templates/feedback.yml) to
   `.github/workflows/feedback.yml` of the course repository.
2. Add `.github/feedback.yml`:

   ```yaml
   course: oop-2 # selects the course values in config.yml
   language: en # locales/en.yml: headings and fixed texts of FEEDBACK.md
   ```

3. Add `.github/instructions/feedback-course.instructions.md` with the course
   rules: students, language and tone, README sections, what the automatic
   checks mean for this course, from which chapter a skill applies (for example:
   `oop` from chapter 02 on), course conventions and equivalent approaches.
4. For programs that use `prompt()`: add `.github/feedback/inputs.yml` with one
   list of answers per run; the first run is the example run of the README.

   ```yaml
   04.02-split-the-bill:
     - ["84.60", "4", "10"]
     - [abc, "4", "10"]
   ```

5. Optionally add course skills in `.github/feedback-skills/<name>/`.

A new language needs a new file in `locales/`.

## First Rollout

The template sync copies a course change into every class and student
repository, so the central side must be ready first:

1. Merge the central changes into `main` and move the version tag `v1` to it.
2. Set the secrets in HTLD-STH-SWP.
3. Merge the course changes. The template sync then brings the new workflow to
   the class and student repositories; it pushes with `TEMPLATE_SYNC_TOKEN`,
   which must belong to an admin, because the ruleset protects `.github/`.

## Versions

Course workflows use `FEEDBACK_VERSION: v1`. After a compatible change to
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

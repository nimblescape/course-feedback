# Course Feedback

Central feedback automation for the majikmate courses. After every push of a
student, an AI agent compares the work with the assignment README, runs it and
writes or updates a `FEEDBACK.md` next to the README.

This repository holds everything that is the same for all courses. One central
file, [`config.yml`](config.yml), decides which agent engine and which model run
– so costs and billing are controlled in one place.

## How It Works

```text
student repo (HTLD-STH-SWP)                   majikmate/course-feedback
.github/workflows/feedback.yml  ── checkout ──▶  scripts/run.sh  (version tag v1)
.github/feedback.yml (course, modules)          config.yml       (always from main)
.github/instructions/
  feedback-course.instructions.md
```

1. The course workflow checks out the student repo and this repository (into
   `.feedback/`) with the secret `FEEDBACK_CENTRAL_TOKEN`.
2. [`scripts/run.sh`](scripts/run.sh) reads `config.yml` from `main` and the
   course's `.github/feedback.yml`, finds the assignments with student work
   ([`scripts/has-implementation.sh`](scripts/has-implementation.sh)) and skips
   those without changes since the last feedback.
3. It copies the agent and the rules of the course's modules into the checkout:
   - [`agent/Feedback.agent.md`](agent/Feedback.agent.md) →
     `.github/agents/Feedback.agent.md`
   - [`agent/feedback-format.instructions.md`](agent/feedback-format.instructions.md)
     → `.github/instructions/`
   - `modules/<module>/rules.instructions.md` →
     `.github/instructions/best-practices-<module>.instructions.md`
4. For each assignment it runs the module checks (`modules/<module>/check.sh`:
   type-check, program output, HTML validation, …) and puts the results, the
   current time and the changes since the last feedback into the prompt.
5. The engine (`engines/<engine>.sh`) runs the agent. The script then checks the
   result: only `FEEDBACK.md` may change, earlier feedback must stay untouched,
   and the new part needs four sections, a score and no secret. Otherwise it
   retries (at most three times). Finally it commits and pushes `FEEDBACK.md`.

The scripts do the mechanical work, so a mid-tier model is enough: the model
only judges the work and writes the feedback.

## Central Config

[`config.yml`](config.yml):

| Key                       | Meaning                                                     |
| ------------------------- | ----------------------------------------------------------- |
| `enabled`                 | `false` stops all feedback runs                             |
| `engine`                  | File in `engines/`: `copilot` or `claude-code`              |
| `models.<engine>`         | Model per engine, named as the engine knows it              |
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
- `install` installs the CLI and checks its secret;
- `run <model> <prompt-file>` runs the agent from the root of the course
  checkout (exit code 0 on success). It must hide its secret from the commands
  the agent runs.

Add its secret to the course workflow template.

## Modules

| Module       | Used by     | Check script                                         |
| ------------ | ----------- | ---------------------------------------------------- |
| `typescript` | ts-2, oop-2 | `deno check`, program run, `deno task check`/`build` |
| `oop`        | oop-2       | –                                                    |
| `html-css`   | html-css-2  | HTML-validate, headless screenshot                   |

A module is a folder `modules/<name>/` with `rules.instructions.md` (best
practices, no chapter numbers) and optionally `check.sh <assignment-path>`
(prints Markdown facts, never fails).

## Security

The agent reads and runs code that students wrote. These layers keep the secrets
and the repository safe:

- **Protected workflow files.** The organisation ruleset "Protected Folders" of
  HTLD-STH-SWP rejects student pushes to `.github/`, `.devcontainer/`,
  `10-course/`, `10-tutorials/`, `reference-material/` and `00-grading/`.
  Without it, a student could add a workflow that prints the organisation
  secrets. Keep `.github/**/*` in that ruleset.
- **Student programs without rights.** The checks and the agent run Deno
  programs with `--allow-read=. --allow-write=.` and a time limit: no
  environment variables, no network, no other programs.
- **Secrets only where needed.** `run.sh` removes every secret the engine does
  not need. The check scripts run without any secret. The engine hides its own
  secret from the commands the agent runs: Copilot with `--secret-env-vars`,
  Claude Code with `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` (needs bubblewrap, which
  the engine installs).
- **Few tools for the agent.** No web access; `deno task`, `npm`, `npx`, `curl`
  and `wget` are denied. Claude Code may only edit `FEEDBACK.md` files and run
  the listed commands.
- **No agent configuration from students.** The ruleset leaves root files and
  folders such as `.claude/` and `.agents/` writable. The engines would read
  them: Copilot loads `AGENTS.md`, `CLAUDE.md` and skills from `.claude/skills/`
  and `.agents/skills/`; Claude Code applies `.claude/settings.json`, whose
  `env` can send the token to another server. `run.sh` removes `AGENTS.md`,
  `CLAUDE.md`, `GEMINI.md`, `.mcp.json`, `.claude/`, `.agents/`, `.copilot/`
  and `.gemini/` from the worktree before every engine run (never committed).
  In addition, Copilot runs with `--no-custom-instructions` and Claude Code
  with `--setting-sources user --strict-mcp-config`.
- **Result checks.** Only `FEEDBACK.md` is committed; every other change is
  reset. A `FEEDBACK.md` that contains a secret value is rejected.
- **No stored central token.** The central repository is checked out with
  `persist-credentials: false`.

Remaining risk: a student who writes text that tricks the agent, or a command
that the student's files define (`deno task` in the final project), can reach
the job's `GITHUB_TOKEN` that the checkout stored. It can only write to the
student's own repository, and the ruleset still protects `.github/`.

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
   course: oop-2
   modules: [typescript, oop]
   ```

3. Add `.github/instructions/feedback-course.instructions.md` with the course
   rules: language and headings, students, README sections, what counts as
   student work, how to check and run the work, chapter mapping for the modules,
   course conventions.

## First Rollout

The template sync copies a course change into every class and student
repository, so the central side must be ready first:

1. Merge the central changes into `main` and create the tag `v1`.
2. Set the secrets in HTLD-STH-SWP.
3. Merge the course changes. The template sync then brings the new workflow to
   the class and student repositories; it pushes with `TEMPLATE_SYNC_TOKEN`,
   which must belong to an admin, because the ruleset protects `.github/`.

## Versions

Course workflows use `FEEDBACK_VERSION: v1`. After a change to scripts, agent or
rules, move the tag so that the courses get it:

```bash
git tag -f v1 && git push -f origin v1
```

`config.yml` is always read from `main` and needs no tag.

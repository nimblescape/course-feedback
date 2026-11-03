#!/usr/bin/env python3
"""The fixed part of the feedback: everything except the model's judgement.

Builds the prompt for the model from fixed parts and hands the model's answer to
the course module, which checks it and writes FEEDBACK.md with the score. Runs
from the root of the course checkout; the central repository is in .feedback/
(FEEDBACK_CENTRAL).

The course module @nimblescape/course (command cs) owns the files of a course:
`cs read` reads an assignment, `cs instructions feedback` prints the rules of
judging and the course's own feedback rules (.course/instructions/feedback.md),
`cs feedback --form` prints the form of the answer, and `cs feedback` writes
FEEDBACK.md. This script keeps the parts of the program: the settings, the
skills, the prepared inputs, the student's work, the checks and the earlier
feedback.

Usage:
  feedback.py setting <key>                     value from config.yml
  feedback.py course <key>                      value of the course: course and
                                                language from .course/course.yml,
                                                runtime from .github/feedback.yml
  feedback.py skills <assignment>               feedback skills for the work
  feedback.py inputs <assignment> <folder>      answers for prompt(): 1.txt, …
  feedback.py prompt <assignment> <checks.md>   prompt on stdout
  feedback.py render <assignment> <answer> <status>
                                                writes or extends FEEDBACK.md

<assignment> is the assignment folder, for example
20-assignments/04-input/04.01-interactive-mad-libs.

Environment:
  FEEDBACK_CENTRAL  central repository (default .feedback)
  FEEDBACK_CONFIG   config.yml (default $FEEDBACK_CENTRAL/config.yml)
  FEEDBACK_CS       the command of the course module (default cs)
  FEEDBACK_TIME     time for FEEDBACK.md, dd.mm.yyyy hh:mm (Europe/Vienna)
  FEEDBACK_SECRETS  names of environment variables that must not appear in
                    FEEDBACK.md
"""

import fnmatch
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

import yaml

CENTRAL = Path(os.environ.get("FEEDBACK_CENTRAL", ".feedback"))
CONFIG = Path(os.environ.get("FEEDBACK_CONFIG", CENTRAL / "config.yml"))
COURSE_CONFIG = Path(".github/feedback.yml")
CS = shlex.split(os.environ.get("FEEDBACK_CS", "cs"))
COURSE_INPUTS = Path(".github/feedback/inputs.yml")
COURSE_SKILLS = Path(".github/feedback-skills")

SKIPPED_FOLDERS = {".git", "node_modules", "dist"}
MAX_FILE_BYTES = 30_000
LANGUAGES = {
    ".ts": "typescript", ".tsx": "tsx", ".mts": "typescript", ".js": "javascript",
    ".html": "html", ".htm": "html", ".css": "css", ".md": "markdown",
    ".json": "json", ".svg": "svg", ".txt": "text",
}


class AnswerError(Exception):
    """The model's answer cannot be used."""


# --- Helpers -----------------------------------------------------------------


def read_yaml(path):
    return yaml.safe_load(Path(path).read_text(encoding="utf-8")) or {}


def cs(*args):
    """The output of the command cs of the course module; exits with its message
    when it fails."""
    result = subprocess.run([*CS, *args], capture_output=True, text=True, check=False)
    if result.returncode != 0:
        sys.exit(f"cs {' '.join(args)}: {result.stderr.strip() or result.stdout.strip()}")
    return result.stdout


_course = None


def course():
    """The settings of the course: `course` (its id) and `language` as the course
    module reads them from .course/course.yml, and the settings of this program
    from .github/feedback.yml (`runtime`)."""
    global _course
    if _course is None:
        _course = read_yaml(COURSE_CONFIG) if COURSE_CONFIG.exists() else {}
        data = json.loads(cs("read", "."))
        _course.update({"course": data["name"], "language": data["language"]})
    return _course


def setting(key):
    """A value of config.yml; an entry under courses.<id> replaces it."""
    config = read_yaml(CONFIG)
    value = config
    override = (config.get("courses") or {}).get(course().get("course")) or {}
    for part in key.split("."):
        value = value.get(part) if isinstance(value, dict) else None
        override = override.get(part) if isinstance(override, dict) else None
    return value if override is None else override


def locale():
    language = course().get("language", "en")
    return read_yaml(CENTRAL / "locales" / f"{language}.yml")


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, check=False).stdout


def fenced(text, language=""):
    """A fenced block that no backtick run in the text can close."""
    longest = max((len(run) for run in re.findall(r"`+", text)), default=0)
    fence = "`" * max(3, longest + 1)
    return f"{fence}{language}\n{text.rstrip()}\n{fence}"


def front_matter(text):
    """(front matter as dict, body) of a Markdown file."""
    match = re.match(r"^---\n(.*?)\n---\n?(.*)$", text, re.S)
    if not match:
        return {}, text
    return yaml.safe_load(match.group(1)) or {}, match.group(2)


# --- The assignment ----------------------------------------------------------


def workspace_files(assignment):
    workspace = Path(assignment) / "workspace"
    files = []
    for path in sorted(workspace.rglob("*")):
        relative = path.relative_to(workspace)
        if path.is_file() and not SKIPPED_FOLDERS.intersection(relative.parts[:-1]):
            files.append(path)
    return files


def text_of(path):
    """The text of a file, or None for binary and very large files."""
    data = path.read_bytes()
    if len(data) > MAX_FILE_BYTES or b"\0" in data:
        return None
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return None


def assignment_info(assignment):
    """The assignment as the course module reads it: its README, title, chapter,
    requirements (group, text), criteria, and whether it has feedback already."""
    data = json.loads(cs("read", str(assignment)))
    chapter = re.match(r"(\d+)-", Path(assignment).parent.name)
    feedback = data.get("feedback") or {}
    return {
        "readme": (Path(assignment) / "README.md").read_text(encoding="utf-8"),
        "title": data["title"] or Path(assignment).name,
        "chapter": data.get("chapter") or (chapter.group(1) if chapter else ""),
        "requirements": [(item["group"], item["text"]) for item in data["requirements"]],
        "criteria": [item["name"] for item in data["criteria"]],
        "update": bool(feedback.get("entries")),
    }


def unchanged_from_template(path):
    """True when the file still has the content of the commit that added it."""
    added = git("log", "--diff-filter=A", "--format=%H", "--", str(path)).split()
    if not added:
        return False
    return subprocess.run(["git", "diff", "--quiet", added[-1], "HEAD", "--", str(path)], check=False).returncode == 0


def student_commits(assignment):
    """Commits that changed the workspace, without the template's first commit,
    merges and commits of the workflows."""
    log = git("log", "--no-merges", "--format=%h%x09%an%x09%s", "--", f"{assignment}/workspace")
    root = set(git("rev-list", "--max-parents=0", "--abbrev-commit", "HEAD").split())
    commits = []
    for line in log.splitlines():
        sha, author, subject = line.split("\t", 2)
        if sha not in root and not author.endswith("[bot]"):
            commits.append(f"{sha} {subject}")
    return commits


# --- Skills -------------------------------------------------------------------


def all_skills():
    """Central skills plus the course's own (a course skill replaces a central
    skill of the same name), sorted by name."""
    skills = {}
    for folder in [CENTRAL / "skills", COURSE_SKILLS]:
        for path in sorted(folder.glob("*/SKILL.md")):
            meta, body = front_matter(path.read_text(encoding="utf-8"))
            skills[meta.get("name", path.parent.name)] = {"meta": meta, "body": body.strip(), "folder": path.parent}
    return dict(sorted(skills.items()))


def matching_skills(assignment):
    """Skills whose metadata matches a file of the work: `files` (patterns
    of file names) and, if given, `contains` (a regular expression that the
    file's text must match)."""
    files = workspace_files(assignment)
    names = []
    for name, skill in all_skills().items():
        meta = skill["meta"].get("metadata") or {}
        patterns = str(meta.get("files", "")).split()
        contains = meta.get("contains")
        for path in files:
            if not any(fnmatch.fnmatch(path.name, pattern) for pattern in patterns):
                continue
            if contains and not re.search(contains, text_of(path) or "", re.M):
                continue
            names.append(name)
            break
    return names


# --- Commands -------------------------------------------------------------------


def command_setting(key):
    value = setting(key)
    if isinstance(value, bool):
        value = str(value).lower()
    print("" if value is None else value)


def command_skills(assignment):
    for name in matching_skills(assignment):
        print(f"{name}\t{all_skills()[name]['folder']}")


def command_inputs(assignment, folder):
    """Writes one file per prepared run, one answer per line."""
    runs = (read_yaml(COURSE_INPUTS) if COURSE_INPUTS.exists() else {}).get(Path(assignment).name) or []
    Path(folder).mkdir(parents=True, exist_ok=True)
    for number, answers in enumerate(runs, 1):
        lines = "".join(f"{'' if answer is None else answer}\n" for answer in answers)
        (Path(folder) / f"{number}.txt").write_text(lines, encoding="utf-8")


def command_prompt(assignment, checks_file):
    info = assignment_info(assignment)
    if not info["requirements"]:
        sys.exit(f"{assignment}/README.md has no requirements checklist.")
    feedback = Path(assignment) / "FEEDBACK.md"
    out = []
    add = out.append

    add((CENTRAL / "agent" / "feedback-rules.md").read_text(encoding="utf-8").strip())
    add(cs("instructions", "feedback").strip())
    skills = all_skills()
    names = matching_skills(assignment)
    add("# Feedback Skills\n\nThe best practices for the technologies in this work, in the long, explicit form.")
    for name in names:
        add(f"## Skill: {name}\n\n" + re.sub(r"^(#+) ", r"\1## ", skills[name]["body"], flags=re.M))

    add(f"# The Assignment\n\nFolder: `{assignment}` · chapter {info['chapter']} · title: {info['title']}")
    add("## README.md\n\n" + fenced(info["readme"], "markdown"))
    lines = ["## Requirements to Judge", "", "Judge each requirement with its id."]
    for number, (group, text) in enumerate(info["requirements"], 1):
        lines.append(f"- R{number}{f' ({group})' if group else ''}: {text}")
    if info["criteria"]:
        lines += ["", "## Criteria to Judge", ""]
        lines += [f"- C{number}: {name}" for number, name in enumerate(info["criteria"], 1)]
    add("\n".join(lines))

    commits = student_commits(assignment)
    add("# The Student's Work\n\n"
        + f"Commits that changed `workspace/`: {len(commits)}\n\n"
        + fenced("\n".join(commits) or "(none)", "text"))
    for path in workspace_files(assignment):
        name = f"`{path.relative_to(assignment)}`"
        if unchanged_from_template(path):
            name += " (unchanged from the template: given, not written by the student)"
        text = text_of(path)
        if text is None:
            add(f"## {name}\n\n(binary or larger than {MAX_FILE_BYTES} bytes: {path.stat().st_size} bytes)")
        else:
            add(f"## {name}\n\n" + fenced(text, LANGUAGES.get(path.suffix.lower(), "text")))
    checks = Path(checks_file).read_text(encoding="utf-8").strip()
    add("# Automatic Checks\n\n" + (checks or "No automatic checks for these files."))

    if info["update"]:
        last = git("log", "-1", "--format=%H", "--", str(feedback)).strip()
        changes = git("log", "--oneline", f"{last}..HEAD", "--", f"{assignment}/workspace") if last else ""
        diff = git("diff", last, "HEAD", "--", f"{assignment}/workspace")[:20_000] if last else ""
        add("# Earlier Feedback\n\nThis is an update: the work changed since the earlier feedback.\n\n"
            + fenced(feedback.read_text(encoding="utf-8")[-15_000:], "markdown")
            + "\n\nChanges since then:\n\n" + fenced(changes + "\n" + diff, "diff"))
    else:
        add("# Earlier Feedback\n\nThere is no earlier feedback: this is the first feedback.")

    add(cs("feedback", "--form", str(assignment)).strip())
    print("\n\n".join(out))


def check_secrets(text):
    for name in os.environ.get("FEEDBACK_SECRETS", "").split():
        value = os.environ.get(name, "")
        if len(value) >= 8 and value in text:
            raise AnswerError(f"the feedback contains the secret {name}")
    if re.search(r"\b(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_\w{20,}|sk-ant-[\w-]{20,})", text):
        raise AnswerError("the feedback contains something that looks like a token")


def not_running(status_file):
    """The reasons of the automatic checks why the work does not run, in the
    language of the course, from the "does-not-run <reason>" lines."""
    lines = Path(status_file).read_text(encoding="utf-8").splitlines() if Path(status_file).exists() else []
    texts = locale()["reasons"]
    reasons = []
    for line in lines:
        parts = line.split()
        if len(parts) >= 2 and parts[0] == "does-not-run" and parts[1] not in reasons:
            reasons.append(parts[1])
    return [texts.get(reason, reason) for reason in reasons]


def command_render(assignment, answer_file, status_file):
    """Hands the answer to `cs feedback`, which checks it and writes or extends
    FEEDBACK.md with the score. Exits with 3 for a rejected answer."""
    answer = Path(answer_file).read_text(encoding="utf-8", errors="replace")
    try:
        check_secrets(answer)
    except AnswerError as error:
        print(f"Answer rejected: {error}", file=sys.stderr)
        sys.exit(3)
    time = os.environ.get("FEEDBACK_TIME") or subprocess.run(
        ["date", "+%d.%m.%Y %H:%M"], capture_output=True, text=True, env={**os.environ, "TZ": "Europe/Vienna"}
    ).stdout.strip()
    args = ["feedback", str(assignment), str(answer_file), "--commits", str(len(student_commits(assignment))), "--time", time]
    for reason in not_running(status_file):
        args += ["--not-running", reason]
    result = subprocess.run([*CS, *args], capture_output=True, text=True, check=False)
    if result.returncode == 1:
        print(result.stderr.strip(), file=sys.stderr)
        sys.exit(3)
    if result.returncode != 0:
        sys.exit(f"cs feedback: {result.stderr.strip()}")
    print(result.stdout.strip())


def command_course(key):
    """A value of the course: course and language from the course module,
    runtime from .github/feedback.yml (empty when not set)."""
    value = course().get(key)
    print("" if value is None else value)


def main(argv):
    commands = {
        "setting": (command_setting, 1), "course": (command_course, 1), "skills": (command_skills, 1),
        "inputs": (command_inputs, 2),
        "prompt": (command_prompt, 2), "render": (command_render, 3),
    }
    if len(argv) < 2 or argv[1] not in commands or len(argv) - 2 != commands[argv[1]][1]:
        sys.exit(__doc__)
    commands[argv[1]][0](*argv[2:])


if __name__ == "__main__":
    main(sys.argv)

#!/usr/bin/env python3
"""The fixed part of the feedback: everything except the model's judgement.

Builds the prompt for the model from fixed parts, checks the model's answer and
writes FEEDBACK.md from it, including the score. Runs from the root of the
course checkout; the central repository is in .feedback/ (FEEDBACK_CENTRAL).

Usage:
  feedback.py setting <key>                     value from config.yml
  feedback.py course <key>                      value from .github/feedback.yml
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
  FEEDBACK_TIME     time for FEEDBACK.md, dd.mm.yyyy hh:mm (Europe/Vienna)
  FEEDBACK_SECRETS  names of environment variables that must not appear in
                    FEEDBACK.md
"""

import fnmatch
import json
import os
import re
import subprocess
import sys
from pathlib import Path

import yaml

CENTRAL = Path(os.environ.get("FEEDBACK_CENTRAL", ".feedback"))
CONFIG = Path(os.environ.get("FEEDBACK_CONFIG", CENTRAL / "config.yml"))
COURSE_CONFIG = Path(".github/feedback.yml")
COURSE_RULES = Path(".github/instructions/feedback-course.instructions.md")
COURSE_INPUTS = Path(".github/feedback/inputs.yml")
COURSE_SKILLS = Path(".github/feedback-skills")

SKIPPED_FOLDERS = {".git", "node_modules", "dist"}
MAX_FILE_BYTES = 30_000
MAX_SUGGESTIONS = 3
POINTS = {"met": 2, "partly": 1, "missing": 0}  # in half points
ICONS = {"met": "✅", "partly": "⚠️", "missing": "❌"}
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


def course():
    return read_yaml(COURSE_CONFIG)


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


def one_line(value):
    """A text of the answer as one line, without Markdown headings."""
    return re.sub(r"\s+", " ", str(value)).strip().lstrip("#").strip()


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


def section(readme, names):
    """The text of the first level-2 section with one of the names."""
    for name in names:
        match = re.search(rf"^## {re.escape(name)}[ \t]*\n(.*?)(?=^## |\Z)", readme, re.M | re.S)
        if match:
            return match.group(1)
    return ""


def requirements(readme, names):
    """The checklist items of the requirements section: (group, text)."""
    items, group, current = [], "", None
    for line in section(readme, names).splitlines():
        heading = re.match(r"^###+ (.+)", line)
        item = re.match(r"^- \[[ xX]\] (.*)", line)
        if heading:
            group, current = heading.group(1).strip(), None
        elif item:
            current = [item.group(1)]
            items.append((group, current))
        elif current is not None and (line.startswith((" ", "\t")) or not line.strip()):
            current.append(line.strip() and line.rstrip())
        else:
            current = None
    return [(group, "\n".join(lines).strip()) for group, lines in items]


def criteria(readme, names):
    """The names of the criteria: items like `- **Code Quality:** …`."""
    return re.findall(r"^- \*\*(.+?):?\*\*", section(readme, names), re.M)


def short(text, limit=90):
    """First sentence of a requirement without emphasis, cut at a space outside
    inline code."""
    lines = []
    for line in text.split("\n"):
        if not line.strip() or line.lstrip().startswith("- "):
            break
        lines.append(line.strip())
    first = re.sub(r"\*\*|__", "", " ".join(lines))
    in_code, cut = False, None
    for index, char in enumerate(first):
        if char == "`":
            in_code = not in_code
        elif char == "." and not in_code and first[index + 1 : index + 2] in ("", " "):
            return first[: index + 1] if index < limit else first[: cut or limit] + " …"
        elif char == " " and not in_code and index <= limit:
            cut = index
    if len(first) <= limit:
        return first
    return first[: cut or limit] + " …"


def assignment_info(assignment):
    readme = (Path(assignment) / "README.md").read_text(encoding="utf-8")
    texts = locale()
    title = re.search(r"^\*\*([^*]+)\*\*", readme, re.M)
    chapter = re.match(r"(\d+)-", Path(assignment).parent.name)
    return {
        "readme": readme,
        "title": title.group(1).strip() if title else Path(assignment).name,
        "chapter": chapter.group(1) if chapter else "",
        "requirements": requirements(readme, texts["readme"]["requirements"]),
        "criteria": criteria(readme, texts["readme"]["criteria"]),
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
    if COURSE_RULES.exists():
        rules = front_matter(COURSE_RULES.read_text(encoding="utf-8"))[1].strip()
        add("# Course Rules\n\n" + re.sub(r"^(#+) ", r"\1# ", rules, flags=re.M))
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

    last = git("log", "-1", "--format=%H", "--", str(feedback)).strip()
    if feedback.exists() and last:
        changes = git("log", "--oneline", f"{last}..HEAD", "--", f"{assignment}/workspace")
        diff = git("diff", last, "HEAD", "--", f"{assignment}/workspace")[:20_000]
        add("# Earlier Feedback\n\nThis is an update: the work changed since the earlier feedback.\n\n"
            + fenced(feedback.read_text(encoding="utf-8")[-15_000:], "markdown")
            + "\n\nChanges since then:\n\n" + fenced(changes + "\n" + diff, "diff"))
    else:
        add("# Earlier Feedback\n\nThere is no earlier feedback: this is the first feedback.")

    add(answer_instructions(info, update=feedback.exists() and bool(last)))
    print("\n\n".join(out))


def answer_instructions(info, update):
    def items(values):
        return "[\n" + ",\n".join(f"    {json.dumps(value, ensure_ascii=False)}" for value in values) + "\n  ]"

    example = "\n".join([
        "{",
        '  "requirements": ' + items({"id": f"R{n}", "status": "met | partly | missing", "comment": "…"}
                                     for n in range(1, len(info["requirements"]) + 1)) + ",",
        '  "criteria": ' + items({"id": f"C{n}", "comment": "…"} for n in range(1, len(info["criteria"]) + 1)) + ",",
        '  "run": "…",',
        '  "best_practices": ' + items([{"rating": "good | improve", "topic": "…", "text": "…"}]) + ",",
        '  "suggestions": ' + items([{"text": "…", "code": "…", "language": "typescript"}]) + ",",
        f'  "changes": "{"…" if update else ""}",',
        '  "summary": "…"',
        "}",
    ])
    return ("# Your Answer\n\n"
            "Answer with this JSON object and nothing else – no text before or after it:\n\n"
            + fenced(example, "json")
            + "\n\n- `requirements`: every id from R1 to R"
            + f"{len(info['requirements'])} exactly once, in this order.\n"
            + ("- `criteria`: every id from C1 to C"
               + f"{len(info['criteria'])} exactly once.\n" if info["criteria"] else "- `criteria`: an empty list.\n")
            + ("- `changes`: required, this is an update.\n" if update else "- `changes`: an empty string.\n")
            + f"- `suggestions`: at most {MAX_SUGGESTIONS}; `code` and `language` may be empty.\n"
            + "- `best_practices`: at least one entry.")


# --- Answer and FEEDBACK.md -----------------------------------------------------


def parse_answer(text, info, update):
    fence = re.search(r"```(?:json)?\s*\n(.*?)\n```", text, re.S)
    if fence:
        text = fence.group(1)
    start, end = text.find("{"), text.rfind("}")
    if start < 0 or end < start:
        raise AnswerError("no JSON object")
    try:
        answer = json.loads(text[start : end + 1])
    except json.JSONDecodeError as error:
        raise AnswerError(f"invalid JSON: {error}") from error
    if not isinstance(answer, dict):
        raise AnswerError("the answer is not a JSON object")

    def items(key, minimum=0, maximum=None):
        value = answer.get(key)
        if not isinstance(value, list) or not all(isinstance(item, dict) for item in value):
            raise AnswerError(f"`{key}` is not a list of objects")
        if len(value) < minimum or (maximum is not None and len(value) > maximum):
            raise AnswerError(f"`{key}` has {len(value)} entries")
        return value

    def text_field(item, key, required=True):
        value = item.get(key, "")
        if not isinstance(value, str) or (required and not value.strip()):
            raise AnswerError(f"`{key}` is missing or empty")
        return value

    expected = [f"R{n}" for n in range(1, len(info["requirements"]) + 1)]
    found = items("requirements")
    if [item.get("id") for item in found] != expected:
        raise AnswerError(f"requirement ids {[item.get('id') for item in found]} instead of {expected}")
    for item in found:
        if item.get("status") not in POINTS:
            raise AnswerError(f"status {item.get('status')!r} of {item['id']}")
        text_field(item, "comment")
    expected = [f"C{n}" for n in range(1, len(info["criteria"]) + 1)]
    found = items("criteria")
    if sorted(item.get("id", "") for item in found) != sorted(expected):
        raise AnswerError(f"criteria ids {[item.get('id') for item in found]} instead of {expected}")
    for item in found:
        text_field(item, "comment")
    for item in items("best_practices", minimum=1):
        if item.get("rating") not in ("good", "improve"):
            raise AnswerError(f"rating {item.get('rating')!r}")
        text_field(item, "topic")
        text_field(item, "text")
    for item in items("suggestions", maximum=MAX_SUGGESTIONS):
        text_field(item, "text")
        text_field(item, "code", required=False)
        text_field(item, "language", required=False)
    text_field(answer, "run")
    text_field(answer, "summary")
    if re.search(r"\d\s*%", answer["summary"]):
        raise AnswerError("the summary contains a percentage; the script adds the score")
    if update:
        text_field(answer, "changes")
    return answer


def score(answer, status_lines):
    """Score in percent from the statuses (✅ 1, ⚠️ ½, ❌ 0), rounded half up,
    and the reasons why the work does not run (cap 50 %)."""
    statuses = [item["status"] for item in answer["requirements"]]
    half_points = sum(POINTS[status] for status in statuses)
    percent = (half_points * 100 + len(statuses)) // (2 * len(statuses))
    reasons = []
    for line in status_lines:
        parts = line.split()
        if len(parts) >= 2 and parts[0] == "does-not-run" and parts[1] not in reasons:
            reasons.append(parts[1])
    if reasons:
        percent = min(percent, 50)
    return percent, reasons


def render(answer, info, percent, reasons, commits, update):
    texts = locale()
    time = os.environ.get("FEEDBACK_TIME") or subprocess.run(
        ["date", "+%d.%m.%Y %H:%M"], capture_output=True, text=True, env={**os.environ, "TZ": "Europe/Vienna"}
    ).stdout.strip()
    h2 = "###" if update else "##"
    heading = lambda key: f"{h2} {texts['headings'][key]}"  # noqa: E731
    out = []
    if update:
        out += ["---", "", f"## {texts['update'].format(time=time)}", "", one_line(answer["changes"]), ""]
    else:
        out += [f"# {texts['title'].format(title=info['title'], time=time)}", ""]

    out += [heading("assessment"), ""]
    for number, (item, (_, text)) in enumerate(zip(answer["requirements"], info["requirements"]), 1):
        out.append(f"- {ICONS[item['status']]} **{number}. {short(text)}** – {one_line(item['comment'])}")
    out.append("")
    comments = {item["id"]: item["comment"] for item in answer["criteria"]}
    for number, name in enumerate(info["criteria"], 1):
        out.append(f"- **{name}:** {one_line(comments[f'C{number}'])}")
    out.append(f"- **{texts['run']}:** {one_line(answer['run'])}")
    out.append(f"- **{texts['commits']}:** {len(commits)}")
    out.append("")

    out += [heading("best_practices"), ""]
    for item in answer["best_practices"]:
        icon = "✅" if item["rating"] == "good" else "💡"
        out.append(f"- {icon} **{one_line(item['topic'])}:** {one_line(item['text'])}")
    out.append("")

    out += [heading("suggestions"), ""]
    for item in answer["suggestions"]:
        out += [f"💡 {one_line(item['text'])}", ""]
        if item.get("code", "").strip():
            language = re.sub(r"[^a-z0-9]", "", str(item.get("language", "")).lower())
            out += [fenced(item["code"], language), ""]
    if not answer["suggestions"]:
        out += [texts["no_suggestions"], ""]

    out += [heading("summary"), ""]
    if reasons:
        names = ", ".join(texts["reasons"].get(reason, reason) for reason in reasons)
        out += [f"⚠️ {texts['capped'].format(reasons=names)}", ""]
    out += [f"**{texts['score'].format(score=percent)}** – {one_line(answer['summary'])}", ""]
    return "\n".join(out)


def check_secrets(text):
    for name in os.environ.get("FEEDBACK_SECRETS", "").split():
        value = os.environ.get(name, "")
        if len(value) >= 8 and value in text:
            raise AnswerError(f"the feedback contains the secret {name}")
    if re.search(r"\b(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_\w{20,}|sk-ant-[\w-]{20,})", text):
        raise AnswerError("the feedback contains something that looks like a token")


def command_render(assignment, answer_file, status_file):
    info = assignment_info(assignment)
    feedback = Path(assignment) / "FEEDBACK.md"
    update = feedback.exists() and bool(git("log", "-1", "--format=%H", "--", str(feedback)).strip())
    try:
        answer = parse_answer(Path(answer_file).read_text(encoding="utf-8", errors="replace"), info, update)
        status = Path(status_file).read_text(encoding="utf-8").splitlines() if Path(status_file).exists() else []
        percent, reasons = score(answer, status)
        part = render(answer, info, percent, reasons, student_commits(assignment), update)
        check_secrets(part)
    except AnswerError as error:
        print(f"Answer rejected: {error}", file=sys.stderr)
        sys.exit(3)
    if update:
        old = feedback.read_text(encoding="utf-8")
        feedback.write_text(old.rstrip("\n") + "\n\n" + part, encoding="utf-8")
    else:
        feedback.write_text(part, encoding="utf-8")
    print(f"Score {percent} %{' (capped: ' + ', '.join(reasons) + ')' if reasons else ''}")


def command_course(key):
    """A value of the course file .github/feedback.yml (empty when not set)."""
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

#!/usr/bin/env python3
"""Fake engine for the tests: builds an answer from the prompt.

FAKE_MODE: good (all met), partly (R1 partly, R2 missing), nojson, wrongids,
percent (score in the summary), secret (the engine secret in a comment).
Every prompt is appended to FAKE_LOG.
"""
import json, os, re, sys

prompt = open(sys.argv[1], encoding="utf-8").read()
with open(os.environ["FAKE_LOG"], "a", encoding="utf-8") as log:
    log.write(prompt + "\n=====PROMPT-END=====\n")
mode = os.environ.get("FAKE_MODE", "good")
requirements = re.findall(r"^- (R\d+)", prompt, re.M)
criteria = re.findall(r"^- (C\d+):", prompt, re.M)
update = "This is an update" in prompt
answer = {
    "requirements": [{"id": r, "comment": f"Gut gemacht ({r}).", "status": "met"} for r in requirements],
    "criteria": [{"id": c, "comment": f"Passt ({c})."} for c in criteria],
    "run": "Der Beispiellauf passt.",
    "best_practices": [{"rating": "good", "topic": "Names", "text": "Klare Namen."},
                       {"rating": "improve", "topic": "Output", "text": "Template Literals\nverwenden."}],
    "suggestions": [{"text": "Nutze `const`.", "code": "const name = prompt(\"Name?\") ?? \"\";", "language": "typescript"}],
    "changes": "Du hast den NaN-Fall ergänzt." if update else "",
    "summary": "Super Arbeit!",
}
if mode == "partly":
    answer["requirements"][0]["status"] = "partly"
    answer["requirements"][1]["status"] = "missing"
elif mode == "wrongids":
    answer["requirements"] = answer["requirements"][1:]
elif mode == "percent":
    answer["summary"] = "Super, 100 % erfüllt!"
elif mode == "secret":
    answer["run"] = "Token " + os.environ.get("FAKE_TOKEN", "")
text = json.dumps(answer, ensure_ascii=False, indent=2)
print("not json at all" if mode == "nojson" else f"Here is the feedback:\n```json\n{text}\n```")

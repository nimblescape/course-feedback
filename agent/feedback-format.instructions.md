---
applyTo: "**/FEEDBACK.md"
---

# FEEDBACK.md – Format and Score

<!-- Central file from majikmate/course-feedback, copied into the course
checkout before every run. The course file feedback-course.instructions.md
gives the language and the heading names. -->

## Language and Tone

- Write in the language that the course file names, simple and clear: short
  sentences, no jargon without explanation.
- Always start with what works well, then guide towards improvements.
- Never use harsh words. Use the soft phrases that the course file gives.
- End with a short encouraging sentence.
- Code examples use English identifiers, English comments and real code of the
  course, written in the course conventions.
- Keep it compact: one line per requirement, at most three suggestions.

## Time

All timestamps use the format `dd.mm.yyyy hh:mm` in the **Europe/Vienna**
timezone. Use the time given in the prompt (`Current time (Europe/Vienna): …`).
If the prompt gives none, run `TZ=Europe/Vienna date '+%d.%m.%Y %H:%M'`. Never
guess the time.

## Initial Feedback

The headings in square brackets are placeholders: use the names from the course
file.

```markdown
# Feedback: [Assignment Title] – dd.mm.yyyy hh:mm

## [Assessment]

✅ / ⚠️ / ❌ one line per README requirement with a short explanation. Then one
line per criterion, judged in words. Then one line on what you ran and what
happened (commands, inputs, output, validation result) and one line on the
commits.

## [Best Practices]

- ✅ [Topic of a best-practice file]: what is done well …
- 💡 [Topic of a best-practice file]: what could be improved …

## [Suggestions]

💡 Up to three concrete improvements with short code examples.

## [Summary]

One or two sentences with the **mandatory score** in percent and an encouraging
end.
```

- `[Assignment Title]` is the bold title in the first paragraph of the README.
- Under [Best Practices], list only topics that have something to say.
- Icons: ✅ met · ⚠️ partially met · ❌ missing · 💡 suggestion.

## Update Section

When `FEEDBACK.md` exists and the work changed:

1. Keep every earlier section and its timestamp untouched.
2. Append a horizontal rule `---`.
3. Add `## Update – dd.mm.yyyy hh:mm` with the current time.
4. One or two sentences about what changed since the last feedback.
5. Then the four sections as third-level headings (`### [Assessment]`,
   `### [Best Practices]`, `### [Suggestions]`, `### [Summary]`).
6. Praise concrete improvements explicitly.

## Score

- The score counts **only the README Requirements checklist**: each ✅ counts 1
  point, each ⚠️ half a point, each ❌ 0 points. Score = points ÷ number of
  requirements × 100, rounded to a whole percent. If the README weights its
  requirements, use its weights.
- The three criteria are judged in words under [Assessment]; they do not change
  the score. Best practices never lower the score.
- Work that gives the right result but ignores a construct the README demands
  counts that requirement as ⚠️.
- **Cap:** work that does not run (the course file says what this means) cannot
  score above 50 %.
- Never give a lower score than the previous feedback for unchanged work.
- Be strict on requirements and generous on creativity.
- The [Summary] always contains the score as a number with a percent sign, for
  example `90 %`.

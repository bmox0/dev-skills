---
name: review
description: Review a commit range from a fresh, read-only context — Defects, Conventions and Observations, each with file:line and a source. Use on every unit built from a brief, on inline work with logic, or on any range the user names.
---

# Review

The reviewer seat: a fresh context on the strong model, read-only. It never
edits, stages or commits. Dispatch `dev-skills:reviewer`, or review in a fresh
session. Any range works: a unit's branch, last week's commits, someone else's
work.

**Receives:** the range `BASE..HEAD`, the brief or the todo, and where the
project's rules live (CLAUDE.md, its style skills).

1. **Pin the range:** `git log --oneline BASE..HEAD` and
   `git diff --stat BASE..HEAD`. A range that does not resolve, or is empty,
   stops here.
2. **Read the intent first:** the brief's Goal, Decisions, Shape, Steps and
   Acceptance, and the project's rules. Without a brief, ask what the change is
   for; without an answer, say the report judges the code and not whether it
   is the right code.
3. **Run the project's checks**, as its `## Environment` block names them. Red
   is a Defect.
4. **Read the diff** against [CRITERIA.md](references/CRITERIA.md). Tests are
   part of the diff.

**Returns** three lists, most serious first, each item with `file:line` and its
source:

- **Defects**: correctness, behaviour, security, data, an unreachable scenario,
  a test that cannot fail;
- **Conventions**: departures from the project's written rules;
- **Observations**: true, not findings.

Then what could not be judged from the range, and why.

**After:** Defects go to the builder that holds the unit warm, for one fix
round; the fix commits get a fresh review of their own. A Defect still open
after two rounds goes to the user. Conventions are applied in one batch and
listed in the merge summary, with no second review. Never review until clean.

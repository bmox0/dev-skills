---
name: spec
description: Use when one finished task, built outside the pipeline, has to leave its rules in git — what must stay true here, and why — or when the project's rules in `docs/spec/` are to be read or listed.
---

# Spec

The project's rules live in `docs/spec/`, one file per area, each rule with its reason and its scenarios. `spec.py` writes them from a plan-shaped file; the grammar and the commands are in [`FORMAT.md`](references/FORMAT.md). A rule is changed through a plan or this skill, never by hand. The pipeline (`grill`, `plan` and `build`) calls `spec.py` itself; this skill's standalone mode is for work done outside it.

The script is called as `python3 "<this skill's directory>/spec.py"`. `<this skill's directory>` is the folder this `SKILL.md` sits in: Claude Code gives it as the skill's base directory, Codex in its skill list.

## Reading the rules

`list` for every area and rule, `show <id>` for one rule with its reason, scenarios and the plans that changed it.

## One finished task

A short grill and the same script.

1. **Read the task's diff and the existing rules**: `list`, then the area files it touches. Done when you can say which rules the diff keeps, changes or adds.
2. **Ask the user only what the code cannot show**: what must stay true here, and why. A rule that code structure, a word or a one-off check would carry goes elsewhere (FORMAT.md). Done when each rule step 1 found has a statement and a reason the user gave or confirmed.
3. **Write `.ai-workflow/spec/<date>-<slug>.md`** with a title, Result, Done (use cases, each a scenario a rule can cite) and `## Spec`. Done when every added rule cites a Done item and every changed rule has its reason.
4. **`check`** the file, fix every line it reports, run it again until it is silent; then **`write`**.
5. **Show `git status --short docs/spec/`, `git diff` and any new file.** Commit only on the user's word.

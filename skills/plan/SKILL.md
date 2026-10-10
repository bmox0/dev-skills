---
name: plan
description: Write the plan a change is built from — one screen, phases with territories and a graph, how it is checked, what done looks like. Use after a grill, a discussion or a bug's accepted cause, before any code is written.
---

# Plan

In Codex, read [CODEX.md](../../references/CODEX.md) first.

This session is the orchestrator: it writes the plan and never edits code.

A plan is always a file, one screen, about 1000 words. It holds only what an
implementer cannot decide alone: the product decisions with a reason each, the
interfaces where two phases meet, what is out, how it is checked. No file lists
beyond territories, no code, no mechanisms: implementers explore the code
themselves.

A plan is a finished thing: its Result is the feature, done, nothing deferred.
Work that does not fit one plan becomes an epic only on the user's word:
propose it with the reason, and the user decides (`dev-skills:epic`).

## Before writing

- The decisions are settled: by a grill, a discussion, or a bug's accepted
  cause.
- After a grill or a discussion, a prototype was offered. If not, offer one in a
  line: "A prototype? An HTML file, inside the app with real data, or code for
  the logic?" (`dev-skills:prototype`). The user may decline.
- A worker reads the code the plan touches, a Sonnet subagent that returns
  paths and seams, so the territories are real. Code outside this repository
  that a decision points at gets its path.
- Checks takes the project's commands from its `AGENTS.md` or `CLAUDE.md`:
  [environment-contract.md](references/environment-contract.md).

## The file

`.ai-workflow/plans/YYYY-MM-DD-<slug>.md`, where `<slug>` is the slug of the
branch the plan will be built on. If `git check-ignore -q .ai-workflow` fails,
add `.ai-workflow` to `$(git rev-parse --git-path info/exclude)`. It is written
with Status `draft`. A worked example: [example.md](references/example.md).

```markdown
# Plan: <what the user gets, in a few words>

Status: <draft | approved | building | at the human gate | at code review | passed | a merge-request link | merged> · branch `<branch>` · base `<sha>`
Prototype: <path, the chosen variant> | none

## Result

<Two or three lines: what the user can do when this plan is done.>

## Approach

<A short paragraph: how it is solved and how the parts fit together.>

- <A decision the implementer cannot make alone> — <why, in one line>

## Out of scope

- <…>

## Phases

### <n>. <task> — `<waiting | in progress | done>`

<What to build and why; what becomes true when it is done.>
Territory: <the directories or files this phase changes>
Waits for: <phases, and the interface it uses from them> | nothing

## Checks

- Every phase: <the project's commands>, on its own territory while other phases run.
- After all phases: <the full commands>; a review against the project's rules;
  e2e through <browser | simulator | curl | CLI>, <where the system runs>.
- Gate: <small | normal | wide> — <why, in one line>

## Done

1. <do this> → <see that>
2. <do this> → <see that> — you check
```

## Phases and the graph

- 2–5 phases, each a task for a capable engineer. The first one gives
  something to look at.
- Phases whose territories overlap never run side by side: one waits for the
  other. An interface is written out only where two phases meet.
- A bug: phase 1 starts from the red test that reproduces it. A refactor, or an
  improvement with tests: phase 1 pins today's behaviour with tests.
- Under an epic, an `Epic: <path>` line follows Status; the epic's decisions are
  not repeated.

## Handing it over

Before showing it:

- **What e2e cannot do.** A Done use case e2e cannot reach with the project's
  Environment block, its Access and Devices lines included, or one judged by
  its look alone, is marked `you check`: the user checks it at the human gate.
  What e2e needs from the user is asked now, with the go.
- **The gate level** goes into Checks, from the table in
  [gate.md](../build/references/gate.md).
- **Other plans** from `building` to `passed` whose territories overlap
  this one's are named in a line.

Show the user the path, the Result, and in one line the graph, the level and
the plan's word count (`1 → 2 ∥ 3 · normal · 1100 words`). The user's "go"
approves the plan and its graph: set Status to `approved`, with the branch
named; build writes the base when it cuts it.

Then offer, in one line, where to build it: here for a small task, or a new
session started from the plan file for anything bigger. The user picks; the
build is `dev-skills:build <plan>`.

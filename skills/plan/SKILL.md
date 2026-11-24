---
name: plan
description: Write the plan a change is built from — one screen, phases with territories and a graph, how it is checked, what done looks like. Use after a grill, a discussion or a bug's accepted cause, before any code is written.
---

# Plan

Read shared `AGENTS.md` and the executor contract:
[SESSIONS.md](../../references/SESSIONS.md).

Planning uses primary; research helpers use secondary. This session plans and never edits code.

`CLI` is `python3 "<this skill's directory>/../build/pipeline.py"`.
Run `CLI workflow` at entry or `CLI status <plan>` with a plan.

A plan is always a file, about 1000 words. It holds only what an
implementer cannot decide alone: the product decisions with a reason each, the
interfaces where two phases meet, what is out, how it is checked. Implementers explore the code; omit mechanisms and file lists beyond territories.

Its Result is a finished feature.
Work that does not fit one plan becomes an epic only on the user's word:
propose it with the reason, and the user decides (`dev-skills:epic`).

## Before writing

- The decisions are settled: by a grill, a discussion, or a bug's accepted
  cause.
- After a grill or a discussion, a prototype was offered. If not, offer one in a
  line: "A prototype? An HTML file, inside the app with real data, or code for
  the logic?" (`dev-skills:prototype`). The user may decline.
- A secondary worker reads the affected code and returns paths and seams,
  including paths outside the repository that decisions refer to. For each
  territory the worker matches applicable project and session skills and
  `CLI spec list` areas by description.
- The run file exists, `.ai-workflow/plans/YYYY-MM-DD-<slug>.run.toml`
  (`dev-skills:run-file`); if not, write it first. The plan takes its name with
  `.md`. `approve` validates without recording consent.
- Get Checks from the run file's `[checks]` via `CLI run show <plan>`.
  The Environment block of `AGENTS.md` fills only what the run
  file lacks: [environment-contract.md](references/environment-contract.md).
- The plan uses the Language line in
  [environment-contract.md](references/environment-contract.md). The conversation and the gate
  page stay in the user's language.

## The file

The run file's name with `.md`. It is written with Status `draft` and base `—`; build writes the SHA. A worked example: [example.md](references/example.md).

```markdown
# Plan: <what the user gets, in a few words>

Status: <draft | approved | building | at the human gate | passed | a merge-request link | merged> · branch `<branch>` · base `<sha>`
Grill: <done | skipped>
Prototype: <path, the chosen variant> | none

## Result

<One sentence on the problem, then two or three lines: what the user can do when this plan is done.>

## Approach

<A short paragraph: how it is solved and how the parts fit together.>

- <A decision the implementer cannot make alone> — <why, in one line>

## Out of scope

- <…>

## Phases

### <n>. <task> — `<waiting | in progress | done>`

<What to build and why; what becomes true when it is done.>
Territory: <the directories or files this phase changes>
Skills: <each skill whose rules this phase's code follows, by its SKILL.md path> | none
Spec: <the area files that exist before this plan, `docs/spec/<area>.md`, whose rules this phase's code must keep> | none
Waits for: <phases, and the interface it uses from them> | nothing

## Checks

- Every phase: <the project's commands>, on its own territory while other phases run.
- After all phases: <the full commands>; a review against the project's rules;
  e2e through <browser | simulator | curl | CLI>, <where it runs>, at <each
  width: the prototype's and the user's real screen>.
- Gate: <small | normal> — <why, in one line>

## Done

1. <do this> → <see that>
2. <do this> → <see that> — you check

## Spec

<`+`, `~` or `-` for every rule this plan adds, changes or removes; else `none`>
```

Record `Grill: done` after a grill or `Grill: skipped` when omitted.
Leave the field out when its history is unavailable.

`## Spec` records lasting product rules, including decisions made without
the user and rules the grill dropped or changed. Use an ADR for code structure.
Choose the rule, ID, statement and reason from the settled decisions, following
[FORMAT.md](../spec/references/FORMAT.md). Include the section even for bugs,
with `none` when no rule changes.

## Phases and the graph

- 2–5 phases, each a task for a capable engineer. The first one gives
  something to look at.
- Phases whose territories overlap never run side by side: one waits for the
  other. An interface is written out only where two phases meet.
- A bug: phase 1 starts from the red test that reproduces it. A refactor, or an
  improvement with tests: phase 1 pins today's behaviour with tests.
- Under an epic, an `Epic: <path> · row <n>` line follows Status; the epic's decisions are
  not repeated.

## Handing it over

Before showing it:

- **The spec.** Run `CLI spec check <plan> --base <default branch>` until it is silent.
- **What e2e cannot do.** A Done use case e2e cannot reach with what the run file
  gives (`[run]` keys, `[checks].dev` and `url`, `[isolation]`), or one judged by
  its look alone, is marked `you check`: the user checks it at the human gate.
  What e2e needs goes in the run file's `[run]` keys, through
  `dev-skills:run-file`; what the file lacks is `you check`.
- **The gate level** follows
  [gate.md](../build/references/gate.md).

Run `CLI approve <plan>` until validation passes; compilation records no consent.
Show the proposed run, including executor presets, and obtain explicit approval:
`CLI run approve <plan> --by <name> --words "<unchanged approval>"`.
Reuse recorded authorization; never invent consent or re-ask.

Write a linked summary following [resume.example.md](references/resume.example.md),
≤350 words in the conversation language: Result, phases, Spec, checks and limits.
Ask approval of that summary and record it:
`CLI summary approve <plan> --file <summary> --by <name> --words "<unchanged approval>"`.
For a designated acceptor also supply `--acceptor <name> --authority "<granted scope>"`.
This sets Status to `approved` only with both current approvals. Changed run,
plan or Spec needs the affected consent renewed; progress survives.

**STOP.** Summary approval launches nothing. A subsequent instruction chooses
herdr, a native independent session or manual handoff through
[SESSIONS.md](../../references/SESSIONS.md).

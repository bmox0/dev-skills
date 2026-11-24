---
name: build
description: Build an approved plan — its branch, implementers run by the plan's graph, the E2E gate, then the human gate. Use when the user says build, with a plan file.
---

# Build

Read shared `AGENTS.md` and the executor contract:
[SESSIONS.md](../../references/SESSIONS.md).

`build <plan>` starts on the separate handoff instruction in
[SESSIONS.md](../../references/SESSIONS.md). The coordinator uses primary
and never edits code. Select each worker's executor from the shared contract.

## 1. The branch

Read the plan, its epic and the project's `AGENTS.md`.
`CLI` is `python3 "<this skill's directory>/pipeline.py"`. It updates statuses,
the base and the epic row. `CLI status` lists runs from `building` to `passed`.
Report shared territories to the designated contact.

Run `CLI build start --base <ref> [--worktree <path>] <plan>`. You name the
base. It reports the checked-out
branch and a dirty tree as facts: when another plan's branch is checked out
here, pass a worktree of its own. Every phase commits there.
From a worktree, hand every implementer, worker and judge its path; the plan,
its notes and the rest of `.ai-workflow/` stay in the main tree, and the app
runs from the worktree on a port of its own.

On resume, use `CLI status --current` to find plans or `CLI status <plan>`
to see its tree, current owner and next action. Reuse the existing writer.

## 2. The graph

`CLI status <plan>` names the phases that are ready. Per ready phase, all at
once: `CLI phase start <plan> <n>`, then `CLI brief implementer --provider <provider> <plan> <n>`,
and a `dev-skills:implementer` in the background whose prompt is the path it
prints. To go against a fact the CLI reports, pass `--note` with your reason; it
reaches the gate page. When an implementer finishes, `CLI phase done <plan>
<n>` checks outcomes and commits and prints the next actions, including gate
start after the last phase. Relay any refusal to the implementer.

- **Messages go through you.** An implementer writes to you for a file outside
  its territory, or a product call the plan does not hold, and carries on
  meanwhile. `CLI owner <plan> <path>` names who holds a path: when no one
  does, `CLI grant <plan> <n> <path>`; otherwise pass the question to that
  phase. Answer a product call yourself, from the plan, its epic and what the
  user said, and report to the designated contact; irreversible calls, deleting
  data, sending outside, production, wait for the user through the designated
  contact; relay their words. Answer through the agreed channel; record it with `CLI decision`.
  Report persistent `index.lock`; never delete it blindly.
- **Decided without you**: rulings and calls are `CLI decision` records, which
  `CLI status <plan>` lists for the human gate page.

## 3. The E2E gate

When every phase is done, `CLI gate start <plan>`. It writes and commits the
rules, prints the level and the paths that raised it, and runs the full checks
(`CLI status <plan>` shows the run). It runs a few minutes: run it in the
background or with a long timeout, as `fix done` and `round done`; a killed
call keeps each command that finished, and the next one runs the rest again. Fix a plan refusal
in `## Spec`; a stale base, by `CLI plan base <plan> $(git merge-base
<default> HEAD)` and `gate start` again.

Then the rest of the gate, by [gate.md](references/gate.md); read it then, not
before.

Then a fresh `dev-skills:judge` ([judge.md](references/judge.md)): `CLI brief
judge --provider <provider> [--note "<…>"] <plan>`, and the prompt is the path it prints. The judge
records its verdict with `CLI verdict` and returns:

- `pass: <path>` and its report: the branch is landed. Go to 4.
- `round`: `CLI round start <plan>` takes the judge's notes; run the round
  ([rounds.md](references/rounds.md)), then a fresh judge.
- `question: <…>`, even after a round: run the round, ask the user, a fresh
  judge with the answer.
- `evidence owed: <verify|reviewer> — <what>`: the judge recorded it with
  `CLI verdict evidence-owed`. Follow `CLI status <plan>` for the reviewer
  brief, Verify cases, or the explicit E2E exception. Then run the judge again.
- `land stopped: <…>`: the judge again. Code turns a stop that keeps coming
  into a question to the user; `CLI brief judge --provider <provider>` refuses until `--note`
  holds their answer.

A verdict that stops rounds says why in `CLI status`; it lands as a pass.

## 4. The human gate

Run `CLI page --note "<how to try it>" [--message "<merge message or request
title>"] <plan>`: it sets `at the human gate` and draws `## Human gate` from the
records, which you never edit. The note explains trying the app, from
a worktree how to run it there. The message is needed unless the run ends
`ff-only`; draft it from the plan's Result by `dev-skills:commit-work`. Report
the page and review location to the designated contact, then wait: [SESSIONS.md](../../references/SESSIONS.md). For a flagged result, say
whether later changes touched it.

On approval from the user or designated acceptor within granted authority:
`CLI accept <plan> --by <name> --words "<unchanged approval>"` binds it to the
current page and sets `passed`. Run `dev-skills:finish` when the instruction
authorizes the configured ending; reuse existing authorization.

## 5. Notes and rounds

From the first phase on, record the user's notes in their words:
`CLI note add --text "<…>" --cause <cause> <plan>`. Nothing starts on one; no
running agent hears of it. The notes file is code's. At the gate, give each note
a cause from the seven in [rounds.md](references/rounds.md), propose it, let the
user correct it (`CLI note edit`), and mark its source against
`<slug>.judge.md`'s Prediction when its round is done. A note changing
the approach or leaving the territories is proposed as `task`; on the user’s
confirmation, list it without building it. A round, on the user's word, builds
every open note or a conflict at `finish` like a phase (reviewer using secondary),
then the judge, dispatched through `CLI brief judge --provider <provider>` like every judge, which lands, and back to the gate.

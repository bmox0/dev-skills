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
`CLI` is the installed `ds` selected for the plan, or
`python3 "<this skill's directory>/pipeline.py"` on the legacy path.
`CLI status` lists project runs. Report shared territories to the contact.

For a ds task, run `CLI build start <plan>` to reuse its registered checkout.
For legacy, run `CLI build start --base <ref> [--worktree <path>] <plan>`.
The command sets `building`. Every phase commits in the reported worktree.
Give each worker that tree and the absolute plan path. See
[workflow paths](../../references/WORKFLOW-PATHS.md) for history and setup.

On resume, use `CLI status --current` to find plans or `CLI status <plan>`
to see its tree, owner and next action. Reuse the existing writer. Follow
[typed actions](../../README.md#the-pipeline) with `--json --provider NAME`.

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

When phases are done, `CLI gate start <plan>` commits the rules, prints the
level and runs full checks. Run `gate start`, `fix done` and `round done` in the
background or with a long timeout.
After interruption, follow `CLI status <plan>` to wait, investigate ownership
or run the printed retry. It reruns the suite or reuses matching results.
Fix plan refusals in `## Spec`. For a stale base, run `CLI plan base <plan>
$(git merge-base <default> HEAD)`, then `gate start` again.

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

After judge and land, write the [guide to the landed build](references/human-guide.md).
Run `CLI page <plan> --guide-file <path> [--message "<merge message or request
title>"]` (or `--guide "<Markdown>"`). The message is needed unless the run ends
`ff-only`. Draft it from the plan's Result by `dev-skills:commit-work`.
The command validates the guide, records it on `## Human gate`, sets `at the human gate` and prints it.
Send the printed guide verbatim and link to the current page, then wait for the
designated contact by [SESSIONS.md](../../references/SESSIONS.md).

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

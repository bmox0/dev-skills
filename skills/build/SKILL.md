---
name: build
description: Build an approved plan — its branch, implementers run by the plan's graph, the E2E gate, then the human gate. Use when the user says build, with a plan file.
---

# Build

In Codex, read [CODEX.md](../../references/CODEX.md) first.

`build <plan>`. This session is the orchestrator: it runs the graph, relays
messages and sorts findings. It never edits code: implementers write it,
Sonnet workers check it.

## 1. The branch

Read the plan, its epic, and the project's `AGENTS.md` or `CLAUDE.md`.
`CLI` is `python3 "<this skill's directory>/pipeline.py"`; every status, the
base and the epic's row change through it, never by hand. `CLI status` lists
the other plans from `building` to `passed`: a territory this plan shares with
one is named to the user in a line.

Run `CLI build start --base <ref> [--worktree <path>] <plan>`. You name the
base, which is not always the default branch. It reports the checked-out
branch and a dirty tree as facts: when another plan's branch is checked out
here, pass a worktree of its own. Every phase commits to this branch, in that one tree.
From a worktree, hand every implementer, worker and judge its path; the plan,
its notes and the rest of `.ai-workflow/` stay in the main tree, and the app
runs from the worktree on a port of its own.

Resuming: `CLI status <plan>` prints the branch and the tree it lives in; work there.

## 2. The graph

`CLI status <plan>` names the phases that are ready. Per ready phase, all at
once: `CLI phase start <plan> <n>`, then `CLI brief implementer <plan> <n>`,
and a `dev-skills:implementer` in the background whose prompt is the path it
prints. To go against a fact the CLI reports, pass `--note` with your reason; it
reaches the gate page. When an implementer finishes, `CLI phase done <plan>
<n>` checks its report and commits and prints what is ready next; a failure
goes back to the implementer as printed.

- **Messages go through you.** An implementer writes to you for a file outside
  its territory, or a product call the plan does not hold, and carries on
  meanwhile. `CLI owner <plan> <path>` names who holds a path: when no one
  does, `CLI grant <plan> <n> <path>`; otherwise pass the question to that
  phase. Answer a product call yourself, from the plan, its epic and what the
  user said, and tell the user in a line; only an irreversible one, deleting
  data, sending outside, production, waits for the user, whose answer goes on
  in their words. Answer with `SendMessage`, and record it with `CLI decision`.
  No git running: clear a stuck `index.lock`.
- **Decided without you**: rulings and calls are `CLI decision` records, which
  `CLI status <plan>` lists for the human gate page.

## 3. The E2E gate

When every phase is done, before every re-check, and before the review of a
round, run `CLI spec write <plan>` (the grammar
is in the `spec` skill's `references/FORMAT.md`) in the plan's branch tree, its worktree when
there is one, never the main tree of another branch, and commit `docs/spec/`
alone with plain git: a script's output, not code. When
nothing changed there is nothing to commit; `git commit` exiting 1 is no
failure. A refusal naming the plan is yours to fix in its `## Spec`; a stale
base, by the base `CLI status` shows or `--base $(git merge-base <default> HEAD)`;
one naming `docs/spec/` is a finding.

Then run the gate at the level the plan's Checks names, by
[gate.md](references/gate.md); read it then, not before.

Then a fresh `dev-skills:judge` ([judge.md](references/judge.md)): put its
case and what judge.md lists for it in `CLI brief judge --note "<…>" <plan>`,
and the prompt is the path it prints. It returns:

- `pass: <path>` and its report: the branch is landed. Go to 4.
- `round: <note — cause>`: each an open note; run the round
  ([rounds.md](references/rounds.md)), the targeted re-check, a fresh judge.
  A second `round:` goes under Open.
- `question: <…>`, even after `round:` lines: run the round, ask the user, a
  fresh judge with the answer.
- `evidence owed: <verify|reviewer> — <what>`: a worker on `dev-skills:verify`
  or the reviewer supplies it, then the judge again.
- `land stopped: <…>`: the judge again, once; a second goes to the user
  as a question with land's message; nothing runs until they answer.

## 4. The human gate

Run `CLI plan status <plan> "at the human gate"`, write one page under the plan's
`## Human gate` above `land`'s `### The commits`, and put it in front of the
user, who tries the running app and reads the commits; from a worktree, say
how to run it there. In this order:

1. **Decided without you**: the product calls and the rulings, each with its cost if wrong.
2. **Open**: the judge's report, without the Prediction; findings that
   survived their fix, use cases not reached and what they need; the
   reviewer's Observations, folded.
3. **E2E.** The level, and why if raised. Each Done use case as "do this → see
   that", with its last result and the commit it ran on; mark one touched
   since. The `you check` ones last, with any capture e2e took.
4. **The commits**, which `land` wrote.

The user's word of approval: `CLI plan status <plan> passed`; `dev-skills:finish` runs
on that word, or on the next.

## 5. Notes and rounds

From the first phase on, the user's notes go into
`.ai-workflow/plans/<slug>.notes.md`. Nothing starts on one; no running agent
hears of it. At the gate, give each note a cause from the seven in
[rounds.md](references/rounds.md), propose it, let the user correct it, and
write its source against `<slug>.judge.md`'s Prediction when its line is built. A note that changes
the approach or leaves the plan's territories is proposed as `task`; once the
user confirms, it is listed, not built. A round, on the user's word, builds
every open note or a conflict at `finish` like a phase (reviewer on Sonnet),
then the judge on the round's notes and re-check, as [judge.md](references/judge.md) lists, dispatched through `CLI brief judge --note` like every judge, which lands, and back to the gate.
A fix implementer has no brief: its final message holds its report and rulings, and you record each ruling with `CLI decision --by implementer`.

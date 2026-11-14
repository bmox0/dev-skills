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

Read the plan, its epic, and the project's `AGENTS.md` or `CLAUDE.md`, and the
other plans from `building` to `passed`: a territory this plan shares with one
is named to the user in a line.

Cut the branch named on the plan's Status line from the default branch with
plain git: here on a clean tree; when another plan's branch is checked out
here, in a worktree of its own (`git worktree add ../<repo>-<slug> -b <branch>
<default>`). Write the base SHA and `building` on the Status line; under an
epic, its row gets `building` too. Every phase commits to this branch, in that
one tree. From a worktree, hand every implementer, worker and judge its path; the
plan, its notes and the rest of `.ai-workflow/` stay in the main tree, and the
app runs from the worktree on a port of its own.

Resuming: switch to the branch, or its worktree in `git worktree list`; the
statuses in the plan and `git log <base>..HEAD` say what's done.

## 2. The graph

The plan file is the registry. Mark it `waiting`; start every phase whose
Waits for is done, all at once, each a `dev-skills:implementer` in the
background, handed the plan's path, its phase, and what earlier phases
reported. Mark it `in progress`; when its report comes in, mark it `done` and
start what it unblocks.

- **Messages go through you.** An implementer writes to you for a file outside
  its territory, or a product call the plan does not hold, and carries on
  meanwhile. Grant the file when no running phase owns it, or pass it to the
  phase that does. Answer a product call yourself, from the plan, its epic and
  what the user said, and tell the user in a line; only an irreversible one,
  deleting data, sending outside, production, waits for the user, whose answer
  goes on in their words. Answer with `SendMessage`. No git running: clear a
  stuck `index.lock`.
- **A changed interface** a later phase uses goes into that phase's hand-off.
- **Decided without you**, kept for the human gate page: the product calls you
  answered and the rulings; each with the question as asked and where it came
  from, the answer, why, and the cost if wrong.

## 3. The E2E gate

When every phase is done, before every re-check, and before the review of a
round, run `python3 "<this skill's directory>/../spec/spec.py" write <plan>` (the grammar
is in the `spec` skill's `references/FORMAT.md`) in the plan's branch tree, its worktree when
there is one, never the main tree of another branch, and commit `docs/spec/`
alone with plain git: a script's output, not code. When
nothing changed there is nothing to commit; `git commit` exiting 1 is no
failure. A refusal naming the plan is yours to fix in its `## Spec`; a stale
base, by the Status line's base or `--base $(git merge-base <default> HEAD)`;
one naming `docs/spec/` is a finding.

Then run the gate at the level the plan's Checks names, by
[gate.md](references/gate.md); read it then, not before.

Then a fresh `dev-skills:judge` ([judge.md](references/judge.md)), handed what
it lists for its case, and whether a judge round ran. It returns:

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

Set Status to `at the human gate`, write one page under the plan's
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

The user's word of approval sets Status to `passed`; `dev-skills:finish` runs
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
then the judge on the round's notes and re-check, as [judge.md](references/judge.md) lists, which lands, and back to the gate.

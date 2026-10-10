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
one tree. From a worktree, hand every implementer and worker its path; the
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
- **Decided without you**, kept: the product calls you answered, for the
  human gate, and the rulings, what an implementer decided alone where the
  plan and the code disagreed, for the code review; each with the question as
  asked and where it came from, the answer, why, and the cost if wrong.

## 3. The E2E gate

When every phase is done, run the gate at the level the plan's Checks names:
the full checks, then at once the reviewer and e2e, one list for one new
implementer, a targeted re-check. Read [gate.md](references/gate.md) then, not
before.

## 4. The human gate

Set Status to `at the human gate`, write one page under the plan's
`## Human gate`, above any `### Code review`, and put it in front of the user,
who tries the running app; from a worktree, say how to run it there. The page
is the product's; the code comes after `land`. In this order:

1. **Decided without you**: the product calls, each with its cost if wrong.
2. **Open**: findings that survived their fix, use cases not reached and what
   they need, a round's open notes.
3. **E2E.** The level, and why if raised. Each Done use case as "do this → see
   that", with its last result and the commit it ran on; mark one touched
   since. The `you check` ones last, with any capture e2e took.

Show the notes left for later. The user's `land` approves the page:
`dev-skills:land`.

## 5. Notes and rounds

From the first phase on, the user's notes about the product, and at the
code review about the code, go into `.ai-workflow/plans/<slug>.notes.md`.
Nothing starts on one; no running agent hears of it. A round, on the user's word, builds every open note or a
conflict at `finish` like a phase (reviewer on Sonnet):
[rounds.md](references/rounds.md).

---
name: build
description: Build an approved plan — its branch, implementers run by the plan's graph, the E2E gate, then the human gate. Use when the user says build, with a plan file.
---

# Build

`build <plan>`. The orchestrator runs the graph, relays messages and sorts
findings. It never edits code: implementers write it, workers check it.
Read [RUNTIME.md](../../references/RUNTIME.md) for roles and dispatch.

## 1. The branch

Read the plan, epic and project instructions. On a clean tree, cut
the branch named on the plan's Status line from the default branch with plain
git, and write the base SHA and `building` there; under an epic, its row
gets `building` too. Every phase commits here, in one working
tree; no worktrees.

Resuming: switch to the branch; the statuses in the plan and
`git log <base>..HEAD` say what's done.

## 2. The graph

Mark phases `waiting` in the plan registry. Start phases whose Waits for is
done within available slots, each a fresh implementer handed the plan's path,
its phase, and earlier reports. Mark it `in progress`; on its report,
mark it `done` and start what it unblocks. Others stay `waiting`.

- **Messages go through you.** An implementer writes to you for a file outside
  its territory, or a product call the plan does not hold, and carries on
  meanwhile. Grant the file when no running phase owns it, or pass it to the
  phase that does; put a product call to the user; relay the answer.
  Coordinate Git operations; never delete `index.lock` on assumed inactivity.
- **A changed interface** a later phase uses goes into that phase's hand-off.
- **Rulings**, what an implementer decided alone where the plan and the code
  disagreed, with the cost if wrong, are kept for the human gate.

## 3. The E2E gate

When every phase is done:

1. A worker runs the plan's full checks and returns only what failed. Red is a
   finding.
2. In parallel within slots: a fresh reviewer over `<base>..HEAD` with the plan
   and checks' result, and a worker driving the plan's Done through
   `dev-skills:verify`.
3. One list: red checks, Defects, Conventions, use cases failed or not reached.
   One new implementer fixes all of it.
4. A targeted re-check: a worker's full checks, then a targeted reviewer in
   clean new context over only the fix's commits, and a fresh worker on those
   use cases, in parallel within slots.

One pass, never "until clean". What is still open goes first on the gate page.

## 4. The human gate

Set Status to `at the human gate`, write one page under the plan's
`## Human gate`, and put it in front of the user, who tries the running app:

- **Code, approval 1.** The rulings with their cost if wrong, first. Then a
  walkthrough in 5–10 lines: what changed, where, why. The change itself is
  `git diff <base>..<branch>`.
- **E2E, approval 2.** Each Done use case as "do this → see that", with its
  last result and the commit it ran on; mark one touched since.

Both approvals: set Status to `passed` and show the notes left for later. The
plan waits for the user's `finish`.

## 5. Notes and rounds

From the first phase on, the user's notes about the product go into
`.ai-workflow/plans/<slug>.notes.md`. Nothing starts on one; no running agent
hears of it. A round, on the user's word, builds every open note or a
conflict at `finish` like a phase (targeted reviewer):
[rounds.md](references/rounds.md).

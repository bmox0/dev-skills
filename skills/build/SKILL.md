---
name: build
description: Build an approved plan — its branch, implementers run by the plan's graph, the E2E gate, then the human gate. Use when the user says build, with a plan file.
---

# Build

`build <plan>`. This session is the orchestrator: it runs the graph, relays
messages and sorts findings. It never edits code: implementers write it,
workers check it.

## 1. The branch

Read the plan, its epic, and the project's `CLAUDE.md`. On a clean tree, cut
the branch named on the plan's Status line from the default branch with plain
git, and write the base SHA and `building` there; under an epic, the plan's row
gets `building` too. Every phase commits to this branch, in this one working
tree; no worktrees.

Resuming: switch to the branch; the statuses in the plan and
`git log <base>..HEAD` say what is done.

## 2. The graph

The plan file is the registry. Start every phase whose Waits for is done, all at
once, each a `dev-skills:implementer` in the background, handed the plan's
path, its phase, and what earlier phases reported. Mark it `in progress`; when
its report comes in, mark it `done` and start what it unblocks.

- **Messages go through you.** An implementer writes to you for a file outside
  its territory, or a product call the plan does not hold, and carries on
  meanwhile. Grant the file when no running phase owns it, or pass it to the
  phase that does; put a product call to the user; answer with `SendMessage`.
  No git running: clear a stuck `index.lock`.
- **A changed interface** a later phase uses goes into that phase's hand-off.
- **Rulings**, what an implementer decided alone where the plan and the code
  disagreed, with the cost if wrong, are kept for the human gate.

## 3. The E2E gate

When every phase is done:

1. A worker runs the plan's full checks and returns only what failed. Red is a
   finding.
2. At once: `dev-skills:reviewer` over `<base>..HEAD` with the plan and the
   checks' result, and a worker driving the plan's Done through
   `dev-skills:verify`.
3. One list: red checks, Defects, Conventions, use cases failed or not reached.
   One new implementer fixes all of it.
4. A targeted re-check: a worker's full checks, then at once the reviewer
   over the fix's commits only and those use cases again.

One pass, never "until clean". What is still open goes first on the gate page.

## 4. The human gate

It approves; it does not test. Set Status to `at the human gate`, write one
page into the plan under `## Human gate`, and put it in front of the user:

- **Code, approval 1.** The rulings with their cost if wrong, first. Then a
  walkthrough in 5–10 lines: what changed, where, why. The change itself is
  `git diff <base>..<branch>`, read in git or the editor.
- **E2E, approval 2.** Each Done use case as "do this → see that", with the
  machine's result beside it: passed, a screenshot's path, the command's
  output.

A note about the product opens a new round: a new implementer with the note,
the E2E gate on what it changed, then this page again. A conflict at `finish` is
a round too: an implementer rebases the branch onto the default branch; write
`git merge-base <default> <branch>` into the plan as its base before the gates.

Both approvals: set Status to `passed`. The plan waits for the user's `finish`.

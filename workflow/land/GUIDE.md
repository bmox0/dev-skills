---
name: land
description: Rewrite a plan's branch into the commits a reviewer reads and write their walkthroughs. Use only when the judge passes the work, or to land again after a round; never on the user's word alone.
---

# Land

Read shared `AGENTS.md` and the executor contract:
[SESSIONS.md](../../references/SESSIONS.md).

Run it on the plan's branch, in the tree where it is checked out (the
worktree, when the plan has one). Use the brief's `CLI`; code does the git,
you write the shape.

Land rewrites the history, never the code: it ends on the tree the checks passed.

## 1. The shape

`CLI land draft <plan>` writes `<slug>.shape.toml` beside the plan: one commit
holding every path; landing again, the last shape, with the paths a round
added apart in `unplaced`. Edit it: each commit's paths, message and
walkthrough, and on a re-land the text on what changed since.

Landing again, the first shape stands: a round's change goes into the commit
that holds its files, and a message is redrafted only when the round made it
wrong.

The first time, from the plan's Result, `git log <base>..HEAD` and
`git diff --stat <base>..HEAD`:

- **One commit**, by default.
- **A few**, when the diff holds parts a reviewer reads apart: a core and the
  screens on it, a migration and its use, a refactor and the feature on it.
  Cut by meaning, never by phase or round: those were the work's steps. Each
  part is whole files and builds on the parts before it.

The messages by `runweld commit-work`. The walkthrough is 2-5 lines: what
changed, where, why; the change is `git log -p <base>..<branch>`.

## 2. Land it

`CLI land <plan>`. It refuses and names what is wrong: a dirty tree (the user
commits it to the branch or moves it away; nothing is stashed or dropped) or a
shape that misses, repeats or invents a path. Fix the shape and run it again.

When the tree differs from the backup's, a hook changed it. Read the
difference: keep it with `CLI land accept --note "<why>" <plan>`, or
`CLI land revert <plan>`. The commits before the tip are not checked; the page
says so.

Done when `land` printed the tip. If it stopped, return the stop as it is
printed; a question from code is the user's.

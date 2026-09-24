---
status: proposed
---

# Every worker gets a git worktree — for attribution, not for isolation

The swarm run measured zero merge conflicts and zero attribution violations, so
worktree isolation was never tested against a case where write isolation actually
mattered. That is not an argument for keeping it. The obvious simplification is
to let a whole row write into one tree, since the **write-sets** are disjoint by
precondition anyway.

Two things decide it the other way.

**The cost collapsed.** Isolation used to mean running `bootstrap` in every fresh
tree, which at width ten is ten installs. Under ADR-0001 a phase builds nothing,
tests nothing and lints nothing, so a worker needs a bare checkout and no
dependencies at all.

**The benefit changed.** In one shared tree nothing can attribute a written path
to the worker that wrote it — `git status` names files, not authors — and having
ten agents commit into one index is a race for `index.lock` and half-written
commits. A worktree per worker makes the **attribution check** a single
`git diff --name-only <dispatch base>..<branch>`, and that check is the one
mechanical guarantee the whole model rests on.

## Consequences

- A **Phase Check** that needs an installed binary either runs from the main
  checkout or is a dash.

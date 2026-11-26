---
name: finish
description: Merge a plan's branch — a merge request, or local with --no-ff or --ff-only. Use on authorized instruction after current human-gate acceptance; never on its own.
---

# Finish

The coordinator uses the pinned CLI after current authorized acceptance
([SESSIONS.md](../../references/SESSIONS.md)). Use the approved ending.

## 1. Merge it

`CLI finish <plan>` in the project checkout. It requires current judge, land,
page and acceptance, with `passed` status or a request link.

- A local merge sets Status and the epic's row to `merged`.
- A merge request link becomes Status. On an unknown host, open it and record
  its link with `CLI plan status <plan> LINK`. The human merges it there.
- With the plan at a merge-request link, `CLI finish <plan>` asks the forge; where
  code cannot ask, once the human has seen it merged, `CLI finish --merged <plan>`.
- A refusal names its fix. `merge-refused` is a conflict or a moved target:
  `CLI round start --conflict "<what>" <plan>`, then a new gate, acceptance and finish.

## 2. After

Verify the reported target and commit. Code removes the owned worktree and
its data directory, follows the run's backup policy and keeps the branch and
history. Only unchanged, recorded setup outputs are automatically removed
from the task tree. If other ignored or unsaved files prevent cleanup, move
the named paths to safety and rerun `CLI finish <plan>` for cleanup only.
`CLI finish <plan> --json` and `CLI next --plan <plan>` expose pending cleanup.
Then offer a retro (`runweld retro`); the human decides.

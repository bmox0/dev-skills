---
name: finish
description: Merge a plan's branch — a merge request, or local with --no-ff or --ff-only. Use on authorized instruction after current human-gate acceptance; never on its own.
---

# Finish

The build writer runs finish after current authorized acceptance
([SESSIONS.md](../../references/SESSIONS.md)). If missing, record
`CLI accept <plan> --by <name> --words "<unchanged approval>"`.
Use the approved ending when instructed; do not ask again.
Use the run's installed `runweld` or legacy CLI from its brief.

## 1. Merge it

`CLI finish <plan>`. It ends the run as the run file says, and refuses unless
the current judge, land, page and authorized acceptance match and the plan
is `passed` or a merge-request link. Read the result:

- A local merge sets Status to `merged`; the epic's row follows.
- A merge request is opened and its link becomes Status. On an unknown host, open it and record the link with `CLI plan status <plan>
  "<link>"`. The user merges it in the request's view; the button is the
  approval.
- With the plan at a merge-request link, `CLI finish <plan>` asks the forge; where
  code cannot ask, once the user has seen it merged, `CLI finish --merged <plan>`.
- A refusal names its fix. `merge-refused` is a conflict or a moved target:
  `CLI round start --conflict "<what>" <plan>`, the round in
  `dev-skills:build`, then the gate page and `finish` again on the user's word.

## 2. After

Code removes the owned worktree and its data directory, follows the run's
backup policy and keeps the branch and history. If unsaved files prevent
cleanup, resolve the named paths and rerun `CLI finish <plan>` for cleanup only.
Then offer a retro (`dev-skills:retro`); the user decides.

---
name: finish
description: Merge a plan's branch — a merge request, or local with --no-ff or --ff-only. Use on authorized instruction after current human-gate acceptance; never on its own.
---

# Finish

The existing build writer runs it on the plan’s branch after current authorized
acceptance: [SESSIONS.md](../../references/SESSIONS.md). If acceptance is missing, record
`CLI accept <plan> --by <name> --words "<unchanged approval>"`.
Use the approved run ending when instructed; do not ask it again.
`CLI` is `python3 "<the build skill's directory>/pipeline.py"`.

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

Code removes the worktree and the data directory, deletes the backups the run
file says to or lists them, and keeps the branch. Then offer a retro (`dev-skills:retro`); the user decides.

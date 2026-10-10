---
name: finish
description: Merge a plan's branch at `passed` — a merge request, or local with --no-ff or --ff-only, the message drafted from the plan's Result. Typed by the user.
disable-model-invocation: true
---

# Finish

Run it on the plan's branch, with the plan at `passed` or a merge-request
link (below); any other status goes back to `dev-skills:build`. It merges what
`dev-skills:land` made. Plain git, and `gh` for a merge request.

## 1. Already a merge request

Status a merge-request link: `gh pr view <link> --json state`. Merged: set
Status to `merged`; the epic's row too. Offer a retro (`dev-skills:retro`).
Still open: say so and stop.

## 2. Ask how to end

One message: **a merge request, `--no-ff`, or `--ff-only`?** and the message
for the merge commit or the request's title, drafted from the plan's Result
by `dev-skills:commit-work`. The user's answer approves the message too.

## 3. Merge it

Locally, in the clean tree that has `<default>` checked out
(`git worktree list`; with none, here after `git switch <default>`):

- **`--no-ff`:** `git merge --no-ff <branch>` with the message.
- **`--ff-only`:** `git merge --ff-only <branch>`. Refused, `<default>` moved
  on: offer `--no-ff`, or a rebase as for a conflict.
- **A merge request:** `git push -u origin <branch>`, then
  `gh pr create --base <default>`, the message as its title and the plan's
  `## Human gate` page as its body, with the captures named by where they sit
  on this machine, not linked. The user merges it in the merge request's view;
  the button is the approval.

A conflict: abort the merge. It is a new round in `dev-skills:build`: an
implementer rebases the plan's branch onto the default branch, then the E2E
gate and the human gate see what changed, then `land` and `finish` again.

No push without the user's word; choosing a merge request is that word for
pushing the plan's branch, nothing else. Leave the plan's branch and its
backups in place.

## 4. After

Local: set Status to `merged`. A merge request: set it to the request's
link — step 1 sets `merged` once it is. Under an epic, the plan's row follows.
Merged from a worktree of its own: `git worktree remove <path>`; the branch
stays.
Offer a retro (`dev-skills:retro`); the user decides.

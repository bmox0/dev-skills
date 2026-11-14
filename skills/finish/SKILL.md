---
name: finish
description: Merge a plan's branch — a merge request, or local with --no-ff or --ff-only. Use only on the user's word at the human gate, typed or plain ("ок, в МР", "ок, локально"); never on its own.
---

# Finish

Run it on the plan's branch, with the plan at `passed` or a merge-request
link (below); any other status goes back to `dev-skills:build`. It merges what
`dev-skills:land` made. Plain git, and `gh` for a merge request.

## 1. Already a merge request

Status a merge-request link: `gh pr view <link> --json state`. Merged: set
Status to `merged`; the epic's row too. Offer to delete the backups (step 4), then a
retro (`dev-skills:retro`). Still open: say so and stop.

## 2. Ask how to end

One message: **a merge request, `--no-ff`, or `--ff-only`?** and the message
for the merge commit or the request's title, drafted from the plan's Result
by `dev-skills:commit-work`. Ask only for what the user did not already say. The user's answer approves the message too.

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
implementer rebases the plan's branch onto the default branch, then the judge
(it lands) and the gate page again, and `finish` again on the user's word.

No push without the user's word; choosing a merge request is that word for
pushing the plan's branch, nothing else. Leave the plan's branch in place.

## 4. After

Local: set Status to `merged`. A merge request: set it to the request's
link — step 1 sets `merged` once it is. Under an epic, the plan's row follows.
Merged from a worktree of its own: `git worktree remove <path>`; the branch
stays.
Backups, local merge only (a merge request gets this question in step 1, once
merged): list `git branch --list 'backup/<branch>-*'` and keep the names whose
part after `backup/<branch>-` is all digits. Any: ask one question naming each,
"delete these backups?", and on yes `git branch -D` them (`land` rewrote the
branch, so they are not merged). A no, or any answer but yes, leaves them.
Local: then offer a retro (`dev-skills:retro`); the user decides.

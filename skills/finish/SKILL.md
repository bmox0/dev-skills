---
name: finish
description: Merge a plan's branch at `passed` — a merge request or local, squash or --no-ff, the message from its Result. Only on the user's explicit request.
disable-model-invocation: true
---

# Finish

Run only on the user's explicit request, on the plan's branch at `passed` or
a merge-request link (below); any other status goes back to `dev-skills:build`.
Plain git, and `gh` for a merge request.

## 1. Already a merge request

Status a merge-request link: `gh pr view <link> --json state`. Merged: set
Status to `landed`; the epic's row too. Offer a retro (`dev-skills:retro`).
Still open: say so and stop.

## 2. Choose the outcome

Honor choices and authorization given. Ask only for missing choices:

- **A merge request, or local?**
- **For local: squash, or `--no-ff`?**
- **The message**, drafted from the plan's Result by `dev-skills:commit-work`.

The answer approves the message; existing authorization still applies.

## 3. Land it

On a clean tree:

- **Local, squash:** `git switch <default>`, `git merge --squash <branch>`,
  then `git commit` with the message.
- **Local, `--no-ff`:** `git switch <default>`, then
  `git merge --no-ff <branch>` with the message.
- **A merge request:** `git push -u origin <branch>`, then
  `gh pr create --base <default>`, the message as its title and the plan's
  `## Human gate` page as its body, with the captures named by where they sit
  on this machine, not linked. The user merges it in the merge request's view,
  choosing squash or merge commit there; the button is the approval.

A conflict: abort the merge. It is a new round in `dev-skills:build`: an
implementer rebases the plan's branch onto the default branch, then the E2E
gate and the human gate see what changed, then `finish` again.

No push without the user's word; choosing a merge request is that word for
pushing the plan's branch, nothing else. Leave the plan's branch in place.

## 4. After

Local: set Status to `landed`. A merge request: set it to the request's
link — step 1 lands it once merged. Under an epic, the plan's row follows.
Offer a retro (`dev-skills:retro`); the user decides.

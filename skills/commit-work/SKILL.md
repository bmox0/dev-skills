---
name: commit-work
description: "Create high-quality git commits: review and stage intended changes, split into logical commits, and write clear commit messages (Conventional Commits). Use when the user asks to commit, craft a commit message, stage changes, or split work into multiple commits."
---

# Commit work

Commits that are easy to review and safe to ship: only intended changes, one
logical change each, a short message that says why.

`git-guard` refuses what breaks the rules: blanket staging (`git add .`, `-A`,
`-u`), `git commit -a`, a subject that is not Conventional Commits or is over 72
characters, a body over 300, and attribution trailers.

## Checklist

1. **Inspect** the tree: `git status`, `git diff`, `git diff --stat` when it is
   large.
2. **Decide the boundaries.** Split feature from refactor, formatting from
   logic, dependency bumps from behaviour changes. A file with two kinds of
   change is staged by hunk.
3. **Stage what belongs in the next commit:** paths by name, or `git add -p`.
   Unstage with `git restore --staged <path>`.
4. **Review what will be committed:** `git diff --cached`. No secrets, no debug
   logging, no unrelated churn.
5. **Say it in one or two sentences:** what changed and why. If you cannot, the
   commit is too big; go back to 2.
6. **Write the message** by
   [commit-message-template.md](references/commit-message-template.md):
   `type(scope): summary`, imperative, at most 72 characters; no body unless the
   subject leaves a question open, then at most 300 characters on why and what
   the diff cannot show; simple programming English.
7. **Run the fastest relevant check** before moving on.
8. **Repeat** until the tree holds only what is meant to stay uncommitted.

Report the messages and what each commit is for.

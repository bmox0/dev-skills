---
name: land
description: Rewrite a plan's branch into the commits a reviewer reads and write their walkthroughs. Use only when the judge passes the work, or to land again after a round; never on the user's word alone.
---

# Land

In Codex, read [CODEX.md](../../references/CODEX.md) first.

Run it on the plan's branch, in the tree where it is checked out (the
worktree, when the plan has one). Plain git.

Land rewrites the history, never the code: it ends on the tree the checks passed.

## 1. Before

- `git status --porcelain` is empty. Otherwise stop and show what is there;
  the user commits it to the branch or moves it away. Nothing is stashed or
  dropped.
- `git branch backup/<branch>-<n> HEAD`, the next free `<n>`.

## 2. The shape

Landing again, the first shape stands: a round's change goes into the commit
that holds its files, and a message is redrafted only when the round made it
wrong. Go to 3.

The first time, from the plan's Result, `git log <base>..HEAD` and
`git diff --stat <base>..HEAD`, draft:

- **One commit**, by default.
- **A few**, when the diff holds parts a reviewer reads apart: a core and the
  screens on it, a migration and its use, a refactor and the feature on it.
  Cut by meaning, never by phase or round: those were the work's steps. Each
  part is whole files and builds on the parts before it.

The messages by `dev-skills:commit-work`.

## 3. Rewrite

`git reset --soft <base>`, `git restore --staged :/`, then per commit:
`git add` its paths, `git commit -F` its message. Then
`git diff backup/<branch>-<n> HEAD` is empty. If not,
`git reset --hard backup/<branch>-<n>` and tell the user what differed.

No checks run: the tip is the tree that passed. The commits before it are not
checked; the page says so.

## 4. The commits

Under the plan's `## Human gate`, write
`### The commits · landed <tip> · backup/<branch>-<n>`, replacing an earlier
one; the Status stays as it is. Build writes the rest of the page above it.

1. **Since the last land**, landing again:
   `git range-diff <base> <the last landed tip> HEAD`, the only part to reread.
2. **The commits**, each with its message and a walkthrough in 2–5 lines:
   what changed, where, why. The change is `git log -p <base>..<branch>`.
3. **The E2E gate's fixes**: what Fix 1 and Fix 2 fixed; the backup keeps
   their commits.

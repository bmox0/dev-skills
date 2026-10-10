---
name: land
description: Rewrite a plan's branch, its product approved at the human gate, into the commits a reviewer reads — one, or a few by meaning — on the same tree, then put the code review in front of the user. Typed by the user.
disable-model-invocation: true
---

# Land

In Codex, read [CODEX.md](../../references/CODEX.md) first.

Run it on the plan's branch at `at the human gate`: the user's `land` approves
the product. After a round of code notes it runs again (below). Any other
status goes back to `dev-skills:build`. Plain git.

Land rewrites the history, never the code: it ends on the tree the user tried.

## 1. Before

- `git status --porcelain` is empty. Otherwise stop and show what is there;
  the user commits it to the branch or moves it away. Nothing is stashed or
  dropped.
- `git branch backup/<branch>-<n> HEAD`, the next free `<n>`.

## 2. The shape

Landing again, the approved shape stands: a round's change goes into the
commit that holds its files, and a message is shown again only when the round
made it wrong. Go to 3.

The first time, from the plan's Result, `git log <base>..HEAD` and
`git diff --stat <base>..HEAD`, draft:

- **One commit**, by default.
- **A few**, when the diff holds parts a reviewer reads apart: a core and the
  screens on it, a migration and its use, a refactor and the feature on it.
  Cut by meaning, never by phase or round: those were the work's steps. Each
  part is whole files and builds on the parts before it.

The messages by `dev-skills:commit-work`. One message to the user: each
commit's files in a line, and its message. The answer approves the shape and
the messages.

## 3. Rewrite

`git reset --soft <base>`, `git restore --staged :/`, then per commit:
`git add` its paths, `git commit -F` its message. Then
`git diff backup/<branch>-<n> HEAD` is empty. If not,
`git reset --hard backup/<branch>-<n>` and tell the user what differed.

No checks run: the tip is the tree that passed. The commits before it are not
checked; the review page says so.

## 4. The code review

Set Status to `at code review`. Under the plan's `## Human gate`, write
`### Code review · landed <tip> · backup/<branch>-<n>`, replacing an earlier
one:

1. **Since the last land**, landing again:
   `git range-diff <base> <the last landed tip> HEAD`, the only part to reread.
2. **The commits**, each with its message and a walkthrough in 2–5 lines:
   what changed, where, why. The change is `git log -p <base>..<branch>`.
3. **Rulings**, each with its cost if wrong.
4. **The E2E gate's fixes**: what Fix 1 and Fix 2 fixed; the backup keeps
   their commits.
5. **Folded**: the Conventions and Observations.

Put it in front of the user:

- **Approved**: set Status to `passed`. The plan waits for the user's
  `finish`.
- **Notes about the code** go into the notes file as kind `code`; a round on
  the user's word builds them ([rounds.md](../build/references/rounds.md)),
  then lands again from 1.
- **A note about the product** takes its round back to the human gate.

---
name: finish
description: Land a finished unit on the default branch — squash by meaning, merge --no-ff locally, report. Typed by the user as /finish.
disable-model-invocation: true
---

# Finish

Run it on the unit's branch. `scripts/finish` does the git and refuses any
state it does not recognise; history is never rewritten by hand.

## 1. The range

```bash
scripts/finish preflight [--base <sha>]
```

Pass the base from the brief's Run line when there is a brief. Without one the
script uses the base preflight recorded when it cut the branch, else the fork
from the default branch. It lists the commits and paths, notes a range that
shares commits with an unlanded branch, and refuses a detached HEAD, a dirty
tree, a half-done merge and an empty range.

## 2. Squash by meaning

One commit per meaning. Most units have one; a bug fixed on the way is a second.
Group the range into contiguous runs and write one message file per group,
following `dev-skills:commit-work`: the subject from the brief's Goal or the
todo, Conventional, at most 72 characters; a body only when the subject leaves a
question open, at most 300. Show the drafts to the user.

```bash
scripts/finish squash [--base <sha>] one.txt [--through <last sha of its group> two.txt]...
```

It first records a numbered recovery ref, `refs/dev-skills/recovery/<branch>/<n>`.
Each new commit holds the tree at the end of its group, so the final tree is the
branch's own.

## 3. Merge

```bash
scripts/finish merge [--base <sha>] [--subject <line>]
```

`--no-ff` into the default branch, in whichever checkout holds it, titled with
the unit's last subject or `--subject`; a dirty or half-done tree there is
refused. A unit stacked on work that has landed moves onto the default branch
first; one stacked on work that has not is refused. A conflict aborts: rebase
onto the default branch, resolve, check, finish again. No push unless the user
asks.

## 4. Afterwards

Mark the unit done in the epic's queue, and in the tracker when the
`## Environment` block names one. Offer `dev-skills:retro` once.

End with the merge summary:

- the commits, by meaning;
- the evidence files under `.ai-workflow/verify/<unit>/`;
- the conventions applied after review;
- the open observations.

## Recovery

`scripts/finish recover` lists the attempts and changes nothing;
`scripts/finish recover <n>` resets to one, always named. `scripts/finish ref`
records an attempt before any other rewrite.

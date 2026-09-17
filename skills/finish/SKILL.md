---
name: finish
description: Close out a run — squash it into one commit, put exactly that commit in front of the human for the run's one acceptance, and integrate it. Invoke once both gates are green.
disable-model-invocation: true
---

# Finishing a run

The phases, the fix rounds and the join commits were scaffolding for a run that
is now over. What lands is **one commit**.

**Announce at start:** "Using dev-skills:finish to close out this run."

You make the judgement calls — is it done, what does the message say, what did
the human choose. `scripts/finish` performs the git, and refuses to act on any
state it does not recognise. Do not do this by hand: hand-run history surgery is
exactly what `finish-guard` blocks while a run is open.

## The order

```text
gate A green, gate B green
→ scripts/finish preflight   branch, run base, range, clean tree, no half-done ops
→ a numbered recovery ref on the current HEAD
→ git reset --soft <run base>
→ one commit, its message derived from the plan's Goal
→ tree hashes compared before and after
→ acceptance: the human reads gate B's evidence, then the one diff
→ merge (fast-forward only) / rebase / leave as is
→ cleanup, only after integration is proven, and only our own worktree
```

**The squash comes before the acceptance, and that ordering is the point.** The
human has to approve exactly the object that lands on the base. Approving a range
and then rewriting it into a single commit means what they read and what ships
are two different things, and nobody would notice the day they differ.

`reset --soft` is deliberate. It touches neither the index nor the working tree,
so a conflict is impossible by construction and the equivalence of the trees is
*guaranteed* rather than checked — the script only confirms the hashes match. On
any refusal the state is left staged: nothing is lost and everything is visible.

## 1. Preflight

```bash
scripts/finish preflight
```

It reads `.ai-workflow/run/<plan>/RUN` for the plan and the base, and refuses on
a detached HEAD, on the default branch, on a dirty tree, on a half-finished merge
or rebase, on an empty range, or on a base that is no longer an ancestor of HEAD.
Two markers is also a refusal, naming both.

A refusal is information, not an obstacle. Settle what it names and run it again.

## 2. The message

Derive it from the plan's **Goal**, not from the diff. That text was written
before the code and approved at the plan gate; a message reconstructed from a
diff describes what changed, which the diff already says, instead of what it was
for.

Subject: Conventional Commits, 72 characters max — `commit-guard` requires both
and refuses a longer one. Body: why the run happened, in 300 characters or less,
which `commit-guard` also enforces. A whole run still squashes to a message this
size: the plan holds the detail, and it is on disk. No trailers, no session
links, no co-authors.

Write it to a file and show the draft to the human before committing.

```bash
scripts/finish squash <message file>
```

The script records a recovery ref at the pre-squash HEAD first, and reports it.

**Recovery refs are numbered and never overwritten:**
`refs/dev-skills/recovery/<branch>/<attempt>`. A single ref could not survive a
second squash — the second one would point it at the first squashed commit, and
the pre-squash state the ref existed to reach would become unreachable at exactly
the moment somebody wanted it.

`scripts/finish recover <attempt>` puts everything back, and the attempt is
required. With no argument it lists what exists and changes nothing: a run that
squashed twice has two states worth reaching, and a default is how a recovery
destroys the thing it was called to save.

## 3. Acceptance

**One acceptance, and this is it.** The run has no earlier human gate; both
questions arrive here, in this order:

1. **gate B's evidence** — what it ran on the live system and what it saw, one
   file per approved test case. Behaviour first, because reading the diff first
   turns the whole thing into diff-reading and the behaviour never gets checked.
2. **the one commit** — the message and the whole diff, exactly the unit that
   will land on the base.
3. **one line: `Unresolved advisories: n`**, and the list. These are gate A's
   non-blocking findings. They never bought a fix round, and the human sees the
   count *before* the diff so nothing rides through unnoticed.

This is where the smells that live between phases become visible, and it is worth
naming them rather than gesturing at "what no single phase could see":

- **Duplicated Code** — the same logic shape in two places, built by two
  implementers neither of which saw the other;
- **Shotgun Surgery** — one logical change that had to be made in scattered
  places;
- **Divergent Change** — one module edited for several unrelated reasons.

**On refusal, nothing is repaired in place and nothing is amended.** This is the
common path out — the same one a third unconverged fix round takes — so it is
written once, here:

```text
the human refuses, or a BLOCKER is still open after two rounds
→ back to the orchestrator
→ a remediation round ON TOP OF the squashed commit, ordinary implementer
→ gate A over what was affected
→ gate B over the affected cases
→ dev-skills:finish again, squashing the two commits into one
```

## 4. If the base has moved

```bash
scripts/finish rebase
```

The rule is proportional to the overlap, not "any rebase invalidates everything":

```text
clean rebase, base changes do not touch the run's paths
→ the acceptance stands, integrate

clean rebase, base touched the same paths
→ gate B re-runs the affected cases
→ the acceptance covers only those

rebase with conflicts
→ resolving a conflict is a code change
→ an ordinary remediation round, then the usual path
```

The rebase records its own recovery attempt before it rewrites anything.

The overlap is computed mechanically — `git diff old_base..new_base --name-only`
against the run's paths — with no model judgement. The script prints it.

## 5. Integration

Put the three to the human and wait. The decision is theirs.

1. **Merge into the base** — `scripts/finish integrate --ff-only`. Fast-forward
   only: the run's commit was built on that base, and if it will not fast-forward
   the base has moved and the answer is a rebase, not a merge commit papering
   over it. The script decides that from the graph before touching the main
   checkout, so a failure that is *not* about the base — an untracked file in the
   way, most often — is reported as itself, with git's own words, instead of
   sending you to a rebase that cannot help.
2. **Push and open a pull request** — the worktree stays; review feedback is
   fixed there.
3. **Leave as is** — nothing is deleted, nothing is removed.

Discarding the work is not on the menu. It happens only when the human asks for
it in so many words.

## 6. Afterwards

**Mark the epic entry done.** If the plan names an epic, set that entry's state to
*done* in the plan list. Together with `dev-skills:plan` setting *in progress*, those are
the only two writes to an epic after it exists.

**Close the run:**

```bash
../implement/scripts/run-state end
```

That removes `RUN` from the run's artifact directory. The marker is what arms
`finish-guard`; leave it and the next ordinary piece of work in this repository
meets a block it did not earn. Everything else in that directory stays.

**Cleanup:** `scripts/finish cleanup`, and only after integration is proven. It
removes only a worktree under `.worktrees/` or `worktrees/` — one this workflow
created. A worktree the host environment owns is never touched. On "leave as is",
nothing is removed at all.

**The artifacts stay.** The epic and the plan remain in `.ai-workflow` after
integration. There is no automatic cleanup: deletion is irreversible and disk is
cheap, so deciding what is no longer needed stays with the human.

## Rationalisations

| Excuse | Reality |
|---|---|
| "I'll just squash it by hand, it's three commands" | The script writes a recovery ref and compares tree hashes. By hand you get neither, and `finish-guard` blocks it anyway. |
| "`SQUASH_MSG` is already written" | It is every branch message concatenated with SHAs and dates. It moves the noise out of `git log` and into one commit body. Write the message from the Goal. |
| "The gates passed, the acceptance is a formality" | The gates are models. This is the one check in the whole scheme without one, and it is the only place duplication between phases is visible. |
| "The advisories are noise, leave them out" | They cost the human one line and one reading. Hiding them is how a run's known compromises stop being known. |
| "Just recover, there's only one ref" | Name the attempt. A run that squashed twice has two, and the wrong one is a silent rollback. |
| "It's a small change, merge without fast-forward" | A non-fast-forward means the base moved. Rebase, then integrate. |
| "The PR is up, the worktree is clutter" | Feedback gets fixed in that worktree. It stays until the work lands. |
| "This other worktree looks stale, I'll remove it too" | Only worktrees this workflow created. Everything else belongs to the host. |
| "The plan is finished with, delete it" | Deletion is irreversible and disk is cheap. The human decides when it goes. |

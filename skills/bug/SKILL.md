---
name: bug
description: Reproduce a bug, find its root cause, fix it with a test that pins it, and drive the fix. Use for any bug, failing test or unexpected behaviour, before proposing a fix.
---

# Fixing a bug

```text
fix/<bug> branch → one command that goes red → root cause → fix + pinning test → drive it → commit
```

Reach for this the moment a symptom arrives: the mistake it prevents, guessing
at a fix, happens in the first reply.

**No fix without a root cause.** A symptom fix is a failure, not a partial
success, and it holds hardest when the fix looks obvious.

## 0. A branch

`fix/<bug>` from the default branch, or a worktree when another session works in
this checkout (`preflight fix/<bug>` from `dev-skills:implement`). Say which in
one line.

## 1. One command that goes red

Before any theory, build the loop: one command that shows the bug every time. A
failing test if the project has a test framework, a script if it does not. Run
it and read the whole failure: the message, the stack, the paths. A bug you
cannot reproduce on demand cannot be shown fixed; gather more data instead of
guessing.

## 2. The root cause

- **Check what changed:** recent commits, dependencies, configuration.
- **Trace the bad value backwards** to where it originates, and fix there, not
  where it surfaced: [root-cause-tracing.md](references/root-cause-tracing.md).
- **Across components,** log what enters and leaves each boundary once, then
  investigate only the component where it breaks.
- **Compare with something similar that works,** and list every difference.
- **One hypothesis at a time,** stated as "X is the cause, because Y", tested
  with the smallest change.

Name the root cause, with its evidence, before writing the fix. **After two
failed hypotheses, stop and go back to step 1:** a fix that keeps
uncovering new coupling is the wrong shape, and that is a conversation with the
user, not a third attempt.

## 3. The fix and its pinning test, here

In this context, while the cause is fresh: the red command becomes a test at
the seam where the behaviour is observable, then the fix turns it green. No
workaround, no retry or sleep over a race you have not explained
([condition-based-waiting.md](references/condition-based-waiting.md) when the
race is real). Run the project's checks.

Where more validation belongs once the cause is known:
[defense-in-depth.md](references/defense-in-depth.md).

## 4. Drive it

Run the original reproduction on the running system and say what you saw. If
the bug was visual, capture it. On a project whose rules say the human tests
(a manual simulator run), hand them the scenario.

## 5. Review and commit

A fix with logic beyond one line gets a fresh review of its diff
(`dev-skills:review`). Commit `fix(<scope>): <what is no longer broken>`; the
merge is the user's `/finish`.

## When the cause is a design flaw

If the root cause is a shape the code should not have, and fixing it is more
than this context holds, write a brief with `dev-skills:plan`: the failing test
is its first step.

## When there really is no root cause

If systematic investigation lands on environmental, timing-dependent or external
behaviour, write down what you checked, add the right handling (a retry, a
timeout, a real error message), and make the next occurrence legible. Most "no
root cause" is an investigation that stopped early.

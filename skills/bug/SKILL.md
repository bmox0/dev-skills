---
name: bug
description: Reproduce a bug and pin down its root cause before anything is fixed — a command that goes red, and a cause with evidence. Use for any bug, failing test or unexpected behaviour, before proposing a fix.
---

# Bug

This session is the orchestrator: it judges the evidence and never edits code.
A bug adds reproduction and cause before the plan; phase 1 is the red test.
Read [RUNTIME.md](../../references/RUNTIME.md) before dispatch.

**No fix without a root cause.** A symptom fix is a failure, not a partial
success, and it holds hardest when the fix looks obvious.

## 1. A worker reproduces and traces

Dispatch a worker with the symptom in the user's words and
a slug for it. It leaves the tree as it found it, and returns:

- **A red test and the command that runs it**, red every time: a failing test
  if the project has a test framework, a script if it does not, with the whole
  failure read. It writes the test as a patch, new files included, to
  `.ai-workflow/plans/<slug>.red.patch` (git-ignored, so the tree is as it
  found it), and returns that path and the command.
- **A candidate cause with its evidence**, stated as "X is the cause, because
  Y" and shown by the smallest experiment. It checks what changed lately,
  traces the bad value back to where it starts
  ([root-cause-tracing.md](references/root-cause-tracing.md)), compares with
  something similar that works, and across components logs each boundary once.

A bug it cannot reproduce on demand comes back as what it checked, never as a
guess.

## 2. Accept or send back

Judge the evidence: accept the cause, or send the worker back with what is
missing. After two failed hypotheses, start over from the reproduction: a fix
that keeps uncovering new coupling is the wrong shape. Show the user the red
command and the cause; the stage ends when the user agrees.

## 3. The plan

`dev-skills:plan`, named with the same slug. Name
`.ai-workflow/plans/<slug>.red.patch` and the red command in phase 1: it
applies the patch, sees it red, and commits it with the fix that turns it
green at the root cause. Done drives the original symptom. No workaround, no
retry or sleep over a race nobody has explained
([condition-based-waiting.md](references/condition-based-waiting.md) when the
race is real). Where more validation belongs:
[defense-in-depth.md](references/defense-in-depth.md).

## When there really is no root cause

If the investigation lands on environmental, timing-dependent or external
behaviour, the plan adds the right handling (a retry, a timeout, a real error
message) and makes the next occurrence legible. Most "no root cause" is an
investigation that stopped early.

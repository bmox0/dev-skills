---
name: bug
description: Reproduce a bug and pin down its root cause before anything is fixed — a command that goes red, and a cause with evidence. Use for any bug, failing test or unexpected behaviour, before proposing a fix.
---

# Bug

Read shared `AGENTS.md` and the executor contract:
[SESSIONS.md](../../references/SESSIONS.md).

Start a task with `--bug`, then enter reproduction with `runweld bug start`.
Use the `next` command for the worktree, setup preview and preparation command.
Reproduce on the registered base. This session judges evidence, not code.

## 1. A worker reproduces and traces

Dispatch a worker, a secondary subagent, with the symptom in the human's words and
its [task paths](../../references/WORKFLOW-PATHS.md). It leaves the tree as it found it and returns:

- **A red test and the command that runs it**, red every time: a failing test
  if the project has a test framework, a script if it does not, with the whole
  failure read. It writes the test as a patch, new files included, to
  the task's ignored artifacts as `<slug>.red.patch`, and returns its path and command.
- **A candidate cause with its evidence**, stated as "X is the cause, because
  Y" and shown by the smallest experiment. It checks what changed lately,
  traces the bad value back to where it starts
  ([root-cause-tracing.md](references/root-cause-tracing.md)), compares with
  something similar that works, and across components logs each boundary once.

A bug it cannot reproduce on demand comes back as what it checked, never as a
guess.

## 2. Accept or send back

Accept the evidenced cause or send back what is missing. After two failed
hypotheses, start over from the reproduction. Show the human the command and
cause. After agreement, record `runweld bug done --result TEXT --command SHELL
--artifact PATH` in the task worktree.

## 3. The plan

`runweld plan`, named with the same slug. Name
the returned red patch and command in phase 1: it
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

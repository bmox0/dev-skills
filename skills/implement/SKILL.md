---
name: implement
description: Build a unit from a brief — its own branch, a green commit per step, then review and verify. Use when a brief is handed over.
---

# Implement

`implement <brief>` builds the brief's steps in order; without a brief, the
todo stands in.

1. **Read first:** the brief, its epic, the project's CLAUDE.md and skills.
2. **Branch:** `scripts/preflight feat/<unit>`; `--from <branch>` to build on
   the last finished unmerged unit; `--worktree` when another session works
   here or the tree holds changes that are not this work.
   Write the base SHA and branch on the Run line.
3. **Each step:** tests with the code, red before green (`dev-skills:tdd`);
   the checks last; drive what changed when you hold the tools; one commit,
   `type(scope): step N: <what became true>`.
4. **Stop a step** for three things only: a product decision the brief and epic
   do not answer; a shared interface that has to change; a destructive or
   expensive action. Park it with the question, carry on with the steps that do
   not depend on it; never build on an assumed answer.
5. **Record** what you decided alone under the brief's `## Corrections`.
6. **Report:** what became true, Corrections, divergences, parked questions,
   the checks and their SHA. A subagent builder stops here.
7. **Then:** `dev-skills:review` over BASE..HEAD in a fresh context. The
   builder fixes Defects and the fix is reviewed again; one still open after two
   rounds goes to the user. Conventions go in one batch. Then
   `dev-skills:verify`.

**Resume:** the brief plus `git log BASE..HEAD`; the first step with no commit
is next. Check it before dispatching again.

**Delegated:** dispatch `dev-skills:builder` with the brief path, the step to
start at, and who answers questions. A parallel group's sides go to two
builders in their own worktrees; the join step follows.

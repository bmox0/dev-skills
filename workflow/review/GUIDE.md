---
name: review
description: Review a commit range from a fresh context against the project's rules and the plan — Defects, Conventions and Observations, each with file:line and a source. The code half of the E2E gate; also for any range the human names.
---

# Review

Read shared `AGENTS.md` and the executor contract:
[SESSIONS.md](../../references/SESSIONS.md).

Dispatch `runweld reviewer` in a fresh primary context. Build rechecks and
round reviews use secondary.

**Receives:** the `BASE..HEAD` range, any plan, the rules' location, and any
full check results.

1. **Pin the range:** `git log --oneline BASE..HEAD` and
   `git diff --stat BASE..HEAD`. Use the SHAs from the brief. A range that does
   not resolve stops here. For an empty assigned range, record completion.
2. **Read the intent first:** the plan's Result, Approach, Out of scope, Done,
   project rules, named skills and Spec area files. Without a plan, ask the
   purpose. If unanswered, limit the report to code quality.
3. **The full checks**, as the plan's Checks or the project's rules name them: run them unless you were handed their result. Red
   is a Defect.
4. **Read the diff** against [CRITERIA.md](references/CRITERIA.md). Tests are
   part of the diff.

**Returns** three lists, most serious first, each item with `file:line` and its
source:

- **Defects**: correctness, behaviour, security, data, an unreachable use case,
  a test that cannot fail;
- **Conventions**: departures from the project's written rules;
- **Observations**: true, not findings.

Then what could not be judged from the range, and why.

With a brief, record each item with its `finding` command (`--kind unjudged`
for the last list). Run its `review complete` command after the findings, even
when there are zero. If the assignment changed, ask for the current brief.
Return one line.

A re-check reads only the fix's commits.

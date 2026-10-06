---
name: review
description: Review a commit range from a fresh context against the project's rules and the plan — Defects, Conventions and Observations, each with file:line and a source. The code half of the E2E gate; also for any range the user names.
---

# Review

Read [RUNTIME.md](../../references/RUNTIME.md). The orchestrator dispatches a
fresh initial reviewer, or a fresh targeted reviewer for fixes and rounds,
and reads its lists. An assigned reviewer follows these steps directly.

**Receives:** the range `BASE..HEAD`, the plan when there is one, where the
applicable project instructions and style skills live, and the full checks'
result when they have just run.

1. **Pin the range:** `git log --oneline BASE..HEAD` and
   `git diff --stat BASE..HEAD`. A range that does not resolve, or is empty,
   stops here.
2. **Read the intent first:** the plan's Result, Approach, Out of scope and
   Done, and the project's rules. Without a plan, ask what the change is for;
   without an answer, say the report judges the code and not whether it is the
   right code.
3. **The full checks**, as the plan's Checks or project Environment names
   them: run them unless you were handed their result. Red is a Defect.
4. **Read the diff** against [CRITERIA.md](references/CRITERIA.md). Tests are
   part of the diff.

**Returns** three lists, most serious first, each item with `file:line` and its
source:

- **Defects**: correctness, behaviour, security, data, an unreachable use case,
  a test that cannot fail;
- **Conventions**: departures from the project's written rules;
- **Observations**: true, not findings.

Then what could not be judged from the range, and why.

One pass, never "until clean": a re-check reads only the fix's commits.

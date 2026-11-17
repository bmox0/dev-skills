---
name: review
description: Review a commit range from a fresh context against the project's rules and the plan — Defects, Conventions and Observations, each with file:line and a source. The code half of the E2E gate; also for any range the user names.
---

# Review

Read shared `AGENTS.md` and the executor contract:
[SESSIONS.md](../../references/SESSIONS.md).

The session that asks for a review dispatches `dev-skills:reviewer`, a fresh
context using primary, and reads its lists; `build` uses secondary for
rechecks and round reviews. Any range works.

**Receives:** the range `BASE..HEAD`, the plan when there is one, where the
project's rules live, and the
full checks' result when they have just run.

1. **Pin the range:** `git log --oneline BASE..HEAD` and
   `git diff --stat BASE..HEAD`. A range that does not resolve, or is empty,
   stops here.
2. **Read the intent first:** the plan's Result, Approach, Out of scope and
   Done, and the project's rules, the skills its phases name among them, and
   the area files in `docs/spec/` that the phases' `Spec:` lines name.
   Without a plan, ask what the change is for;
   without an answer, say the report judges the code and not whether it is the
   right code.
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

Handed a brief, record each item with its `finding` command (`--kind unjudged` for the last list) and return one line.

A re-check reads only the fix's commits.

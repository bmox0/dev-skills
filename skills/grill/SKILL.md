---
name: grill
description: Question an idea with the user until both agree on what is being built, before any plan or code — "let's grill this", "think this through with me", "I'm not sure what we're building". Use when it is unclear what is being built, or the change is hard to undo.
---

# Grill

Read shared `AGENTS.md` and the executor contract:
[SESSIONS.md](../../references/SESSIONS.md).
For runweld, [enter or resume the task](../../references/WORKFLOW-PATHS.md) before the interview.

This session remains the user’s orchestrator: it talks, decides with the user,
and never edits code. Turn the idea into a design you and the user both agree
on, through questions. This interview has no formal approval gate.

Run the interview in [INTERVIEW.md](references/INTERVIEW.md).

## While it runs

- **Facts are yours.** Anything that needs reading across the code goes to a
  worker, a secondary subagent that returns paths, abstractions and what it found.
  Keep asking the questions that do not wait on it.
- **The rules come first.** At the start a second worker, a secondary subagent,
  reads `docs/spec/` (use `CLI spec list`, the area files and `CLI spec show ID`;
  see [FORMAT.md](../spec/references/FORMAT.md)) and returns
  the rules the task touches, each with its reason and any contradiction: with
  the task, between rules, with the code or an ADR. None is a normal answer.
- **Decisions are the user's,** in prose. Put each one to them and wait.
- **What outlives the talk.** A term that settles goes into `CONTEXT.md`, and
  an ADR is offered when one is earned, through `dev-skills:domain-modeling`.
  Nothing is committed unless the user asks.

## The end

The grill ends when the decisions are clear enough to plan.
Then:

1. Offer a prototype in one line, the shape for the user to pick: "A
   prototype? An HTML file, inside the app with real data, or code for the
   logic?" (`dev-skills:prototype`). The user may decline.
2. Write the run file: `dev-skills:run-file`.
3. Write the plan: `dev-skills:plan`, with run and summary approval, then stop.

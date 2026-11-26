---
name: grill
description: Question an idea with the human until both agree on what is being built, before any plan or code — "let's grill this", "think this through with me", "I'm not sure what we're building". Use when it is unclear what is being built, or the change is hard to undo.
---

# Grill

Read shared `AGENTS.md` and the executor contract:
[SESSIONS.md](../../references/SESSIONS.md).
For runweld, [enter or resume the task](../../references/WORKFLOW-PATHS.md) before the interview.

This session remains the human’s orchestrator: it talks, decides with the human,
and never edits code. Turn the idea into a design you and the human both agree
on, through questions. This interview has no formal approval gate.

Enter with `runweld grill start` in the task worktree. Follow **The interview**.

## While it runs

- **Facts are yours.** Anything that needs reading across the code goes to a
  worker, a secondary subagent that returns paths, abstractions and what it found.
  Keep asking the questions that do not wait on it.
- **The rules come first.** At the start a second worker, a secondary subagent,
  reads `docs/spec/` (use `CLI spec list`, the area files and `CLI spec show ID`;
  see [FORMAT.md](../spec/references/FORMAT.md)) and returns
  the rules the task touches, each with its reason and any contradiction: with
  the task, between rules, with the code or an ADR. None is a normal answer.
- **Decisions are the human's,** in prose. Put each one to them and wait.
- **What outlives the talk.** A term that settles goes into `CONTEXT.md`, and
  an ADR is offered when one is earned, through `runweld domain-modeling`.
  Nothing is committed unless the human asks.

## The end

Save decisions and open questions with `runweld grill save`. Resume with
the `next` command. When decisions are settled, record them with
`runweld grill done --result TEXT`. If the work is already clear,
record `runweld grill skip --reason TEXT`.

Follow the next action. Offer a prototype in one line: an HTML file,
inside the app with real data, or code for the logic.

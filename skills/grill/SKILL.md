---
name: grill
description: Question an idea with the user until both agree on what is being built, before any plan or code — "let's grill this", "think this through with me", "I'm not sure what we're building". Use when it is unclear what is being built, or the change is hard to undo.
---

# Grill

In Codex, read [CODEX.md](../../references/CODEX.md) first.

This session is the orchestrator from here: it talks, decides with the user,
and never edits code. Turn the idea into a design you and the user both agree
on, through questions. Nothing is built until the user confirms.

Run the interview in [INTERVIEW.md](references/INTERVIEW.md).

## While it runs

- **Facts are yours.** Anything that needs reading across the code goes to a
  worker, a Sonnet subagent that returns paths, abstractions and what it found.
  Keep asking the questions that do not wait on it.
- **Decisions are the user's,** in prose. Put each one to them and wait.
- **What outlives the talk.** A term that settles goes into `CONTEXT.md`, and
  an ADR is offered when one is earned, through `dev-skills:domain-modeling`.
  Nothing is committed unless the user asks.

## The end

The grill ends when both of you understand each other, and the user says so.
Then:

1. Offer a prototype in one line, the shape for the user to pick: "A
   prototype? An HTML file, inside the app with real data, or code for the
   logic?" (`dev-skills:prototype`). The user may decline.
2. Write the plan: `dev-skills:plan`. The work is one plan; an epic only on the
   user's word.

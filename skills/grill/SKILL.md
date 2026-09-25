---
name: grill
description: Talk an idea through into a shared understanding before anything is built — "let's grill this", "think this through with me", "I'm not sure what we're building". Use when you cannot say what done looks like, or the change is hard to row back from. Ends with a size call — inline, one unit, or many.
---

# Grill

Turn an idea into a design you and the user both agree on, through questions.
No code, and nothing built, until the user confirms the shared understanding.

Run the interview in [INTERVIEW.md](references/INTERVIEW.md).

## While it runs

- **Facts are yours.** Look them up. Anything that needs reading across the
  code goes to a Sonnet scout: a read-only subagent that returns paths,
  abstractions and what it found. Keep asking the questions that do not wait on
  it.
- **Decisions are the user's.** Put each one to them and wait.
- **A visual question gets a prototype** the moment it comes up: how something
  looks, sits or moves. `dev-skills:prototype` draws the variants; point at them
  instead of describing them.
- **What outlives the talk.** When a term settles, add it to `CONTEXT.md`
  through `dev-skills:domain-modeling` as it settles, not at the end. When a
  decision is hard to reverse, surprising without context, and the result of a
  real trade-off, offer an ADR; the user decides. Nothing is committed unless
  the user asks.

## The end: the size call

Once the user confirms, say in one line what size the work is, and why:

- **inline**: it fits this context. Build it here on its own branch, and drive
  the scenarios the grill settled when it is done.
- **one unit**: it will be built in another context or across sessions.
  `dev-skills:plan` writes the brief.
- **many units**: `dev-skills:epic` holds the queue, then one brief per unit.

The user can overrule the call. Most small features are inline.

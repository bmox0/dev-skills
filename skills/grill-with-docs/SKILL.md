---
name: grill-with-docs
description: Use instead of dev-skills:grill when the talking-through will settle vocabulary or a hard-to-reverse decision — "we need to agree what we call this", "let's write this decision down", "grill it and capture the terms". Grills the idea and also captures what outlives the conversation: glossary terms as they settle, and an ADR when one is genuinely earned.
---

# Grilling, with the domain captured

Same interview as `dev-skills:grill`, plus the part that survives the session.

**Announce at start:** "Using dev-skills:grill-with-docs — grilling, and capturing the
domain as we go."

## Run the interview

Read [`dev-skills:grill`'s SKILL.md](../grill/SKILL.md) — and the
[INTERVIEW.md](../grill/references/INTERVIEW.md) it points at — and follow both end to
end: the hard gate, the depth rule, facts against decisions, the decision tree,
the approaches, the design sections, the stop at the end. Those two files are the
single home of that text and this skill does not restate it.

Read them; do not try to invoke `dev-skills:grill`. It is user-invoked, so nothing but
the human typing its name can reach it — which is why the technique is a file.

Everything below happens *during* that interview, not after it.

## What gets captured

Two things surface in a design conversation that are lost the moment it ends.

**A new domain word.** The moment the two of you settle on a term for a thing — a
state, an actor, an event, a boundary — that word belongs in the glossary, not
only in this transcript. Add it to `CONTEXT.md` through `dev-skills:domain-modeling`,
**as it settles**, not at the end: a term recorded three topics later has already
lost the discussion that sharpened it.

`CONTEXT.md` is a glossary and nothing else. No implementation detail, no
decisions, no scratch notes.

**A hard-to-reverse decision.** Offer an ADR only when **all three** are true:

1. **Hard to reverse** — changing your mind later costs something real.
2. **Surprising without context** — a future reader will ask why it was done this
   way.
3. **The result of a real trade-off** — there were genuine alternatives and one
   was chosen for stated reasons.

Miss any one and there is no ADR. When all three hold, name the decision, say why
it qualifies, and **offer**. Writing it is the human's call.

An ADR written on the model's own judgement is how a repository fills with
documents nobody chose — and then with the next one explaining that the last is
stale, until no agent can tell which document describes the system.

## Committing

**Neither the glossary nor an ADR is committed unless the human asks.** Recording
a decision is theirs to authorise, and so is putting it in the history.

## Why this is a separate skill

`dev-skills:grill` produces alignment and no artifact. This one produces a durable
artifact. That difference in what comes out the other end is the only reason two
skills exist rather than one, which is why `dev-skills:domain-modeling` may fire inside
this skill and must not fire inside bare `dev-skills:grill`. Let it fire there and the
bare grill starts writing `CONTEXT.md` on its own and becomes this skill in
practice, and the choice the human made when they typed one name rather than the
other stops meaning anything.

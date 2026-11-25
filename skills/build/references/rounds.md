# Notes and rounds

The build writer records unchanged feedback from the designated contact:
[SESSIONS.md](../../../references/SESSIONS.md).

## The notes file

`<slug>.notes.md`, beside the plan, which code renders from
`CLI note`: each note numbered, in the user's words, with its cause. The
build session proposes the cause; the user corrects it.

Causes: `bug` (the code misses the plan), `off-plan` (it departs from the
plan or a written rule), `proto-mismatch` (it departs from the chosen
prototype), `grill-miss`, `proto-miss` (the grill or the prototype missed what
the user wanted), `feel-ui` (it works as planned but feels or looks wrong),
`code-taste` (the code reads wrong to the user).

- **`task`** is not a cause but a verdict: the note changes the approach or
  leaves the plan's territories. The build session proposes it, the user confirms,
  it is listed and never built: its own task. Anything inside the plan's
  intent is a round now.
- An answer to an implementer's question is not a note: relay it.
- Until a round starts, the user edits or drops notes (`CLI note edit|drop`).
- The source of a note done: `P<n>`, a note the judge predicted
  (`<slug>.judge.md`, read only to mark notes); `missed`, one it did not;
  code sets `judge` on the judge's own notes. `round done` is refused while a
  user's note has none.

## A round

A round needs an instruction to build notes; notes during review are not one. Name what the round takes; the user can
overrule. `CLI round start <plan>` takes every open note, or the judge's notes
when the last verdict ordered a round:

1. A note that changes a rule changes `## Spec` along with Done first. Then a
   new `dev-skills:implementer` handed `CLI brief round --provider <provider> <plan>`; its territory
   is what the notes touch. Its checks, as for any phase.
2. When it has reported, `CLI round done <plan>` writes the rules and runs the
   full checks. Then at once: the reviewer on secondary handed `CLI brief
   reviewer --provider <provider>`, and the blast radius from the diff. Confined to what the notes
   name: tell the user what to look at, since they asked for it. Reaching shared
   code, logic or anything else: a fresh worker drives the Done use cases the
   diff touches through `dev-skills:verify` handed `CLI brief verify --provider <provider> --cases`.
   Give the cases and why; the user can overrule. `CLI status <plan>` names
   pending evidence.
3. Defects and failed use cases go through `CLI fix`, as gate.md; what
   survives is under Open on the gate page. Conventions go to the judge.
4. A new note taken adds its use case to Done. After a round at the human gate:
   the judge, handed `CLI brief judge --provider <provider>`, which lands, and `CLI page` again.

After `CLI round done` for a judge's round, use gate.md's targeted re-check,
then brief the judge again.

Notes given during a round wait under Open.

## A conflict at finish

`finish` refused with `merge-refused`: `CLI round start --conflict "<what>"
<plan>` opens a round with no notes. An implementer rebases the branch onto the
default branch; run `CLI plan base <plan> $(git merge-base <default> <branch>)`
before the gates. A conflict inside `docs/spec/` is not merged by hand: it goes back to the
default branch's state, this plan's record in the archive removed too, and the
build session runs `CLI gate start` once the base is rewritten. If it refuses, two plans disagree about a rule: the user's call.

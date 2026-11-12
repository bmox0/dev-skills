# Notes and rounds

How `dev-skills:build` keeps what the user says, and builds it in rounds.

## The notes file

`.ai-workflow/plans/<slug>.notes.md`, beside the plan. Each note numbered, in
the user's words, with its cause. The session proposes the cause; the user
corrects it.

Causes: `bug` (the code misses the plan), `off-plan` (it departs from the
plan or a written rule), `proto-mismatch` (it departs from the chosen
prototype), `grill-miss`, `proto-miss` (the grill or the prototype missed what
the user wanted), `feel-ui` (it works as planned but feels or looks wrong),
`code-taste` (the code reads wrong to the user).

- **`task`** is not a cause but a verdict: the note changes the approach or
  leaves the plan's territories. The session proposes it, the user confirms,
  it is listed and never built: its own task. Anything inside the plan's
  intent is a round now.
- An answer to an implementer's question is not a note: relay it.
- Until a round starts, the user edits or drops notes; re-read the file before
  a round.
- `<source>` of a note done: `P<n>`, a note the judge predicted
  (`<slug>.judge.md`, read only to mark notes); `missed`, one it did not;
  `judge`, a round the judge ordered. Written when the note's line is
  completed; an open note has none.

```markdown
# Notes: <the plan's title>

## Open
6. <the note> — feel-ui

## Round 1 · `<first sha>..<last sha>`
1. <the note> — bug — P1 — `<sha>` — e2e: Done 2, 5 passed
2. <the note> — feel-ui — missed — `<sha>` — the user looked
3. <the note> — off-plan — judge — `<sha>` — e2e: Done 8, added, passed

## Tasks
4. <the note> — task
```

## A round

The user's word is a request to build the notes; a note given while they are
still trying the app is not one. Name what the round takes; the user can
overrule. Then take every open note; a round the judge ordered takes
only the judge's notes:

1. A new `dev-skills:implementer` with the notes file's path and the numbers
   it takes: it reads the user's words there. Its territory is what they
   touch. Its checks, as for any phase.
2. At once: the reviewer on Sonnet over the round's commits, and the blast
   radius from the diff. Confined to what the notes name: tell the user what
   to look at, since they asked for it. Reaching shared code, logic or
   anything else: a fresh worker drives the Done use cases the diff touches
   through `dev-skills:verify`, since nobody asked to look there. Say which,
   and why, in one line; the user can overrule.
3. Defects and failed use cases become open notes, under Open on the gate
   page; Conventions go to the judge.
4. Each note moves under its round with its commit and its check; a new one
   taken adds its use case to Done. After a round at the human gate: the judge
   on the round's commits ([judge.md](judge.md)), which lands, and the gate page
   again.

A round the judge ordered ends with gate.md's targeted re-check instead of
step 2, then the judge again.

Notes given during a round wait under Open.

## A conflict at finish

An implementer rebases the branch onto the default branch; write
`git merge-base <default> <branch>` into the plan as its base before the
gates.

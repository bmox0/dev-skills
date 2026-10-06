# Notes and rounds

Product notes and rounds in `dev-skills:build`.
Use [RUNTIME.md](../../../references/RUNTIME.md) for dispatch.

## The notes file

`.ai-workflow/plans/<slug>.notes.md`, beside the plan. Each note numbered, in
the user's words, with its kind: bug, polish, text or new.

- **New** is what the plan's Result does not hold. Say so and ask: in a round,
  or after the gate. Often it belongs to the feature and was missed in the
  grill; the user decides either way.
- An answer to an implementer's question is not a note: relay it.
- Until a round starts, the user edits or drops notes, in the chat or in the
  file. The file is the truth: re-read it before a round.

```markdown
# Notes: <the plan's title>

## Open
6. <the note> — polish

## Round 1 · `<first sha>..<last sha>`
1. <the note> — bug — `<sha>` — e2e: Done 2, 5 passed
2. <the note> — text — `<sha>` — the user looked
3. <the note> — new — `<sha>` — e2e: Done 8, added, passed

## After the gate
4. <the note> — new
```

## A round

On the user's word, take every open note:

1. A new implementer with the notes; its territory is what they
   touch. Its checks, as for any phase.
2. In parallel within slots: a targeted reviewer in clean new context over the
   round's commits, and the blast radius from the diff. Confined to what the
   notes name: tell the user what to look at, since they asked for it.
   Reaching shared code, logic or
   anything else: a fresh worker drives the Done use cases the diff touches
   through `dev-skills:verify`, since nobody asked to look there. Say which,
   and why, in one line; the user can overrule.
3. Defects, Conventions and failed use cases become open notes, first on the
   gate page.
4. Each note moves under its round with its commit and its check; a new one
   taken adds its use case to Done. Then the gate page again.

Notes given while a round runs wait under Open for the next one. What is left
under After the gate is not built in this plan: the next grill or plan starts
from it.

## A conflict at finish

An implementer rebases the branch onto the default branch; write
`git merge-base <default> <branch>` into the plan as its base before the
gates.

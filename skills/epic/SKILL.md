---
name: epic
description: Hold a body of work that is more than one unit — the shared decisions, the glossary, and the queue of units with what blocks what. Use when the work splits into several briefs.
---

# Writing an epic

An epic exists when the work is more than one unit. It holds what the units
share and the order they go in. One unit needs no epic: its brief carries it.

Write it to `.ai-workflow/epics/<topic>.md`:

```markdown
# <topic>

## Goal
<what the whole body of work makes possible, in the user's terms>

## Decisions
- <decision> — <the reason>

## Glossary
<terms every unit uses the same way; definitions live in CONTEXT.md when it exists>

## Out of scope
- <what a reader would assume is included and is not>

## Interfaces
<shapes passed between units, verbatim, written once>

## Queue
| # | Unit | Blocked by | State |
|---|---|---|---|
| 1 | Transport and tool registration | — | ready |
| 2 | First tool over the service layer | 1 | — |
| 3 | Call log and access revocation | 1 | — |
```

## Decisions

They bind every unit, and no brief reopens one. A decision that turns up while
planning one unit and binds another moves here from the brief, leaving the
brief's `Epic:` line. Move, never copy: two copies disagree by the third unit.

## The queue

Lines, not files. Each unit fits one context and ends in a state someone can
check. A brief is written for a unit when it is next (`dev-skills:plan`), under
200 lines, with `Epic:` pointing here. `plan` sets a unit *in progress*;
`finish` sets it *done*. The next unblocked unit branches from the last finished
one that has not merged yet.

Units merge or split as planning shows what fits: the queue is corrected, not
defended.

## The tracker

When the project's `## Environment` block in CLAUDE.md has a `Tracker` line,
mirror the queue there: one task per unit, with its blocking relations. Move a
task's status when its unit's state changes here. Progress, briefs and evidence
stay in `.ai-workflow/`.

## An ADR

A decision that is hard to reverse, surprising without context, and the result
of a real trade-off is worth recording. Offer it through
`dev-skills:domain-modeling`; the user decides.

## When the epic arrives late

The second unit often appears after the first brief exists. Create the epic,
register the first brief as unit 1 in its real state, move its shared decisions
here, and put `Epic:` in the brief where they were.

End with the queue in front of the user; the first unblocked unit is next.

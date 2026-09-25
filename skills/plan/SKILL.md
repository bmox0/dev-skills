---
name: plan
description: Write the brief a fresh context builds a unit from — goal, decisions, shape, steps, acceptance. Use when the work will be built outside the context that discussed it, or across sessions.
---

# Writing a brief

A brief carries one unit to a builder who was not in the conversation: a
subagent, a tab, a new session, you tomorrow. Write what that builder cannot
recover from the code and the project's rules, and nothing it can.

Reach for it when the work will leave this context. Work that stays here needs
no brief: the todo and the commits carry it.

## Before writing

- **Settle the decisions first.** A brief records decisions; it does not make
  them. If "done" is still unclear, `dev-skills:grill` first.
- **Under an epic,** read it. Its Decisions bind this unit and are not repeated.
- **Read the code the unit touches,** or send a Sonnet scout to read it and
  return paths, abstractions and seams. A brief written from memory names paths
  that do not exist.
- **A bug found while planning** becomes an early step with its failing test,
  not a note.

## Where it goes

`.ai-workflow/plans/<unit>.md`, where `<unit>` is the branch slug the unit will
be built on (`feat/theme-toggle` → `theme-toggle`). The builder's `preflight`
adds `.ai-workflow` to git's local exclude when nothing ignores it yet.

## The seven sections

```markdown
# <unit title>

## Goal
<One paragraph: what becomes true, for whom, and how anyone can tell.>

## Decisions
- <decision> — <the reason, one clause>
<or, under an epic, a single line instead of this section:>
Epic: .ai-workflow/epics/<epic>.md

## Out of scope
- <what a reader would reasonably assume is included and is not>

## Shape
- **Paths:** <the files and directories this unit touches>
- **Build on:** <existing abstractions, helpers, patterns to use, with paths>
- **Do not introduce:** <new layers, dependencies, patterns this unit must not add>
- **Interfaces:** <verbatim, only where two contexts meet>

## Steps
1. **<what becomes true>** — changes `<paths>`; how: <approach, and the test
   that goes red first>.
2. ...

## Acceptance
1. <starting state> → <action> → <what is seen>
...
Looks: <screen or state> — <compared with what: prototype path or description>

Run: <filled by the builder: base SHA and branch>
```

The builder appends `## Corrections` below Run as it works. Nothing else is
added to a brief after it is handed over.

### Goal

What the user or the system can do after this unit that it could not before,
in terms someone can check. Not the implementation.

### Decisions or Epic

Every decision the builder must not reopen, each with its reason in a clause.
Under an epic, one `Epic:` line replaces the section: the epic's Decisions are
the unit's decisions, and a decision that belongs only to this unit is added to
the epic, not here.

### Out of scope

The things a builder would reasonably do next and must not: the neighbouring
refactor, the second screen, the migration of old data.

### Shape

Where the work sits in the code as it is. Name real paths and real symbols.
Name what to reuse, so the builder does not write a second one. Name what not to
introduce, so it does not add a layer the project does not have.

**Interfaces are written verbatim only where two contexts meet:** a function
another unit will call, a message format two sides of a parallel group
exchange, a file format a later unit reads. Everywhere else, describe the
behaviour and leave the code to the builder.

**A refactor** states its frozen surface: the public names, signatures and
observable behaviour that must not change. Its first step is characterisation:
tests that pin today's behaviour at that surface, green before anything moves.

### Steps

Each step is one commit and leaves the project green. Write three things:

- **what becomes true**, which is also the commit subject after `step N:`;
- **what changes**, as paths;
- **how**, in a sentence or two: the approach, and the test that goes red first
  at the seam where the behaviour is observable.

Order the steps so each one can be built and checked on its own. Put the risky
one early.

**A parallel group** is one sentence: the sides, the paths each side owns (they
do not overlap), and the step that joins them. Anything the two sides exchange
is an interface, written verbatim under Shape.

### Acceptance

About ten scenarios, each one line: a starting state, an action, what is seen.
Each is driven on the running system at verify and gets one evidence file,
`.ai-workflow/verify/<unit>/<n>.md`. Cover the paths a user takes, the edges
they hit, and the failure they see when something is wrong. A scenario nobody
can drive (no screen, no command, no request that reaches it) is rewritten
until someone can, or it moves to a test step.

Then **Looks**: every screen or state whose appearance matters, and what it is
compared with, a prototype path or a short description. Verify checks these on
captures: screenshots, and frames for motion.

### Run

One line, written by the builder when it cuts the branch: the base SHA and the
branch. With the brief, it is how a new builder resumes: `git log BASE..HEAD`
shows which steps have landed.

## Size

Under an epic, a brief stays under 200 lines. A one-feature brief is well
under 3,000 words. If it grows past that, the unit is two units, or the brief is
explaining what the builder could read in the code.

## Handing it over

End by putting three lines to the user, and nothing else:

```text
Decided alone: <the calls you made without asking, one clause each>
Out of scope: <the list, short>
Will be checked: <the acceptance in one sentence, and the looks>
```

Silence is yes. An answer changes the brief before anyone builds from it. When
the brief sits under an epic, set its entry to *in progress* in the epic's
queue.

The build is `dev-skills:implement <brief>`.

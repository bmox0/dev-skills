# Review criteria

What counts as a finding. The reviewer reads this file, and nothing else
defines it.

## The producible-source rule

**A finding cites its source**, or it is not written down. A source is one of:

- the brief or the epic: its Goal, a Decision, the Shape, a step, an Acceptance
  scenario;
- a written project rule: CLAUDE.md, the project's style skills,
  CONTRIBUTING, an ADR, CONTEXT.md for names;
- a check that fails, or a behaviour you can show: the input, the path through
  the code, the wrong result;
- a smell from the list below.

> "I don't like this name" does not pass.
> "CLAUDE.md puts handlers of this kind in `hooks/`; this one is inside the
> component" passes.

A pattern that merely exists in the code is not a rule. What you saw goes under
Observations.

## Defects

Correctness, behaviour, security, data integrity, an Acceptance scenario the
code cannot reach, and a test that cannot fail. Show each one: run what you can,
and give the input and the result.

A test that cannot fail passes with the behaviour it names broken. It asserts on
a mock rather than on behaviour, computes its expectation with the code under
test, or fails only on a crash or a missing selector. A step or scenario the
brief declared with no test and no path to it is a Defect too.

A Defect opens a fix round.

## Conventions

A departure from a written project rule, with the rule cited. The builder
applies them in one batch and lists them; they are not reviewed again. Style
never opens a round.

## Observations

True and worth knowing, but not a finding: outside the range, a smell no rule
names, a design worry, a risk for a later unit. Listed, never counted, never
blocking.

## The smells

Fowler's (*Refactoring*, ch. 3). Each is a judgement call: "possible Feature
Envy", never a violation. The project's rules override them, and anything
tooling enforces is skipped. A smell is a Convention only when a project rule
names it; otherwise it is an Observation.

- **Mysterious Name** — a name that does not say what it does or holds.
- **Primitive Obsession** — a primitive standing in for a domain concept.
- **Data Clumps** — the same few fields keep travelling together.
- **Feature Envy** — a method reaching into another object's data more than its own.
- **Repeated Switches** — the same cascade on the same type recurs.
- **Message Chains** — a long `a.b().c().d()` the caller should not depend on.
- **Middle Man** — a unit that mostly delegates onward.
- **Refused Bequest** — a subclass ignoring most of what it inherits.
- **Speculative Generality** — abstraction for a need the brief does not have.
- **Duplicated Code** — the same logic shape in more than one place.
- **Shotgun Surgery** — one logical change forcing scattered edits.
- **Divergent Change** — one module edited for several unrelated reasons.

## Never a finding

- A different order of work, or fewer steps than the brief listed.
- Anything the brief or the epic decided. A decision that looks wrong goes to
  the user as a question, not into the lists.
- A finding an earlier round closed.
- Formatting a tool enforces.
- The author's stated rationale. Judge the code.

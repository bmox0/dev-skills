# Vocabulary

The words the dev-skills skills use, so that a human and a model reading any of
them mean the same thing. A plain reference file, not a skill.

## The work

**Unit.** Whatever fits one context: a todo done inline, or a brief built by one
builder. It lands as its own branch. _Avoid:_ phase, segment, ticket.

**Brief.** The document a unit is built from when it leaves the context that
discussed it: `.ai-workflow/plans/<unit>.md`, written by `plan`, seven sections.
_Avoid:_ plan (for the file), spec, PRD.

**Epic.** The document that holds more than one unit: shared decisions, the
glossary, and the queue of units with what blocks what.

**Run line.** The line after a brief's Acceptance: the base SHA and the branch,
written by the builder when it cuts the branch. With `git log BASE..HEAD` it is
how a unit resumes. _Avoid:_ run marker, ledger.

**Corrections.** What the builder decided alone while building, appended to the
brief under `## Corrections`.

**Acceptance.** About ten scenarios in a brief, each a starting state, an action
and what is seen, then the looks list.

**Evidence.** One file per Acceptance scenario, `.ai-workflow/verify/<unit>/<n>.md`:
actions, expected, seen, captures, verdict. Written by `verify`.

## Acts and seats

**Act.** A verb with a command of its own, usable on anything: `implement`,
`review`, `verify`, `finish`. `implement <brief>` runs build, review and verify
in order; it is not a mode.

**Seat.** Who performs an act: the session, a subagent, a tab or the human. The
seat is chosen by who holds the tools, never fixed by the plugin. `builder` and
`reviewer` ship as agents; the tester is whoever holds the tools; the
orchestrator is the human, or a tab under the user's own `orchestrate` skill.

**Scout.** A read-only Sonnet subagent that looks up facts and returns paths and
findings.

## Review

**Defect.** A finding about correctness, behaviour, security, data, an
unreachable scenario, or a test that cannot fail. It opens a fix round; two
rounds, then the user. _Avoid:_ blocker.

**Convention.** A departure from a written project rule, cited. Applied in one
batch, listed, never reviewed again. _Avoid:_ advisory, nit.

**Observation.** True and worth knowing, but not a finding. Never blocks.

## Retired

These named parts of the old pipeline and are gone: Run (as a state with a
marker), Phase, Moment, Storyboard, Dispatch, Brief-as-script-output, Frozen
Contract, Write-Set, Ledger, Test Writer, Implementer, Gate A, Gate B, Fact and
Decision (as a protocol), PLAN_CONFLICT, Segment, Checkpoint, Spec.

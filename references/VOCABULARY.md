# Vocabulary — the dev-skills pipeline

The domain model for the pipeline itself: the words a plan, a brief, a dispatch,
a report and the two gates use, so a human and a model reading any of them mean
the same thing every artifact writer meant. Every script named here anchors on
the exact strings in the last three sections — get one wrong and a checker that
should refuse a plan accepts it instead.

This is an External Reference: a plain file, no frontmatter, not a skill. Any
skill may point at it.

Skill-authoring vocabulary — **Predictability**, **Model-Invoked**, **Context
Pointer**, and the rest — is a different domain and stays where it is:
[`skills/writing-great-skills/references/GLOSSARY.md`](../skills/writing-great-skills/references/GLOSSARY.md).
This file does not import it.

**Bold terms** in any definition are themselves defined in this file; find them
by their heading.

## The Run

### Run

A single execution of the pipeline, from an approved **plan** through both
gates to one landing commit. Opened by `scripts/run-state begin` when
`dev-skills:implement` starts, closed when `dev-skills:finish` squashes it. Its
artifacts live under `.ai-workflow/run/<plan>/`. One run at a time per tree:
`run-state begin` refuses while a marker already exists.

_Avoid_: session, execution, pass

### Phase

A numbered unit inside a **plan**, and nothing else — `### Phase <n>.` under
`## Phases`, carrying the seven fields (*Becomes true*, *Changes*, *How*, *Do
not touch*, *Frozen for later phases*, *Verification*, *Steps*). The word
collides with conversational use, and the collision is closed by declaration,
not by a rename: in any artifact "phase" is the numbered unit. The stages of a
**run** are named by their skill instead — `grill`, `plan`, `implement`,
`finish` — and "the planning phase" or "the implementation phase" is
conversation; it does not appear in a document.

_Avoid_: step, stage, the planning phase, the implementation phase

### Plan

The file `dev-skills:plan` writes to `.ai-workflow/plans/YYYY-MM-DD-<name>.md`
— the contract a cold, cheap **implementer** builds from, and the ledger the
human reads at acceptance. Carries a header (`Norms:`, `Baseline:`, the goal,
the user stories, the constraints, what is out of scope, what the final gate
proves, the test seams, the paths and existing abstractions, the test cases),
the **phase**s under `## Phases`, a `## Topology` table, and a `## Ledger`.

_Avoid_: epic, design doc, ticket

## The Documents

### Epic

The file `dev-skills:epic` writes to `.ai-workflow/epics/YYYY-MM-DD-<topic>.md`
— the document that holds a body of work too large for one **plan**. Carries
the decisions every plan below it follows and none may reopen, the shared
glossary, the integration invariants no single plan's verification can reach,
and the list of plans with the dependencies between them. Exists only when the
work produces more than one **plan**; most work produces one, and then there is
no epic.

_Avoid_: spec, design doc, ticket, epic doc

### Brief

The slice of the **plan** one **implementer** actually reads: the plan's
header plus the phases in its assigned range, and nothing else. Cut by the
`brief` script; hard-stops on a plan with no `## Phases`. Named by the
**artifact naming convention** below.

_Avoid_: instructions, epic, ticket

### Dispatch

The file that hands one **implementer**, the **test writer**, or a gate its
task: the **brief** path, what already exists (the **frozen contract** and
earlier **report**s), the model to run on, and the report path it must write
to. Derived mechanically by the `dispatch` script, which marks what it cannot
derive with a `<<< FILL: ... >>>` marker. Named by the **artifact naming
convention** below, except a gate's dispatch, which is not derived from a
range.

_Avoid_: brief (not interchangeable with it — a brief is what an implementer
reads about the work, a dispatch is what it is told to do with that brief),
task, ticket

### Report

The file an **implementer**, the **test writer**, or a gate writes back: what
it built or found, its self-check, its divergences, and the checks it ran.
Named by the **artifact naming convention** below.

_Avoid_: summary, log, output

### Moment

A sequence the work puts in front of a person, recorded in a **plan**'s `##
Moments` section between `## User stories` and `## Constraints`. Where a user
story says what the work is for, a moment says what a person sees and does,
and in what order; one moment usually gathers several stories under a single
heading. Read by the planner, the **implementer** building the **phase** that
lands part of it, and **Gate B**, which checks the running system against the
order it recorded.

_Avoid_: flow, interaction, scenario, walkthrough, journey

### Storyboard

The form a **moment** takes on the page: a moment heading followed by at
least two numbered steps, each written in the person's own words rather than
the mechanism's. A `## Moments` section holding a single `—` is a deliberate,
well-formed absence — the planner's assertion that this work puts no new
moment in front of anyone; an absent section is equally well-formed.

_Avoid_: script, mockup, storyline

## The Actors

### Planner

Whoever is running `dev-skills:plan` — human and model together, since the
human approves every **phase** boundary and every parallel grouping before the
plan is final. Decides scope, architecture and phase boundaries; the
**implementer** decides none of that.

_Avoid_: author, planning agent

### Orchestrator

The session running `dev-skills:implement`. Dispatches every **implementer**,
the **test writer**, and both gates; classifies every **fact** and **decision**
it meets; records the **Ledger**. Does not write code and does not review it.

_Avoid_: coordinator, controller, manager

### Implementer

The subagent that builds every **phase** in its **brief**, in order, on the
model the plan's `## Topology` assigns. Commits its own work, unless it is one
side of a parallel group, in which case it edits only its own paths and does
not commit.

_Avoid_: builder, coder, dev

### Test Writer

The subagent that turns the plan's human-approved test cases into executable
tests, before the production code they check exists. Writes tests and nothing
else — no architecture, no product decision — and commits them as their own
commit, before the phases that make them green.

_Avoid_: QA, tester

### Prototyper

The subagent a planner dispatches once a **moment**'s questions are settled
and before **phase**s are laid out, to offer a self-contained HTML drawing of
it — one file per moment, opened directly with no server running. A decline
ends the offer without changing the interview's shape.

_Avoid_: prototype (the existing skill that writes throwaway code into a
project — a different thing), mockup tool

### Gate A

The run's code gate — Opus, on a clean context. Reads the whole `BASE..HEAD`
range against the **plan**, in order: checks, then conformance, then
integrity. Judges whether the code is what the plan asked for, built the way
the project builds things; never whether the running system works.

_Avoid_: code review, static gate

### Gate B

The run's one runtime gate — Opus, on a clean context. Drives the plan's
executable test cases on a live system and writes one evidence file per case.
Judges behaviour, never code quality — that question belongs to gate A.

_Avoid_: e2e gate, runtime review, functional gate

## Contract and Scope

### Frozen Contract

The union of every **phase**'s *Frozen for later phases* field — the names,
signatures and shapes a parallel group's two sides build against without
reading each other's code, and the one thing an ordinary gate finding may not
change. A frozen name, signature or shape that has to change is a
**PLAN_CONFLICT**, never a quiet adapter in the join phase.

_Avoid_: interface, API, contract (bare)

### Write-Set

The paths one **phase** touches — its *Changes* field, one path per bullet. A
parallel group is admissible only when the write-sets of its sides are
disjoint; `scripts/preflight --parallel` checks that mechanically, and
intersecting write-sets stop the group before anything is dispatched.

_Avoid_: touched files, scope (bare), footprint

## Findings

### Blocker

A gate finding that opens a fix round — the only kind that does. Carried
alongside its cited source and the file and line it lives at; orthogonal to
which section of a gate's report it appears under.

_Avoid_: critical, must-fix, error

### Advisory

A gate finding that travels to the human alongside the diff, counted on one
line, and never on its own buys an implementer pass and a gate pass.

_Avoid_: nit, suggestion, minor

### PLAN_CONFLICT

What an actor reports when a **frozen contract**, or a field of its own
**phase**, would have to change to proceed. Not fixed and not dismissed by
anyone downstream of the **plan** — it stops the **run** and goes to the
human, because only the human can amend the plan.

_Avoid_: blocker (a PLAN_CONFLICT is not graded or weighed the way a
**Blocker** is — it stops the run outright), escalation (bare)

## The Interview

### Fact

Something unambiguously established from the working tree, that changes no
**decision** — a path, a symbol name, the signature of an existing internal
API, a fixture's location, an available repository command. An actor meeting
a divergence classifies it as a fact only when settling it needs no judgement;
correcting it is then its own to do, written into the plan, and the run
carries on.

_Avoid_: assumption, detail

### Decision

Everything a **fact** is not — behaviour, acceptance, scope, architecture, a
public interface, data migration, security, dependency order, phase
boundaries. Never settled by an actor on the human's behalf; a decision met
mid-run stops the whole run and goes to the human with options.

_Avoid_: judgement call, choice

## Retired

These words survive only here, as retired entries, so a reader meeting one in
an old document knows it is dead rather than assuming it still means
something.

### Spec

Retired. Named what an **epic** now names, and the `## Spec` heading a **plan**
now spells `## Epic`. Renamed to stop it colliding with OpenSpec and the other
spec-driven frameworks: the document was never a specification of behaviour, it
was always an epic — a body of work split into plans.

_Avoid_: — retired; do not use it in a new artifact

### Segment

Retired. Named a contiguous range of phases assigned to one **implementer**,
before a phase range did that job directly in `## Topology` and in every
artifact name. What replaced it: a **phase** range, named directly — no
intervening word.

_Avoid_: — retired; do not use it in a new artifact

### Checkpoint

Retired. Named a review dispatched between phases, mid-run. What replaced it:
nothing — there are no checkpoint reviews. The two gates read the whole
assembled range once, at the end, and see everything the checkpoints could
plus the cross-phase duplication they structurally could not.

_Avoid_: — retired; do not use it in a new artifact

## Fixed strings

The literal strings the scripts in `skills/implement/scripts/` anchor on —
exactly as later phases must produce and check them:

- `## Phases` — the container heading, on its own line
- `### Phase <n>.` — a phase heading; the number is followed by `.` or
  whitespace
- the seven field headings, verbatim, each bold on its own line:
  `**Becomes true**`, `**Changes**`, `**How**`, `**Do not touch**`,
  `**Frozen for later phases**`, `**Verification**`, `**Steps**`
- `## Topology`, and its table columns, in this order and no others:
  `| Phases | Implementer | Why the boundary is here |`
- `## Ledger`
- `## Moments` — the section heading, on its own line, between `## User
  stories` and `## Constraints`
- a moment heading — `- **M-<n>. <what the person is doing>** · US-<n>[, …]` —
  matches `^- \*\*M-[0-9]+\. ` and carries at least one `US-` reference after a
  `·`
- a moment carries **at least two** numbered steps, each indented two spaces:
  `  1. <step, in the person's own words>`
- `## Moments` holding a single `—` is well-formed and means "no new moment";
  an absent section is equally well-formed

## Artifact naming convention

Every file a script derives from a phase range is `<kind>-<first>-<last>.md` —
`brief-1-3.md`, `dispatch-1-3.md`, `report-1-3.md`. Files not derived from a
range keep their own names: `gate-a-dispatch.md`, `contracts/<range>.md`,
`review-<sha>..<sha>.diff`.

A file derived from a **moment** instead of a phase range is named by its
number: `.ai-workflow/plans/<plan>/prototypes/M-<n>.html` for the drawing, and
`.ai-workflow/run/<plan>/gate-b/M-<n>.md` for gate B's evidence.

## Script names

`brief`, `dispatch`, `plan-check`, all in `skills/implement/scripts/`.

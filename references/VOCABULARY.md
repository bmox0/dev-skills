# Vocabulary

Terms used in Runweld.

## Model profiles

**Primary.** A provider's model and reasoning-effort preset for planning,
coordination, first review and judgment.

**Secondary.** A provider's model and reasoning-effort preset for research,
prototypes, implementation, e2e and repeat reviews.

## Roles

**Human.** The person directing the task and granting consent.

**Orchestrator.** The human or agent assigned to coordinate a run and make
decisions within the authority the human grants.

**Build session.** The session executing an approved plan, communicating with
the human or designated orchestrator.

**Implementer.** A secondary agent in a clean context. It builds
one phase, a list of findings, or a round's notes.

**Worker.** A secondary agent for a side job: facts from the code, a
prototype, e2e. The **spec scout** reads `docs/spec/` at the start of
the grill and returns the rules the task touches, with reasons and contradictions.

**Reviewer.** The `reviewer` agent: primary first, secondary for rechecks.

## The work

**Run file.** `<slug>.run.toml`, written before the plan with
`runweld run-file`: permissions, checks and ending. `approve` validates; `plan approve` records
the human decision and freezes the revision.

**CLI.** `runweld`: keeps each plan's state, renders the plan,
notes, judge file and gate page, runs the checks, holds the caps, lands and
finishes as the run file says. Agents decide; it manages.

**Plan.** The file a change is built from, one screen: Result,
Approach, Out of scope, Phases, Checks, Done, Spec, and the prototype's link. Its
result is a finished feature. `plan review` displays the plan and run together.
Approval of that revision starts nothing. `build start` is separate.

**Phase.** One task in a plan, for one implementer: what to build and why, its
territory, what it waits for, its status.

**Territory.** The directories or files a phase changes. Implementers read anywhere, write only there. Phases whose territories overlap never run side
by side.

**Graph.** Phases and dependencies; ready phases start at once. The **registry** holds phase statuses, `waiting`, `in progress` or `done`, kept through the CLI.

**Ruling.** What an implementer decided alone where the plan and the code
disagreed: what, why, the cost if wrong. The human gate page shows them.

**Checks.** The plan's section naming the project's commands for every phase,
the full commands after all phases, and how e2e drives the system.

**Done.** The plan's use cases, each "do this → see that". The E2E gate drives
them; the human gate shows them with their results. One marked `you check`,
which e2e cannot reach or which is judged by its look alone, is the human's.

**Epic.** Several plans, only on the human's word: their shared decisions and
the order they go in.

## Checks at three levels

**Level 1.** Inside a phase: TDD, linters, typechecks, the project's scripts,
on the phase's own territory while other phases run.

**The E2E gate.** After the last phase, at the level the plan names, small or
normal: the full checks, then a review and e2e over Done at once. Their
findings make one list for one new implementer, then a targeted re-check. Code
runs the checks and holds the caps.

**The judge.** The `judge` agent, primary, after the E2E gate. It finds nothing
itself: it reads the gate's results and decides each Open entry and Convention
(let through, a round with a cause, or a question), writes its prediction of
the human's notes, and runs `land`.

**The human gate.** Acceptance of the result, after the judge, by the human
or designated acceptor within granted authority. The decisions made
without them, the judge's report, the use cases with the machine's results and
the landed commits: the human tries the app and reads the commits, and a
**round**, on their word, builds the open **notes** in the plan's notes file.
Each note carries a **cause** and, once done, its source against the judge's
prediction. `accept --by --words` binds approval to the current page and sets `passed`;
`finish` uses the approved ending when instructed.

## Review

**Defect.** A finding about correctness, behaviour, security, data, an
unreachable use case, or a test that cannot fail. _Avoid:_ blocker.

**Convention.** A departure from a written project rule, cited. Decided by the
judge. _Avoid:_ advisory, nit.

**Observation.** True and worth knowing, but not a finding. Never blocks.

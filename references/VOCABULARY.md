# Vocabulary

The words the dev-skills skills use, so that a human and a model reading any of
them mean the same thing. A plain reference file, not a skill.

## Roles

**Orchestrator.** The model the user started with, from the first pipeline
skill the user enters. It talks, decides with the user, writes the plan, runs
the graph, relays messages and sorts findings. It holds conclusions, not raw
code, and never edits code.

**Implementer.** Sonnet in a clean context, the `implementer` agent. It builds
one phase, a list of findings, or a note from the human gate.

**Worker.** A subagent for a side job: facts from the code, drawing a
prototype, review, e2e.

## The work

**Plan.** The file a change is built from, always written, one screen: Result,
Approach, Out of scope, Phases, Checks, Done, and the prototype's link. Its
result is a finished feature; nothing is deferred.

**Phase.** One task in a plan, for one implementer: what to build and why, its
territory, what it waits for, its status.

**Territory.** The directories or files a phase changes. Its implementer reads
anywhere and writes only there. Phases whose territories overlap never run side
by side.

**Graph.** The phases and what each waits for; every phase whose dependencies
are met starts at once. The plan file is also the **registry**: each phase
carries its status, `waiting`, `in progress` or `done`, kept by the
orchestrator.

**Ruling.** What an implementer decided alone where the plan and the code
disagreed: what, why, the cost if wrong. The human gate reads them first.

**Checks.** The plan's section naming the project's commands for every phase,
the full commands after all phases, and how e2e drives the system.

**Done.** The plan's use cases, each "do this → see that". The E2E gate drives
them; the human gate shows them with the machine's results.

**Epic.** Several plans, only on the user's word: their shared decisions and
the order they go in.

## Checks at three levels

**Level 1.** Inside a phase: TDD, linters, typechecks, the project's scripts,
on the phase's own territory while other phases run.

**The E2E gate.** After the last phase: the full checks, then a review and e2e
over Done at once. Their findings make one list for one new implementer, then a
targeted re-check. One pass, never "until clean".

**The human gate.** One page, two approvals: the code (the branch against its
base, a walkthrough, the rulings) and the e2e (the use cases with the machine's
results). It approves; it does not test. A note about the product opens a new
**round**. Approved, the plan is `passed` and waits for `finish`.

## Review

**Defect.** A finding about correctness, behaviour, security, data, an
unreachable use case, or a test that cannot fail. _Avoid:_ blocker.

**Convention.** A departure from a written project rule, cited. Fixed in the
same pass as the Defects. _Avoid:_ advisory, nit.

**Observation.** True and worth knowing, but not a finding. Never blocks.

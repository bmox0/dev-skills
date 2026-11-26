This is history; the rules that hold now are in `docs/spec/`.

# Plan: Show the next workflow step

## Result

An agent entering or resuming a change can see the route from discussion to finish, its place on that route, who acts next, and the command or decision that moves the work forward. An implementer sees its own phase obligations. The coordinator sees parallel work, missing evidence, and waits for the user.

## Approach

Show eight stages in order: optional grill, optional prototype, plan, build, build verification, judge, human review, finish. Include run and summary approval under planning, the phase graph and its checks under build, and land under the judge. Read progress from the existing plan, run, Git and evidence records. Keep the existing lifecycle statuses and detailed reports.

- At workflow entry, show the route even before a plan exists. Record grill participation during ordinary plan writing and use the existing prototype field. Label unavailable history as unknown. Optional steps create no new approval.
- Use the same progress calculation for explicit CLI status, transition hints and session advice. Show the responsible role and its available actions, including parallel reviewer and E2E assignments. When waiting, say for whom and why. A hint confers no permission to start a build, round, acceptance or finish.
- Distinguish a phase's recorded checks, review completion for a specific range, and E2E results on a specific tree. A finding count alone cannot establish that review finished. Preserve existing reasoned exceptions, targeted rechecks, and the small gate's human checks.

## Out of scope

- Changing Git mutation safeguards, merge strategies, executor presets, host permissions, or release packaging.
- A new orchestrator, automatic worker dispatch, or a separate event log.

## Done and Spec

```text
## Done

1. Enter with no plan, then view a draft with optional steps taken or skipped and a plan with unrecorded stage history → all eight stages are identifiable, optional history is honest, and neither inspection nor consent launches work.
2. Open two independent phases and a dependent phase → the coordinator sees parallel owners and waits, each brief gives its territory, TDD and checks, and a configured check with no reported outcome keeps its phase open. Close the last phase → the output names gate start.
3. Run a normal gate and finish a clean review → status distinguishes pending review from zero findings and names outstanding E2E cases. Retry review completion and submit an old range after a change → current evidence remains accurate.
4. Change the tree after verification, then drive a fix and a targeted recheck → the required cases and reviewer are named, stale evidence cannot silently satisfy the judge, and existing explicit exceptions remain visible. On small, review remains required and the human sees the cases to try.
5. Resume an approved plan and a building plan from their relevant checkouts → CLI and hook agree on the plan, stage, owner and next action. With several plans each has its own path. A session unrelated to any run gets no unsolicited workflow.
6. Drive judge pass, land, human notes, an authorized round, renewed review and acceptance through configured finish → every handoff names the next role or wait, and merged is terminal. Open a fixture merge request → the guide shows the outstanding merge.

## Spec

+ build#workflow-progress — The workflow view shows eight stages, current owners and the next permitted actions or waits
  Why: a fresh coordinator needs to recover the route at any handoff
  Done: 1, 2, 5, 6
+ build#phase-check-outcomes — Completing a phase with configured checks requires a report of their outcomes
  Why: a completed phase is used to release dependent work
  Done: 2
+ build#review-completion — Gate readiness distinguishes completed review of the assigned range and applicable E2E evidence for the current change
  Why: a clean review, missing review and stale check lead to different next steps
  Done: 3, 4
~ hooks#status-at-start — Supported lifecycle hooks deliver current CLI progress for relevant plans across linked worktrees
  Why: a resumed agent needs the same plan and next action it would find from the main checkout
  Done: 5
```

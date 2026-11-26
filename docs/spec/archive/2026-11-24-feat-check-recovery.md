This is history; the rules that hold now are in `docs/spec/`.

# Plan: Guide agents and the human through the workflow

## Result

A fresh coordinator can read the next actions throughout a normal run, hand work to the right roles, and tell when to wait. At human review the user receives a short, usable guide to the landed build in the handoff message. Daily tasks `DT-ih1SGKxmK1BllufZs4AaN` (check recovery) and `DT-UnSCgStGE4ypMtSF9sqik` (acceptance guide and required files) share this plan.

## Approach

Keep one source of next actions for text and JSON. Preserve existing fields, inventory behavior, optional history and historical records. Extend each action with a proposed `kind`: `run` for a fully specified CLI transition, `work` for an assignment that requires judgment, `wait` for a pending actor or process, and `ask` for a missing decision or input. Keep multiple independent assignments visible. The host dispatches workers; the CLI reports what is available. Only `run` carries executable argv, including the actual interpreter, script and plan. Resolve provider-dependent commands from an explicitly supplied provider and its approved snapshot. A hint cannot supply consent or reserve a transition.

Examples of individual JSON actions, from different points in a run:

```json
{"owner":"Reviewer","kind":"work","action":"Review the assigned range and record completion."}
```

```json
{"owner":"Coordinator","kind":"run","action":"Resume the open fix.","argv":["/usr/bin/python3","/work/runweld/workflow/build/pipeline.py","fix","done","/work/runweld/.runweld/workflow/plans/demo.md"]}
```

```json
{"owner":"Coordinator","kind":"wait","action":"Wait for the full checks to finish."}
```

```json
{"owner":"User","kind":"ask","action":"Accept the landed result or return feedback."}
```

The planning summary still approves intent. The coordinator prepares the acceptance guide after judge and land, using the current build, manual Done cases, decisions made during implementation and unresolved findings. The page and handoff message share the same validated text. Mechanically validate coverage, structure and references; the coordinator owns relevance and wording.

Illustrative acceptance message for the VikingRobot cross-tab build (the linked plan summary shows the Russian wording). Open the provided dev URL in two tabs of the same browser profile. Sign in in the first tab → the second opens the platform. Refresh both → both keep the session and the account menu opens. Sign out from either → both return to sign-in. Decision: D3, an indefinitely stalled refresh response, has already been reproduced; accept and defer it or request a fix before acceptance.

## Out of scope

- Automatic worker dispatch, a new daemon or command executor, per-command checkpointing and remote process management.
- Changing authorization, migrating historical records or sending messages from the CLI.

## Done and Spec

```text
## Done

1. Inspect entry, draft, consent, build, verification, judge, human review and finish in a fresh context → text and typed JSON agree, approval boundaries hold, parallel owners are visible, and merged has no actions. Inspect current-checkout and per-plan views; run known argv directly from another directory with spaces in the plan path.
2. Hold a full check, kill only its coordinator, then stop its remaining child → wait while work is alive, ask for the missing fact when ownership is indeterminate, and run the correct gate, fix or round retry once safe, including a fix nested in a round.
3. Execute the same recovery from two fresh sessions → only one replacement suite starts. Interrupt between check completion and transition closure → the matching result is reused and the originating transition closes once.
4. Exercise every required file at its consuming transition, including the pre-build summary → valid files pass; missing, empty, unreadable, invalidly encoded and malformed required inputs name the path and repair without advancing state. Optional absence and historical reads still work.
5. Build a human guide after judge and land for a small and normal gate, including a decision taken mid-build and an open defect → page and message contain identical actionable text, cover manual cases and distinguish the outstanding choice. A new round supersedes the old guide and acceptance.
6. Submit the shipped example, then remove a manual case, duplicate its reference, or leave its expected result empty → the production validator accepts the example, rejects each broken guide at page, and points to the correction. Planning summary approval succeeds without these post-build steps.
7. Read the final guide in the coordinator’s message alone → I can open the result, perform the checks and decide what to accept or defer without asking what to look at — you check

## Spec

+ build#typed-workflow-actions — Workflow actions identify executable commands, role assignments, waits and required input
  Why: a fresh coordinator needs the permitted next steps and parallel owners throughout the run.
  Done: 1
+ build#full-check-recovery — Competing callers recover the originating full check without overlapping work
  Why: a stale status response or a lost coordinator must not launch a duplicate suite.
  Done: 2, 3
+ build#required-transition-files — Each transition validates its required files before changing state
  Why: a coordinator needs the affected path, failure and repair at the point where the file is consumed.
  Done: 4, 6
+ build#human-check-guide — Human review hands over one validated guide to the landed build on the page and in the coordinator’s message
  Why: a person needs concrete checks and outstanding decisions that reflect the result, including choices made during implementation.
  Done: 5, 6, 7
```

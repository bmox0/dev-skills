<h1 align="center">
  <img src="docs/runweld-wordmark.svg" width="280" alt="Runweld">
</h1>

<p align="center"><strong>A deterministic workflow for coding agents, from task to merge.</strong></p>

<p align="center">You describe the change. Runweld tracks who acts next, what they checked and which version you accept.</p>

<p align="center">
  <a href="https://github.com/bmox0/runweld/actions/workflows/ci.yml"><img src="https://github.com/bmox0/runweld/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI on main"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-5c527b" alt="MIT license"></a>
  <img src="https://img.shields.io/badge/python-3.11%2B-3776ab" alt="Python 3.11+">
</p>

<p align="center">
  <a href="#quick-start"><strong>Quick start</strong></a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="#workflow-stages">Workflow stages</a> ·
  <a href="docs/cli.md">CLI reference</a> ·
  <a href="#examples">Examples</a>
</p>

## Quick start

### Install

On macOS or Linux, install the CLI with Bash, Git, curl and Python 3.11+ (`python3`).

```sh
curl -fsSL https://raw.githubusercontent.com/bmox0/runweld/main/install.sh | bash
export PATH="$HOME/.local/bin:$PATH"
```

In your project’s Git checkout (at least one commit), install the agent skill with Node.js and initialize Runweld.

```sh
npx skills add https://github.com/bmox0/runweld/tree/main/runweld
runweld init
```

Choose your models, project checks and merge policy. Commit the generated project configuration and skill files. [Project setup](skills/run-file/references/project-config.md)

### Start a task

Open a fresh coding-agent session in the project and ask:

> Use Runweld to add search to our reports page. Users should be able to find a report by title and see a clear message when nothing matches.

Approve the run settings and plan summary, then ask the agent to build. To pick up the task in a new session, open its worktree and ask **“Continue this task with Runweld.”**

## How it works

You describe a task in your coding agent. Runweld gives it a worktree. While the planner discusses open questions with you, the code researcher traces current behavior and the spec scout checks applicable rules against the request, the code and existing architecture decisions. A question can proceed as soon as the facts it depends on are known.

![Runweld workflow from task intake to acceptance, with parallel build phases and CLI responsibilities at each stage.](docs/workflow-board.png)

[Workflow board source (HTML)](docs/workflow-board.html)

The planner assigns each phase its files, checks and dependencies. The two phases shown can start together when both are ready. Each implementer tests and commits within its own files. As each phase closes, the CLI identifies any phases it unlocks. After the last phase, the coordinator moves on to project checks and independent review.

**Across sessions**, the CLI records approvals, phase commits, check results and verdicts. A fresh coordinator can see which commit the reviewer examined, what evidence is missing and whose decision comes next. Your final acceptance applies to the exact revision you reviewed. [Roles and handoffs](#roles-and-handoffs)

## Workflow stages

Run `runweld workflow` to see the stages. During a task, `runweld status --current` shows the current stage, who owns the next action and what they can do.

[Grill and prototype](#grill-and-prototype) · [Plan and approvals](#plan) · [Build by phase](#build) · [Verification and judge](#build-verification-and-judge) · [Human review and finish](#human-review-and-finish)

### Grill and Prototype

```mermaid
flowchart TD
    task(["Task"]) --> plan["Planner"]:::primary
    plan -->|"Trace behavior"| code["Code researcher"]:::secondary
    plan -->|"Find rules"| scout["Spec scout"]:::secondary
    rules[("Project docs and specs<br/>Glossary and ADRs")]:::cli -.-> scout
    code -->|"Code paths"| grill["Planning discussion"]:::primary
    scout -->|"Rules and conflicts"| grill
    grill -->|"Product choices"| decision["Product decisions"]:::human
    decision -->|"Settled term"| glossary["CONTEXT.md"]
    decision -.->|"Design trade-off"| adr["Proposed ADR"]
    decision -.->|"Try a design"| proto["Prototype worker"]:::secondary
    proto -->|"Chosen variant"| draft(["Draft run and plan"])
    decision -->|"Ready to plan"| draft
    classDef primary fill:#e5eaff,stroke:#596eb0,color:#182951
    classDef secondary fill:#d6f3ee,stroke:#428478,color:#113c36
    classDef cli fill:#e6ebf1,stroke:#667588,color:#1c2b3a
    classDef human fill:#fff0cf,stroke:#a27625,color:#4d3613
```

When a task needs a Grill, the **code researcher** traces the behavior through the repository and brings back file paths, existing interfaces and where the change would fit. The **spec scout** reads the relevant rules in `docs/spec/`, brings back the reason for each, and flags conflicts with the request, the code or an architecture decision record (ADR). For the CSV example, the researcher might find where the page applies its date filter. The scout checks whether the project already defines which rows an export includes. You decide what should happen if the two disagree.

As terms settle, the planner records them in the project glossary, `CONTEXT.md`. When an architectural choice involves a trade-off that would be costly to reverse and hard to understand later, the planner offers to record an ADR. If a design question remains, you can ask a secondary worker for a throwaway prototype before planning. [Grill](skills/grill/SKILL.md) · [Glossary and ADRs](skills/domain-modeling/SKILL.md)

### Plan

```mermaid
flowchart TD
    config[("Project defaults")]:::cli --> run["Task run file"]:::cli
    decisions["Product decisions"] --> plan["Plan draft"]:::primary
    run -->|"Checks and limits"| plan
    plan --> cases["Done cases"]
    plan --> delta["Spec changes"]
    cases -->|"Case numbers"| check{"runweld spec check"}:::cli
    delta --> check
    base[("Base spec")]:::cli --> check
    check -->|"Invalid change"| plan
    check -->|"Valid"| compile["Compile plan"]:::cli
    compile --> approve["Approve run settings"]:::human
    approve -->|"Frozen run"| summary["Approve summary"]:::human
    summary -->|"Approval recorded"| wait(["Await build request"]):::cli
    wait -->|"Explicit start"| coordinator["Build coordinator"]:::primary
    classDef primary fill:#e5eaff,stroke:#596eb0,color:#182951
    classDef cli fill:#e6ebf1,stroke:#667588,color:#1c2b3a
    classDef human fill:#fff0cf,stroke:#a27625,color:#4d3613
```

1. **Set the terms of the run.** The planner starts from the project defaults in the task’s `.run.toml`. You settle the model settings, phase and full-project checks, fixtures or accounts needed for verification, and how the branch will be integrated. [Example run file](skills/run-file/references/example.run.toml)
2. **Write the plan and its spec changes.** Each phase names the files it may change, the existing spec areas it must respect, the checks to run and which phases it depends on. A secondary researcher identifies the relevant code and project instructions. In the plan’s `## Spec`, the planner records lasting rules to add (`+`), change (`~`) or remove (`-`), or writes `none`. The numbered **Done** cases describe an action and the result someone can observe.
3. **Validate, approve and hand off.** The planner runs `runweld spec check` against the base revision. You approve the run settings, then a linked summary of at most 350 words. Its approval covers the plan, spec changes and summary text for that run. If the planner edits an acceptance criterion afterward, `runweld` requires renewed summary approval. Your separate instruction to build starts the handoff. [Example approval summary](skills/plan/references/resume.example.md)

For example, the keyboard-shortcuts plan adds `settings#taken-blocks`. It gives the reason a duplicate binding must be rejected and links the rule to Done case 2. That case tells the verifier to record an occupied shortcut, check that the UI names the conflicting action and confirm that Save is disabled. [Worked plan and spec](skills/plan/references/example.md)

### Build

```mermaid
flowchart TD
    coord["Build coordinator"]:::primary -->|Read task state| ready["Ready phases in the approved graph"]:::cli
    ready -->|Phase brief| a["Phase 1 implementer"]:::secondary
    ready -->|Phase brief| b["Phase 2 implementer"]:::secondary
    a --> reportA["TDD, phase checks,<br/>commits and report"]
    b --> reportB["TDD, phase checks,<br/>commits and report"]
    reportA --> done{"runweld phase done"}:::cli
    reportB --> done
    done -->|Missing evidence| repair["Implementer completes its report"]:::secondary
    repair --> done
    done -->|Dependencies met| ready
    done -->|All phases closed| spec["Apply spec changes"]:::cli
    spec --> gate(["Run full project checks"]):::cli
    classDef primary fill:#e5eaff,stroke:#596eb0,color:#182951
    classDef secondary fill:#d6f3ee,stroke:#428478,color:#113c36
    classDef cli fill:#e6ebf1,stroke:#667588,color:#1c2b3a
```

The coordinator starts a secondary implementer for each phase whose dependencies are met. They share the task worktree and write within their assigned files.

Each implementer follows **test-driven development (TDD)**. They write one test where the behavior is observable, run it to see the expected failure, make it pass, then run neighboring tests and the phase’s configured checks. A test covering a Done case cited by a spec rule carries that rule’s ID. [TDD cycle](skills/tdd/SKILL.md)

Before closing a phase, `runweld phase done` checks the report against Git. The reported commits must be on the task branch after its base and touch only paths assigned or granted to the phase. Those paths must be clean, and the report must give an outcome for each configured check.

### Build verification and Judge

```mermaid
flowchart TD
    gate(["Full project checks"]):::cli --> review["Independent reviewer"]:::primary
    gate -.->|"Small gate"| manual["Manual Done cases"]:::human
    gate -->|"Normal gate"| verify["E2E verifier"]:::secondary
    gate -->|"Check outcomes"| evidence["Gate record"]:::cli
    review -->|"Findings + range"| evidence
    verify -->|"Result + capture"| evidence
    evidence -->|"Failures to fix"| fix["Fresh implementer"]:::secondary
    fix -->|"Fix commits"| recheck["Checks and rechecks"]:::cli
    recheck -->|"Updated evidence"| evidence
    evidence -->|"Gate evidence"| judge["Fresh judge"]:::primary
    judge -.->|"Evidence owed"| assigned["Reviewer or verifier"]
    assigned -->|"Missing result"| evidence
    judge -->|"Pass"| land(["Land checked tree"]):::cli
    classDef human fill:#fff0cf,stroke:#a27625,color:#4d3613
    classDef primary fill:#e5eaff,stroke:#596eb0,color:#182951
    classDef secondary fill:#d6f3ee,stroke:#428478,color:#113c36
    classDef cli fill:#e6ebf1,stroke:#667588,color:#1c2b3a
```

When the phases finish, `runweld` applies the plan’s spec changes to `docs/spec/` in the task branch, commits the updated rules and runs the full project checks. The coordinator then assigns two distinct jobs at a normal gate.

| Subagent | Assignment | Evidence |
| --- | --- | --- |
| **Code reviewer · primary** | Read the diff against the approved plan, project conventions and applicable spec rules. | Findings and an explicit completion record for the commit range, even when the reviewer finds nothing. After a fix, `runweld` uses the recorded coverage to determine which range needs review. |
| **End-to-end verifier · secondary** | In parallel with review, drive the assigned Done cases against the running system through the browser, simulator, HTTP or CLI. | A result for each case at the tested commit, with a capture or command output. A case the environment prevents the worker from reaching records why. |

At a small gate, full checks and the first code review still run. All Done cases go into your manual guide. Failed checks, defects and failed cases go to a fresh implementer on one fix list. The coordinator then runs the checks again and assigns targeted rechecks. [Verification levels and fixes](skills/build/references/gate.md)

A **fresh primary judge** reads the plan, findings and evidence. It can send a missing result back to the reviewer or verifier, request a round of changes, or ask you to resolve a product question. If successive rounds keep producing as many new issues, or a previously fixed check fails again, `runweld` can stop further rounds. The review page shows why the rounds stopped and which findings remain open. When the branch is ready for human review, the judge prepares the commits and writes a walkthrough for each. [Judge](skills/build/references/judge.md)

### Human review and Finish

```mermaid
flowchart TD
    judge["Fresh judge"]:::primary -->|"Pass"| land["runweld land"]:::cli
    land -->|"Commit walkthroughs"| guide["Prepare review guide"]:::primary
    guide -->|"Build + manual cases"| human{"Human review"}:::human
    human -->|"Request a round"| round["Round implementer"]:::secondary
    judge -->|"Order a round"| round
    round -->|"New commits"| check["Recheck round"]:::cli
    check -->|"Current evidence"| judge
    judge -->|"Product question"| answer["Product decision"]:::human
    answer -->|"Answer"| judge
    human -->|"Accept page"| accept["runweld accept"]:::cli
    accept -->|"Finish instruction"| finish{"Merge policy"}:::cli
    finish -->|"ff-only or no-ff"| local(["Local merge"])
    finish -->|"Merge request"| mr(["Open merge request"])
    classDef primary fill:#e5eaff,stroke:#596eb0,color:#182951
    classDef secondary fill:#d6f3ee,stroke:#428478,color:#113c36
    classDef cli fill:#e6ebf1,stroke:#667588,color:#1c2b3a
    classDef human fill:#fff0cf,stroke:#a27625,color:#4d3613
```

The build coordinator sends a guide in your conversation language with the exact worktree, URL or artifact to open. It lists each manual case as an action and expected result, plus any outstanding decision and what you would defer by accepting. For a CSV export, you can try an empty date range and decide whether a hang on exports over 10,000 rows needs a fix before merge. [Example review guide](skills/build/references/example.guide.md)

The page also lists decisions agents recorded during implementation, why they chose each option and what it would cost if they were wrong. You can request a round and receive a new guide after the fixes, rechecks and fresh verdict.

Your acceptance applies to that page and its landed commit. On your instruction, `runweld finish` checks the branch tip, verdict, evidence and acceptance again before merging locally or opening a merge request. If someone adds a commit after you accept, the revised build goes through review and acceptance again.

## Roles and handoffs

Install one entry skill and say **“Use Runweld”** in the agent you already use. The skill runs `runweld help agents` to read the installed workflow. Your agent client runs shell commands and dispatches workers with the model and effort named in their briefs. You can use a native agent session, a separate herdr tab or a manual handoff. Each uses the same CLI, project checks and task state. [Session handoff](references/SESSIONS.md)

The planning session and build coordinator use **primary** for decisions that affect the whole change. **Secondary** workers get a bounded assignment, such as tracing a code path, implementing one phase or rerunning a failed case. A fresh primary model handles the first review and every judge verdict. Project profiles live in `.ds/config.toml`. Inspect one with `runweld executor show --provider NAME`.

```mermaid
flowchart TD
    task(["Task"]) -->|"New task worktree"| planner["Planning session"]:::primary
    planner -->|"Trace code"| code["Code researcher"]:::secondary
    planner -->|"Read rules"| scout["Spec scout"]:::secondary
    planner -->|"Approved build"| coord["Build coordinator"]:::primary
    coord -->|"Ready phases"| implement["Implementers"]:::secondary
    coord -->|"Diff and spec"| review["Code reviewer"]:::primary
    coord -->|"Done cases"| verify["E2E verifier"]:::secondary
    coord -->|"Gate evidence"| judge["Judge"]:::primary
    planner -.->|"Record approvals"| cli["runweld CLI"]:::cli
    coord -.->|"Advance run"| cli
    cli -->|"Save transition"| records[("Task state")]:::cli
    records -.->|"Next action and owner"| coord
    classDef secondary fill:#d6f3ee,stroke:#428478,color:#113c36
    classDef primary fill:#e5eaff,stroke:#596eb0,color:#182951
    classDef cli fill:#e6ebf1,stroke:#667588,color:#1c2b3a
```

### What survives a handoff

`runweld task start` records the branch, worktree and workflow release. When the planner compiles the plan, `runweld` writes a JSON state file beside it under `.ds/workflow/plans/`. Approvals, phase reports, commits, check outcomes, review findings, verdicts and acceptance accumulate against that task. The CLI uses those records to render the review page and issue the next worker’s brief.

If a session closes during a full test run, the next coordinator can ask `runweld` about that run. While its test processes are alive, `runweld` tells the coordinator to wait. Once they stop, it can retry the interrupted check or reuse a completed result from the same cycle for the same commit and check commands. If it cannot determine whether the original processes are still running, it asks for that fact before starting another run.

Run `runweld status --current` in the worktree to see the next action and its owner. For automation, add `--json`. The result distinguishes a command to run, work to assign, a decision to request and a reason to wait. [CLI actions](docs/cli.md#workflow-actions)

## Features

| Feature | What you get |
| --- | --- |
| **Isolated tasks** | Each task has a branch, worktree and artifact directory. A project can also allocate a port and data directory per task. |
| **Versioned product rules** | Each plan identifies the rules it changes. The resulting `docs/spec/` files travel with the code, ready for the next task’s spec scout. |
| **Parallel builds** | The planner assigns files and dependencies to each phase. If two phases claim overlapping paths, `runweld` requires a dependency between them. Independent phases can start together. |
| **Verification follows the diff** | A small gate includes full project checks and code review. If the diff reaches beyond the paths assigned or granted to the phases, `runweld` raises the gate to normal. The coordinator then dispatches a verifier for the applicable end-to-end cases. Generated changes under `docs/spec/` are exempt. |
| **Reviewable commits** | Before reorganizing the working commits, `runweld land` creates a backup branch. It compares the resulting Git tree with the checked tree. If a commit hook changes a file, the judge can restore the backup or keep the difference with a reason that appears on the review page. |
| **Pinned workflow releases** | The project lock selects the engine and instructions for new tasks. An existing run keeps its release when a teammate updates the project. |

## Examples

### Start and resume a task from the terminal

```console
$ runweld task start export-csv
[…]
Tree: /Users/alex/src/reports/.ds/workflow/trees/export-csv
Plan: /Users/alex/src/reports/.ds/workflow/plans/export-csv.md
Artifacts: /Users/alex/src/reports/.ds/workflow/artifacts/export-csv
[…]
Next:
  User and planner — Continue in the task worktree with a grill or plan. [work]
```

Open your coding agent in the printed `Tree` and ask it to plan the export. From the project, use the task list or resume by name.

```sh
runweld status                    # List tasks in the project
runweld task resume export-csv    # Show this task's worktree and next step
```

### Read a plan or review guide

- **Keyboard shortcuts.** Read the summary you would approve, then open the full plan to see why the Settings panel and live rebinding can be built in parallel. [Approval summary](skills/plan/references/resume.example.md) · [Full plan](skills/plan/references/example.md)
- [CSV export review guide](skills/build/references/example.guide.md) — see what to download, what to expect for an empty date range and how an unresolved defect appears for your decision.
- [Project configuration](skills/run-file/references/project-config.md) — initialize from a script and configure per-task setup.
- [CLI reference](docs/cli.md) — update or repair a release, or read the next actions as JSON.

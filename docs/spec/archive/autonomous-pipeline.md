This is history; the rules that hold now are in `docs/spec/`.

# Plan: Run an entire task from the installed CLI

## Result

A fresh agent starts with `runweld next` in a clean checkout or an active task, gets its assignment and completes authorized work. A human can follow the same route from the terminal, make product decisions, approve the plan and accept the result. Each task keeps its plan, configuration and evidence in one dated folder.

## Approach

Use the release workflow, persisted task facts and existing transition checks to compute available actions once. Human-readable output, JSON and post-transition guidance describe those same actions. Reading instructions has no side effects. A transition records its result before printing what comes next. Extra reference material is available through the pinned CLI when needed.

The planner proposed a detailed help example covering first use, the workflow and stage commands. The help and next examples illustrate one possible design. The implementer may improve the structure, wording, examples and presentation if that helps a fresh agent understand the task and act correctly. Help explains when each stage applies, what it consumes, what it produces and which decision opens the next stage. The default next view gives a new agent the task goal, the current stage's purpose, relevant decisions and approvals, and the recorded evidence that explains the available actions. Identify the active assignment, its worktree and artifacts, what is outstanding and the condition for continuing. Include facts when they exist and identify missing inputs. Keep the same information available in JSON.

For a run action supply executable argv and its working directory. For work provide the assignment, role instructions from the pinned release, boundaries, relevant evidence, expected deliverable and reporting command. An ask names the decision, the available choices and their consequences. A wait names the outstanding event, the assignment already responsible, where to find its result and what becomes available when it arrives. Supply conditional reference commands at the point where their material applies.

## Out of scope

- Publishing a CLI release, merging PR #4 into main, adding a hosting service or remote task synchronization.

## Done and Spec

```text
## Done

1. From a clean checkout follow help and next through init twice. Project checks, bootstrap and URL survive, format passes and the second init produces no diff.
2. Create two tasks. Choose explicitly in the main checkout and resume by worktree. Retry across a date boundary. Each task has one dated plan directory holding its artifacts through finish.
3. Resume an interrupted interview with its saved decisions. Exercise taking and skipping optional stages and refusing a required skip. For a bug reproduce it in a fresh tree and validate the plan against its actual base.
4. Review a complete plan and its config, approve once, then start separately. Change a criterion or finish target and see the affected approval become stale. Repeated start preserves the phase, worktree and executor.
5. Use a fresh process to follow a review finding through fix, recheck, judge and human feedback round. Execute the supplied argv in its indicated cwd. Find the brief and reporting command for work. Distinguish a question for the human from waiting on the assigned worker. Text and JSON agree on each action.
6. Accept a landed result once. Verify the agreed local fast-forward and cleanup. Repeat with an unknown ignored file. Preserve it, expose pending cleanup, resolve it, and retry cleanup without a second integration. A changed accepted revision blocks finish.
7. Start on release A, select B for new tasks, resume the first from a fresh session. Commands and roles resolve on this machine to the task's release. A second task uses B.
8. Give a fresh agent only the instruction to run next mid-task. Ask it to explain the goal, what has been decided, what evidence justifies the current action, who owns it and what will unlock the next step. Compare its answers with the saved records and observe it continue from the resulting report or human decision — you check

## Spec

~ distribution#system-cli — Humans and agents can enter with help and resume with next using the installed release
  Why: a new terminal or agent needs a discoverable path through the entire task
  Done: 1, 5, 7, 8
+ distribution#task-artifacts — Each new task keeps its plan and execution records in one dated task directory
  Why: humans can browse runs and retain evidence after the working tree is removed
  Done: 2
+ planning#early-progress — Explicit stage entry, completion and optional skips preserve decisions across sessions
  Why: a coordinator can recover the current work before a plan exists
  Done: 3
~ planning#summary-before-build — A human approves the displayed complete plan and configuration together before a separate build start
  Why: one decision covers the exact work and execution terms presented together
  Done: 4
~ run#required-to-approve — Build requires one current human approval binding the complete plan and run config
  Why: authorization identifies both the work and how it will be executed
  Done: 4
~ run#changes-through-approve — Changes to approved planning content or execution settings identify the stale approval and preserve progress
  Why: the human must see a material change before work proceeds under it
  Done: 4, 6
~ build#start-chosen — Explicit build start after current plan approval starts or resumes the selected execution session
  Why: a human controls launch and a resumed coordinator must find active work
  Done: 4, 8
~ finish#by-run-file — After current human acceptance the coordinator completes and verifies the agreed ending, reporting any remaining cleanup
  Why: humans need to know where the accepted result landed and which resources remain
  Done: 6
```

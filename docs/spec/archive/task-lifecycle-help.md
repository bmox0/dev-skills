This is history; the rules that hold now are in `docs/spec/`.

# Plan: Close Runweld tasks, isolate their routes, and explain the CLI

## Result

An owner can close a task when its goal is met or cancel it when work should stop. A fresh agent can recover that decision and open the evidence. Project configuration selects a release; each run can follow its own route. An agent can use terminal help alone to choose an operation, execute it with the right inputs, and check its result.

## Approach

Keep the task's outcome separate from the stage's own evidence. In local-status-ui, the accepted artifact belongs to Prototype and the current stage is Plan. Closing the task records both facts without synthesizing a build, acceptance of code, or Git integration. The owner explicitly chooses the outcome. Preserve the worktree, evidence, branch and pinned release. Treat duplicate requests for the same outcome consistently and refuse conflicting outcomes. An old writer must not advance closed work through the supported launcher.

- Keep only the lock format and exact release identifier in newly generated project locks for the new release. Continue verifying the installed bundle against its release manifest and support existing v2 projects and registered runs across updates.
- For a concrete per-run customization, let an individual run select whether to take the optional Grill and Prototype stages in its configuration. With no preference, preserve interactive discovery. Use the chosen route consistently in guidance and execution; preserve completed stage history and mandatory approval and verification gates.
- Use the accepted terminal mockup for ordering, examples and depth. Generate both help spellings from the same command definitions. Keep help safe to call without a configured checkout. Teach this style in the existing guide for authors and apply it throughout CLI command groups: identify the action, meaningful defaults and requirements, writes, success verification, and recovery where relevant.

## Out of scope

- Replacing the existing adapters, implementing the dashboard, extending the stage vocabulary or enabling arbitrary executable workflows.
- Closing the real local-status-ui task, publishing a release, or changing the defaults of an existing user project as part of the test.

## Done and Spec

```text
## Done

1. Complete a disposable 7.2.0 task at Plan with an accepted Prototype artifact. A fresh CLI shows completed at Plan, opens the saved prototype, and omits the task from suggested work. History and release pin survive.
2. Cancel a task with a compiled plan and reopen its status. The cancelled outcome and actual stage survive; another closure cannot overwrite it, and a stale workflow command cannot advance it. The branch and evidence remain accessible.
3. Initialize and update a test project. Its new lock contains only format and release, an existing v2 project opens, older runs retain their pinned engine, and an altered package still fails verification.
4. Configure two runs from one project to take different optional stages. Resume each in a fresh process and follow its selected route; compare project config and lock byte for byte before and after. Existing runs with no preference keep working.
5. Read root help outside a project, find a task action, and invoke both help spellings. The text agrees, explains authorization and effects, gives a usable example, and shows how to check the outcome. An unknown command path gives a helpful usage error.
6. Open the bare plan guide, its command help, and help agents for a selected run. Each produces the intended instructions; the root examples and grouped command names correspond to the shipped CLI.

7. Start a GPT task in a project with GPT, Qwen and Claude configured. Inspect the run TOML: it contains exactly the GPT pair. Join the same run as Qwen: only the Qwen pair is added. Resume as either provider: their recorded models and effort are unchanged, Claude is absent, and the project config and other runs are untouched. An existing multi-provider run retains its recorded profiles.

## Spec

+ distribution#task-outcome — The owner can complete or cancel a task at its current stage and inspect the preserved result
  Why: a task can reach its goal before Git integration or stop on its owner's decision
  Done: 1, 2
~ distribution#project-lock — The project lock selects an exact verified release for new work and existing runs retain their release
  Why: release contents already carry their integrity metadata and task changes must stay local
  Done: 3, 4
+ planning#run-route — Each task can customize its optional route independently of the project and other tasks
  Why: selected discovery work depends on the task and must survive a fresh session
  Done: 4
+ distribution#command-help — Root, group and command help let an agent discover an operation, carry it out and verify the result
  Why: a fresh agent needs accurate examples, effects and next steps directly in the terminal
  Done: 5, 6
~ run#executor-presets — Each provider records its own primary and secondary presets when it joins a run and approval freezes the recorded profiles
  Why: the task configuration should list participating providers while preserving their chosen models across sessions
  Done: 7
```

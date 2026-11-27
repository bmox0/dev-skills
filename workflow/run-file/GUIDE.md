---
name: run-file
description: Write the run file a plan is built under — what the run may do, how it is checked and how it ends. Use after a grill and its prototype, before the plan, or when a plan's run file is to change.
---

# Run file

Read shared `AGENTS.md` and the executor contract:
[SESSIONS.md](../../references/SESSIONS.md).

The run records agreed permissions, checks and ending. Use `runweld` as
`CLI`. See [example.run.toml](references/example.run.toml) for the fields.

1. **Locate.** Use the plan path and companion run from
   [task entry](../../references/WORKFLOW-PATHS.md).
2. **Snapshot.** A task starts with the
   [project configuration](references/project-config.md) and locked release.
   For a task override, use e.g. `CLI task start ID --secondary-model MODEL`.
   Inspect assignments with `CLI executor show PLAN`. Keep the recorded
   mandatory commands in `[checks].full` and their sources intact.
3. **Agree the ending.** Read the draft. Record the human's local merge method or
   merge request and target in `[finish]`. Ask once for missing choices and
   task-specific fixtures or accounts. Keep choices already given.
4. **Secrets.** For each new secret, in the step 3 message when an answer
   brings it, ask: written directly, or as `keychain:<service>/<account>`, which
   stays unresolved.
5. **Check.** `CLI run check <plan path>` until it is silent: the file is done.

Before compiling, set `[route]` preferences for `grill` and `prototype`.
`"take"` requires the stage, `"skip"` bypasses an unstarted stage, and
`"ask"` keeps the choice interactive. Omitted keys use the pinned release's
defaults. Discovery records and mandatory gates stay intact.

The planner links this configuration and the complete plan alongside the summary
from `CLI plan review <plan>`. One human approval binds both at the displayed
revision. Approved readers use the frozen snapshot. A material change requires
another review and approval, even if the plan itself did not change.

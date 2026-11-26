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
   Verify the pair with `CLI executor show --provider <provider>`.
3. **Agree the ending.** Read the draft. Record the user's local merge method or
   merge request and target in `[finish]`. Ask once for missing choices and
   task-specific fixtures or accounts. Keep choices already given.
4. **Secrets.** For each new secret, in the step 3 message when an answer
   brings it, ask: written directly, or as `keychain:<service>/<account>`, which
   stays as written.
5. **Check.** `CLI run check <plan path>` until it is silent: the file is done.

Then `dev-skills:plan` validates and asks explicit run approval with
`CLI run approve <plan> --by <name> --words "<unchanged approval>"`, then summary
approval. After approval readers use the frozen snapshot; changing it requires
renewed run and summary consent, not compilation alone.

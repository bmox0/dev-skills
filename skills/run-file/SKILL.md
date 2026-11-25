---
name: run-file
description: Write the run file a plan is built under — what the run may do, how it is checked and how it ends. Use after a grill and its prototype, before the plan, or when a plan's run file is to change.
---

# Run file

Read shared `AGENTS.md` and the executor contract:
[SESSIONS.md](../../references/SESSIONS.md).

The run records agreed permissions, checks and ending. Use `ds` as `CLI` for an
installed workflow, or `python3 "<this skill's directory>/../build/pipeline.py"`
for a legacy plugin run. The keys are in [example.run.toml](references/example.run.toml).

1. **Locate.** For ds, use the plan path and companion run from
   [task entry](../../references/WORKFLOW-PATHS.md). For legacy, choose a
   branch and `.ai-workflow/plans/YYYY-MM-DD-<slug>.md` with branch `/` written `-`.
2. **Snapshot.** A ds task starts with the
   [project configuration](references/project-config.md) and locked release.
   For legacy, `CLI run new <plan path>` copies the latest run or the
   credential-free example with current AGENTS presets. Verify the pair with
   `CLI executor show --provider <provider>`.
3. **Ask once.** Send one message with the copied values (`CLI run show
   <plan path>`). Ask what differs and add `[run]` keys for missing task needs, including
   fixtures and accounts: E2E sets up only these keys. Apply the answers.
4. **Secrets.** For each new secret, in the step 3 message when an answer
   brings it, ask: written directly, or as `keychain:<service>/<account>`, which
   stays as written.
5. **Check.** `CLI run check <plan path>` until it is silent: the file is done.

Then `dev-skills:plan` validates and asks explicit run approval with
`CLI run approve <plan> --by <name> --words "<unchanged approval>"`, then summary
approval. After approval readers use the frozen snapshot; changing it requires
renewed run and summary consent, not compilation alone.

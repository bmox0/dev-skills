# Standalone project configuration

Run `runweld init` at a Git checkout and choose the active provider if it isn't
detected. Supply just its primary and secondary models, optionally with effort.
In a terminal, confirm defaults or enter your own commands. Documented
Environment commands or an executable `scripts/setup` are suggestions only.

For explicit input, see `runweld init --help`. For example:

```sh
runweld init --non-interactive --provider GPT \
  --primary-model MODEL --secondary-model MODEL \
  --phase-check 'scripts/check' --full-check 'scripts/test'
```

Commit `.runweld/config.toml`, `.runweld/runweld.lock` and the generated changes in
`AGENTS.md` and `.gitignore`. A colleague with another provider reruns init
with that provider's pair. Init does not replace existing profiles or settings;
edit `.runweld/config.toml` to change them for future runs. `runweld update --project` changes
the release for new runs. For a previous run, `runweld help agents --plan PLAN`
opens its release's instructions.

Every runweld task uses a dedicated worktree. Planning does not run setup.
Set `[setup].command` to an existing preparation command if needed. It runs
in the task tree and receives `RUNWELD_SOURCE_CHECKOUT`, `RUNWELD_TASK_PATH`, `RUNWELD_PLAN`,
`RUNWELD_WORKFLOW`, `RUNWELD_ARTIFACTS`, and `RUNWELD_PORT` / `RUNWELD_DATA_DIR` when allocated.
Use these output locations to keep the checkout clean. Failures retry in
place. A successful setup is reused for those inputs.

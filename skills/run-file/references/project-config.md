# Standalone project configuration

Run `ds init` at a Git checkout and choose the active provider if it isn't
detected. Supply just its primary and secondary models, optionally with effort.
In a terminal, confirm defaults or enter your own commands. Documented
Environment commands or an executable `scripts/setup` are suggestions only.

For explicit input, see `ds init --help`. For example:

```sh
ds init --non-interactive --provider GPT \
  --primary-model MODEL --secondary-model MODEL \
  --phase-check 'scripts/check' --full-check 'scripts/test'
```

Commit `.ds/config.toml`, `.ds/ds.lock` and the generated changes in
`AGENTS.md` and `.gitignore`. A colleague with another provider reruns init
with that provider's pair. Init does not replace existing profiles or settings;
edit `.ds/config.toml` to change them for future runs. `ds update` changes
the release for new runs. For a previous run, `ds help agents --plan PLAN`
opens its release's instructions.

Every ds task uses a dedicated worktree. Planning does not run setup.
Set `[setup].command` to an existing preparation command if needed. It runs
in the task tree and receives `DS_SOURCE_CHECKOUT`, `DS_TASK_PATH`, `DS_PLAN`,
`DS_WORKFLOW`, `DS_ARTIFACTS`, and `DS_PORT` / `DS_DATA_DIR` when allocated.
Use these output locations to keep the checkout clean. Failures retry in
place. A successful setup is reused for those inputs.

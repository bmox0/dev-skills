# Standalone project configuration

Run `runweld init` in a Git checkout. Supply the active provider's two models
and optional effort. Init previews the `AGENTS.md` Environment defaults.
`**Phase checks.**` and `**Full checks.**` list commands in backticks and override
inferred checks. `**Build.**`, `**Bootstrap.**` and `**Dev URL.**` set separate
defaults. An executable `scripts/setup` is the fallback bootstrap.

Example flags (see `runweld init --help`):

```sh
runweld init --non-interactive --provider GPT \
  --primary-model MODEL --secondary-model MODEL \
  --phase-check 'scripts/check' --full-check 'scripts/test' \
  --build 'npm run build' --bootstrap 'npm ci' --dev-url 'http://localhost:3000'
```

Commit `.runweld/config.toml`, `.runweld/runweld.lock`, `AGENTS.md` and
`.gitignore`. Rerun init to add a provider. Edit the config to change defaults.
`runweld update --project` changes the release for new runs.

Choose the finish method and target in each task before approval. Set
`[route]` only in the companion run file, not in project configuration.
Each new task records the initiating provider's pair. A provider joining
later adds its own pair without updating project defaults.
`[setup].command` runs
in the task tree and receives `RUNWELD_SOURCE_CHECKOUT`, `RUNWELD_TASK_PATH`, `RUNWELD_PLAN`,
`RUNWELD_WORKFLOW`, `RUNWELD_ARTIFACTS`, and `RUNWELD_PORT` / `RUNWELD_DATA_DIR` when allocated.
Use these output locations to keep the checkout clean. Failures retry in
place. A successful setup is reused for those inputs.

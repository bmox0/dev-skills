# Checkout configuration

Run `runweld onboard` in a Git checkout. It previews both executor roles,
project commands and their sources without writing files or running commands.
Ask for missing decisions in chat. Save only confirmed inputs with `--apply`.
Repeat the preview after a partial save.

Personal defaults live in `$XDG_CONFIG_HOME/runweld/config.toml` or
`~/.config/runweld/config.toml`. Each of `[executors.primary]` and
`[executors.secondary]` holds `provider`, `model` and optional `effort`.
Use `--confirm-primary` or `--confirm-secondary` for offered defaults, or
supply role fields, for example:

```sh
runweld onboard --apply --primary-provider GPT --primary-model PRIMARY \
  --secondary-provider Claude --secondary-model SECONDARY --no-setup
```

In `AGENTS.md` under Environment, list commands in backticks. Phase checks
and Full checks override inferred commands. Required checks names the mandatory
ones. CI workflow identifies a workflow file. CI checks names its required
commands when they are not simple `run:` steps. Resolve conflicting lists in
chat and repeat `--required-check COMMAND` for each selected command.

Build, Dev server, Dev URL and Worktree setup describe optional commands.
An executable `scripts/setup` supplies a bootstrap if the project does not
declare one. Use `--setup COMMAND` or `--no-setup` if the preview asks.

Commit `runweld.lock`, `AGENTS.md` and `.gitignore`. Each clone confirms
its own roles and saves them to the ignored `.runweld/config.toml`.
`runweld update --project` changes the release for new tasks.

See [worktree setup](../../../references/WORKFLOW-PATHS.md) for the bootstrap environment.

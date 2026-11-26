# CLI reference

## Install from a checkout

Run `./scripts/install-runweld` from the Runweld checkout and give its
`runweld/` directory to your agent’s skill manager. The default launcher
is `~/.local/bin/runweld`. Use `./scripts/install-runweld --prefix DIR` to choose
another location.

## Update or repair a release

For a project with an existing lock, install the Git revision that produced
its release ID. Set `revision` to that published tag or commit, then run:

```sh
curl -fsSL https://raw.githubusercontent.com/bmox0/runweld/main/install.sh | RUNWELD_REF="$revision" bash
```

To install into a separate prefix, pass `--prefix DIR` via
`bash -s -- --prefix DIR`. The project lock stores the release ID. It does
not fetch source code or select a Git revision for the installer.

To use the newly installed release for new work, run `runweld update` in
the project and commit the updated `.runweld/runweld.lock`. This selects the most
recently installed release for new tasks. Use `runweld update RELEASE` to select
an exact installed ID. Existing versioned runs keep their recorded release.

To repair a missing or damaged release, reinstall the source revision that
produced its exact ID. If you had to use an older installer, rerun your
current installer afterward to restore the shared launcher. Reinstalling
preserves the project lock. Use `runweld help agents --plan "$plan"` to verify
that the original run can read its instructions again.

## Workflow actions

For automation, use `runweld workflow --json` before there is a plan, or
`runweld status --json <plan>` and `runweld status --current --json` during a run. Read
`workflow.actions` on a status result, or `actions` on the entry view. Each
action names its `owner`, has readable `action` text, and supplies a `kind`.

- `run` carries an `argv` array. Run it directly as a process, with each array
  item as a separate argument. The interpreter, script and plan paths are absolute.
- `work` names a `role` and its `assignment`, such as a phase number, review
  range or Done cases. Reuse an existing worker when it owns the assignment.
  For a new worker, use the brief command with the matching assignment and
  dispatch the returned brief through the chosen host.
- `wait` identifies work or authorization to wait for. Read status again when
  it arrives.
- `ask` identifies a decision or missing input. Obtain it from the named owner
  before proceeding.

Pass `--provider NAME` to status for executable brief commands using the
approved executor snapshot. The ordinary `status` inventory keeps its existing
shape. The merged workflow has an empty `actions` array. Guidance is a snapshot
and the CLI still applies each command's own checks.

## Install the legacy native plugin

In Claude Code:

```
/plugin marketplace add bmox0/runweld
/plugin install dev-skills@dev-skills
```

Then restart the session. Installing also brings the agents `implementer`, `reviewer` and `judge`.

In Codex:

```sh
codex plugin marketplace add bmox0/runweld
codex plugin add dev-skills@dev-skills
```

Start a new session and invoke a skill by name, such as `$dev-skills:grill`.
To update, run `codex plugin marketplace upgrade dev-skills`, then
`codex plugin add dev-skills@dev-skills` again.

For Qoder CLI, install from a local checkout and start a new session.

```sh
qodercli plugin install /absolute/path/to/runweld
```

For a single Qoder session, load the checkout with
`qodercli --plugin-dir /absolute/path/to/runweld --add-dir /absolute/path/to/runweld`.
The second flag grants access to the workflow files outside the target project.

The plugins use the shared role instructions in `agents/` and register advisory
hooks for their host. In Codex, trust the hooks after installation and after
each plugin update to receive workflow reminders. [Host adapters](../adapters/README.md)

# CLI reference

## Install from a checkout

Run `./scripts/install-ds` from the dev-skills checkout and give its
`ds-cli-skill/` directory to your agent’s skill manager. The default launcher
is `~/.local/bin/ds`. Use `./scripts/install-ds --prefix DIR` to choose
another location.

## Migrate from the legacy plugin

1. **Install the CLI and the entry skill** using the [installation instructions](../README.md#install). Keep the old engine and
   its files available to any workers still using previously issued commands.
2. **Disable the old plugin for new sessions.** Use the command for your host
   below. If you previously copied individual skills such as `build`, `plan`,
   or `grill` into a personal or project skills directory, disable those
   copies too, or move them outside the host's skill search paths. A plugin
   toggle only controls the skills that the plugin supplies. In Codex you
   can disable a standalone copy by its `SKILL.md` path.
   [Disable local Codex skills](https://learn.chatgpt.com/docs/build-skills#enable-or-disable-local-codex-skills)
3. **Adopt the existing history.** Run `ds init` in the main project checkout
   while the old linked worktrees still exist, then run `ds status`. Check
   that your old plans appear and an active plan shows the expected stage.
   The main checkout's `.ai-workflow/` stays in place. Linked checkout history
   moves under `.ds/workflow/legacy/`, with links at the old paths. Leave
   those links in place. If init reports a collision, inspect the named path,
   move the conflicting item aside, and retry.
4. **Switch new work to the CLI.** Commit the shared project files listed
   in the [quick start](../README.md#quick-start). Start a fresh session
   and say **“Use ds”**. Once outstanding legacy workers have finished,
   you can uninstall the old plugin.

| Host | Disable the old plugin |
|---|---|
| Codex | Start the session with `codex -c 'plugins.dev-skills@dev-skills.enabled=false'`. |
| Claude Code | Start the session with `claude --settings '{"enabledPlugins":{"dev-skills@dev-skills":false}}'`. |
| Antigravity CLI | Run `agy plugin disable dev-skills`, then start a fresh session. Use `agy plugin enable dev-skills` to restore it. |

**Active 7.0.0 runs.** If the approved summary was a relative symlink to a
file outside a linked checkout, a previously issued `pipeline.py build start`
can report `no-summary` after adoption. Run `ds build start` with the **same
plan path and arguments**. The current CLI uses the existing approval.

## Update or repair a release

For a project with an existing lock, install the Git revision that produced
its release ID. Set `revision` to that published tag or commit, then run:

```sh
curl -fsSL https://raw.githubusercontent.com/bmox0/dev-skills/main/install.sh | DS_REF="$revision" bash
```

To install into a separate prefix, pass `--prefix DIR` via
`bash -s -- --prefix DIR`. The project lock stores the release ID. It does
not fetch source code or select a Git revision for the installer.

To use the newly installed release for new work, run `ds update` in
the project and commit the updated `.ds/ds.lock`. This selects the most
recently installed release for new tasks. Use `ds update RELEASE` to select
an exact installed ID. Existing versioned runs keep their recorded release.

To repair a missing or damaged release, reinstall the source revision that
produced its exact ID. If you had to use an older installer, rerun your
current installer afterward to restore the shared launcher. Reinstalling
preserves the project lock. Use `ds help agents --plan "$plan"` to verify
that the original run can read its instructions again.

## Workflow actions

For automation, use `ds workflow --json` before there is a plan, or
`ds status --json <plan>` and `ds status --current --json` during a run. Read
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
/plugin marketplace add bmox0/dev-skills
/plugin install dev-skills@dev-skills
```

Then restart the session. Installing also brings the agents `implementer`, `reviewer` and `judge`.

In Codex:

```sh
codex plugin marketplace add bmox0/dev-skills
codex plugin add dev-skills@dev-skills
```

Start a new session and invoke a skill by name, such as `$dev-skills:grill`.
To update, run `codex plugin marketplace upgrade dev-skills`, then
`codex plugin add dev-skills@dev-skills` again.

For Qoder CLI, install from a local checkout and start a new session.

```sh
qodercli plugin install /absolute/path/to/dev-skills
```

For a single Qoder session, load the checkout with
`qodercli --plugin-dir /absolute/path/to/dev-skills --add-dir /absolute/path/to/dev-skills`.
The second flag grants access to the workflow files outside the target project.

The plugins use the shared role instructions in `agents/` and register advisory
hooks for their host. In Codex, trust the hooks after installation and after
each plugin update to receive workflow reminders. [Host adapters](../adapters/README.md)

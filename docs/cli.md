# CLI reference

## Install from a checkout

Run `./scripts/install-runweld` from the Runweld checkout. The default launcher
is `~/.local/bin/runweld`. Use `./scripts/install-runweld --prefix DIR` to choose
another location.

## Update the CLI

Run `runweld update --cli` from any directory to install the current version
from `main` into the same prefix as the CLI you invoked. Existing project locks
and running tasks keep their selected builds. To install directly:

```sh
curl -fsSL https://raw.githubusercontent.com/bmox0/runweld/main/install.sh | bash
```

## Update a project

Run `runweld update --project` in an initialized checkout to select the installed
default for new tasks. Commit `.runweld/runweld.lock` to share the selection.
The TOML lock uses `lock_version = 2`. It records the exact release ID and SHA-256 digests for
the CLI, each guide, role and adapter, and the remaining package resources.
A component digest covers its packaged paths, contents and executable flags.
Review these entries in the Git diff when updating. Components ship together
under the release version. Each `[stages.NAME]` table records the stage digest,
transitions, roles, conditional tools and SHA-256 of individual input files.
A change to the shared session protocol affects every stage. A change to
`workflow/grill/references/INTERVIEW.md` affects the grill stage. The shared CLI
engine has its own digest. Models and checks live in `.runweld/config.toml`.

Use `runweld update --project RELEASE` to select a specific installed build ID.
That changes the release for new tasks only. From an older task’s worktree,
`runweld next` still uses that task’s release for commands, roles and references.
Keep both builds installed while tasks use them. Tasks from versions before
`runweld next` and dated task directories are not migrated. Start a new task
to use this workflow.

In a terminal, `runweld update` asks you to choose `cli` or `project`.
Scripts must pass a scope explicitly. Outside an initialized project,
`runweld --version` prints the installed default version. Inside one, it prints both `CLI` (the installed default) and `Project`
(the version in the project lock). Add `--verbose` for the exact build IDs.

## Update or repair a release

For a project with an existing lock, install the Git revision that produced
its release ID. Set `revision` to that published tag or commit, then run:

```sh
curl -fsSL https://raw.githubusercontent.com/bmox0/runweld/main/install.sh | RUNWELD_REF="$revision" bash
```

To install into a separate prefix, pass `--prefix DIR` via
`bash -s -- --prefix DIR`. The project lock stores the release ID. It does
not fetch source code or select a Git revision for the installer.

To repair a missing or damaged release, reinstall the source revision that
produced its exact ID. Reinstalling
preserves the project lock. Use `runweld help agents --plan "$plan"` to verify
that the original run can read its instructions again.

## Run a guide

Run `runweld grill` to print the interview and its rules, or `runweld plan` to print the planning instructions. The bare commands for build, review, land and finish also print instructions. Pass the operational arguments to carry out an action, such as `runweld finish PLAN`. Use `--plan PLAN` to read instructions from a task’s pinned release. Run `runweld browser-test` for browser guidance and `runweld browser-test up URL` to open the browser.

## Start or resume a task

In a clean Git checkout, start with `runweld help agents` and `runweld next`.
If prompted, run `runweld init`. It previews project defaults without running
the commands. Commit the shared config, lock and project instructions, and
make an initial Git commit if the checkout has none.

```sh
runweld task start report-search --goal "Search reports by title"
runweld next report-search
```

From the printed task worktree, use `runweld next` without an ID. From the
main checkout, use `runweld next ID` or `runweld next --plan "$plan"` with the
printed plan path. A fresh agent only needs the worktree and the instruction
to run `runweld next`. It can recover the goal, saved decisions, evidence,
current owner and what has to happen before work advances.

Follow the available actions through discovery and planning. Even without
`--goal`, complete the grill and prototype or skip each with a reason before
validating the draft. Save open questions if you stop mid-interview. Add
`--bug` when starting a task that needs a red reproduction instead.
When the draft is ready, `runweld plan review "$plan"`
shows the full plan, run settings and the revision to approve. Use its
approval command with the human’s name and words. Approval records the
decision. A separate instruction authorizes the displayed build-start command.

At the human gate, use the displayed `page --show` command to recover the
review guide. Feedback does not start a round by itself. When the human
authorizes one, follow the round action and review the revised result before
accepting. After current acceptance, the configured finish reports the target
and integration commit. For local finish, the command runs in the surviving
project checkout. If it reports an unknown local file, move it somewhere safe
or resolve it, then follow the cleanup retry. Runweld keeps the dated task
directory, including the accepted result and evidence.

## Inspect a stage

`runweld workflow --stage grill` shows the files used by the interview.
`runweld workflow --stage build-verification --json` includes the reviewer and
verify instructions, the web/Electron browser-test tool and possible next stages.
These commands, agent briefs and the lock read the installed release's
[workflow definition](../references/workflow.toml). Runtime evidence and approvals
determine which transition a task may take.

## Choose the ending for a task

Start from the main checkout's HEAD, or select a base with `--base`.
For a known ending, pass it at task entry:

```sh
runweld task start local-fix --finish-how ff-only --finish-target main
runweld task start review-fix --finish-how merge-request --finish-target main
```

If the ending is open, use `runweld task start ID`. Before approving the plan,
record the agreed `how` and `target` in the companion run file's `[finish]`
table. Approval requires both.

The run file starts with `[workflow]`: `version` names the release and `digest`
pins its exact build with a 64-character SHA-256. Every task uses a worktree.
The optional `[isolation]` table requests a port or data directory for a task.
Enable `port` to use `{port}` in the dev command and URL; enable `data_dir` to
use `{data_dir}` in check commands. Setup receives the corresponding
`RUNWELD_PORT` and `RUNWELD_DATA_DIR` environment variables.

## Workflow actions

Use `runweld next --json` for the same guidance in machine-readable form.
Each entry in `actions` names its `owner`, has readable `action` text, and
supplies a `kind`.

- `run` carries `cwd` and an `argv` array. Run the process in that directory
  with each array item as a separate argument. The command names the installed
  launcher and the task’s pinned release.
- `work` names a `role` and its `assignment`, such as a phase number, review
  range or Done cases. It lists the role instructions, reporting commands and
  return channel. Recover a prepared brief if one exists. Check the host for a
  live worker before dispatching a new one or continuing an existing one.
- `wait` identifies work or authorization to wait for. A worker wait marked
  `after-dispatch` applies only after you confirm dispatch. Generating a brief
  is not dispatch. Run `next` again when the expected result arrives.
- `ask` identifies a decision or missing input. Obtain it from the named owner
  before running its command, if one is shown.

If prompted, pass `--provider NAME` to `next` for executable brief commands using
the approved executor snapshot. For inventory, use `runweld status`. After
finish and cleanup, `actions` is empty. Guidance is a snapshot and each
command still checks whether it can run.

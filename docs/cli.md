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
The current TOML lock contains only `lock_version = 3` and the exact
`release` ID. Runweld verifies the installed files and executable flags
against the release manifest before running commands. Existing version 2
locks remain readable. Selecting a release that expects version 2 writes
its expanded lock. Models and checks live in `.runweld/config.toml`.

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

## Find a command

Run `runweld --help` (or `runweld help`) for the overview, even outside a Git
checkout. A group like `runweld help task` lists its actions. For a specific
operation, both spellings show the same usage, requirements, effects and
examples:

```sh
runweld help task complete
runweld task complete --help
```

Examples in terminal help use placeholders such as `PLAN` for the plan path
printed by task entry. For the workflow, roles and approval boundaries, use
`runweld help agents`. Add `--plan PLAN` to read the run's pinned agent
guidance rather than the current project's release. An older selected release
retains its own help and may not have the detailed command pages.

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

Follow the available actions through discovery and planning. With the default
route, complete Grill and Prototype or skip each with a reason before validating
the draft. Save open questions if you stop mid-interview. Add `--bug` when
starting a task that needs a red reproduction instead.
When the draft is ready, `runweld plan review "$plan"`
shows the planner's text from `<slug>.summary.md` beside the plan, links to all
three files, changes since approval, and the revision to approve. The approval
saves the reviewed summary alongside the plan snapshot. The summary links to
the plan and run settings. Use the six headings from the worked summary, or
number their translations from 1 to 6. `next` identifies missing and empty
sections. Review includes the recorded prototype or bug cause, reproduction
command and artifact. With `--json`, read these from `evidence` beside `summary`.
Previously compiled plans without a summary display in full and return `null`
for `summary`. Use the displayed
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

## Complete or cancel a task

Run these only on the task owner's explicit decision. Use `complete` when the
goal is met and `cancel` when work should stop. Approving a prototype does not
close the task by itself.

```sh
runweld task complete report-search --by "Project owner" --reason "The approved prototype met the goal"
runweld task cancel review-fix --by "Project owner" --reason "The review is no longer needed"
```

Either command records the outcome and the actual stage, before or after plan
compilation. It leaves the worktree, branch, plan history, artifacts, and
release pin in place. It does not approve code, integrate it, or clean up any
files. A repeat of the same outcome returns the first decision. The opposite
outcome is refused.

Check the result with `runweld next ID`, `runweld task resume ID`, or
`runweld status PLAN`. Add `--json` for the recorded `outcome` (including its
`stage`, `by`, `reason`, and `at` fields) and the preserved evidence paths.
Closed tasks stay in the status inventory but are no longer offered as work by
project-wide `next`. Use `runweld task path ID` to locate the saved files.

If a compiled task loses its state file, `next` and `status` show it as
`stopped` with a `not-compiled` reason and the missing file's path. The
launcher refuses workflow writes, including completion and cancellation.
Restore the original state file to resume at the saved stage. An uncompiled
draft can still be closed.

Use an up-to-date installed launcher even for tasks pinned to older releases.
Closing waits for writes already running through that launcher. Subsequent
workflow writes are refused, including commands copied before closure with an
explicit release pin. Closing does not stop agents or commands running directly
in the worktree.

## Inspect a stage

`runweld workflow --stage grill` shows the files used by the interview.
`runweld workflow --stage build-verification --json` includes the reviewer and
verify instructions, the web/Electron browser-test tool and possible next stages.
These commands and agent briefs read the installed release's
[workflow definition](../references/workflow.toml). Runtime evidence and approvals
determine which transition a task may take.

## Set a task's route and providers

Before compiling the plan, edit the companion `.run.toml` file. For example,
skip Grill and require a Prototype for just that task.

```toml
[route]
grill = "skip"
prototype = "take"
```

Use `"ask"` for interactive discovery. An omitted key uses the pinned release's
default, currently `"ask"` for both stages. `"skip"` bypasses a stage that hasn't
started. It doesn't erase saved progress or remove mandatory stages. Run
`runweld next ID` to see the selected stage and its allowed actions.

Pass `--provider NAME` to `task start` when needed to choose the initiating
provider. The task records only that provider's primary and secondary pair.
Run `runweld task start ID --provider NAME` again to join an existing task
with a new provider. Repeating a recorded provider never changes its pair
or effort. Use `runweld executor show --provider NAME PLAN` to inspect the
pair. If the run is already approved, joining updates the proposal. The
approved snapshot stays frozen until renewed human approval.

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

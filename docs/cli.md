# CLI reference

## Install the published CLI

Follow the [installation quick start](../README.md#install). It resolves the
latest published stable tag to an exact Git commit and runs that commit's
installer. The default launcher is `~/.local/bin/runweld`.

## Install from a checkout

Run `./scripts/install-runweld` to install the files in a Runweld source
checkout. This is useful for testing local changes. Use
`./scripts/install-runweld --prefix DIR` to choose another location.

## Update the CLI

Run `runweld update --cli` from any directory to install the latest published
stable release into the current launcher's prefix. A failed lookup or install
leaves the working selection in place. Project and task pins stay unchanged.

## Update a project

Run `runweld update --project` in an onboarded checkout to select the installed
default for new tasks. Commit `runweld.lock` at the Git root to share the selection.
The lock records the exact release ID and SHA-256 component hashes under
`[guides]`, `[roles]`, `[cli]` and `[adapters]`. Updating only the grill
interview changes two values in Git: the release ID and `guides.grill`.
Runweld verifies every installed file against the release manifest.
Existing tasks retain their release and route. Confirmed executors and checkout
settings live in the ignored `.runweld/config.toml`.

Use `runweld update --project RELEASE` to select a specific installed build ID.
That changes the release for new tasks only. From a task’s worktree,
`runweld next` uses that task’s release for commands, roles and references.
Keep builds installed while tasks use them.

In a terminal, `runweld update` asks you to choose `cli` or `project`.
Scripts must pass a scope explicitly. Outside an onboarded project,
`runweld --version` prints the installed default version. Inside one, it prints both `CLI` (the installed default) and `Project`
(the version in the project lock). Add `--verbose` for the exact build IDs.

## Update or repair a release

Set `RUNWELD_REF` to select an explicit tag, commit or development ref in the
CLI updater or the bootstrap script from a Runweld source checkout:

```sh
RUNWELD_REF="$revision" runweld update --cli
RUNWELD_REF="$revision" bash ./install.sh
```

Use `--prefix DIR` with the bootstrap to choose an installation location.
The lock holds a Runweld release ID, not a Git revision.

To repair a missing or damaged release, reinstall the source revision that
produced its exact ID without changing the lock. Check the installed ID with
`runweld --version --verbose` outside the project. Use
`runweld help agents --plan "$plan"` to verify the run can read its instructions.

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
guidance for the task's release.

## Run a guide

Run `runweld grill` to print the interview and its rules, or `runweld plan` to print the planning instructions. The bare commands for build, review, land and finish also print instructions. Pass the operational arguments to carry out an action, such as `runweld finish PLAN`. Use `--plan PLAN` to read instructions from a task’s pinned release. Run `runweld browser-test` for browser guidance and `runweld browser-test up URL` to open the browser.

## Onboard a checkout

Run `runweld next` from your Git checkout. If setup is needed, use
`runweld onboard` to preview the two executor roles, project commands,
sources and unanswered questions. It does not write files or run the commands.
Confirm both roles in chat, even when personal defaults are offered. Resolve
any ambiguous checks or preparation commands, then use `--apply` to save the
confirmed answers. A later preview continues from a partial save. It can also
identify shared files that need repair. See [checkout configuration](../workflow/run-file/references/project-config.md).

Read the per-path outcomes and keep `.runweld/` local. Commit the root
`runweld.lock`, `AGENTS.md` and `.gitignore` so colleagues can clone and
onboard with their own roles. The checkout needs an initial Git commit
before creating a task worktree.

## Start or resume a task

```sh
runweld task start report-search --goal "Search reports by title"
runweld next report-search
```

From the printed task worktree, use `runweld next` without an ID. From the
main checkout, use `runweld next ID` or `runweld next --plan "$plan"` with the
printed plan path. A fresh agent only needs the worktree and the instruction
to run `runweld next`. It can recover the goal, saved decisions, evidence,
current owner and what has to happen before work advances. The ordinary
output leads with the next action. Use `runweld next --details` for exact
commands, paths and recorded evidence. `runweld status` lists all tasks,
including closed ones. Use `runweld status --current` to see the actions
for this checkout or `runweld status "$plan"` for the full plan status.

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
Use the displayed approval command with the human’s name and words. Approval records the
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

Closing waits for writes already running through the launcher. Subsequent
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

## Set a task's route and executors

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

New tasks record the checkout's confirmed primary and secondary executors.
Set a task-specific choice at entry using role flags, for example
`runweld task start report-search --secondary-model MODEL`. Each unspecified
field keeps its checkout default. Use `runweld executor show PLAN` to inspect
both recorded roles, or omit `PLAN` for checkout defaults. Reusing a task ID
does not replace its settings. To propose different executors for an existing
task, edit `[executors]` in its run file and obtain current human approval.

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

Use `runweld next --json` for full evidence and machine-readable actions.
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
  before running its command, if one is shown. At acceptance, it includes the
  named acceptor and recorded authority when available.

Task actions use the recorded executor choices, frozen at approval. For
inventory, use `runweld status`. After
finish and cleanup, `actions` is empty. Guidance is a snapshot and each
command still checks whether it can run.

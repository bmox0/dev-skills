# The run file

`.runweld/workflow/plans/<slug>.run.toml`, written before the plan: what a run may do, its checks, its isolation and how it ends.

### starts-from-last — Every new run takes its defaults from current project configuration and records its exact Runweld release

Why: local history must not override shared project decisions and retro needs the release actually used.

- Initialize once, then start one local run and one merge-request run → the project has no finish method, and each run approves its own method and target. An undecided task may start planning; it must choose both before approval.
- Change the shared test command and create a run with an older run present → the new run config records the current checks, profiles and exact release. Resume the older run → it uses its approved snapshot.
- Install releases A and B, start a run on A and call `runweld update --project` → the project lock moves to B, new work uses B, and the active run and its briefs still use A. An unavailable or damaged release gives an actionable error and leaves the prior lock or run intact.

### contract-checked — Onboarding validates each role and exposes project commands, sources and unresolved decisions before use

Why: an operator must see what the agent will run and which inputs are still needed

- In an empty Git checkout run `next --json` then the offered preview. Nothing is written. Inspect proposed commands, sources and both roles. Apply the confirmed settings and see a per-path outcome. Repeat and verify byte-identical project files.
- Commit shared setup and clone it. The clone has the root lock and no local configuration. With both global defaults supplied, a new agent still asks for confirmation. Save one role, stop, and finish from a fresh process. Removing only the managed block or ignore rule offers repair and preserves adjacent user text.
- Resolve conflicting project and CI checks in chat after seeing both sources. With two mandatory commands, try omitting one before approval, then try a judge waiver after one fails. Both attempts stop before a pass or integration. Fix the failure, rerun at the current head and observe both successes.
- Confirm GPT primary and Claude secondary. Override just the secondary model for one task. Change global defaults, open a new session and inspect both role briefs. They use the recorded providers, models and efforts. A sibling task uses checkout defaults and a new clone offers the new personal defaults.

### required-to-approve — Build requires one current human approval binding the complete plan and run config

Why: authorization identifies both the work and how it will be executed

- Review a complete plan and its config, approve once, then start separately. Change a criterion or finish target and see the affected approval become stale. Repeated start preserves the phase, worktree and executor.

### changes-through-approve — Changes to approved planning content or execution settings identify the stale approval and preserve progress

Why: the human must see a material change before work proceeds under it

- Review a complete plan and its config, approve once, then start separately. Change a criterion or finish target and see the affected approval become stale. Repeated start preserves the phase, worktree and executor.
- Accept a landed result once. Verify the agreed local fast-forward and cleanup. Repeat with an unknown ignored file. Preserve it, expose pending cleanup, resolve it, and retry cleanup without a second integration. A changed accepted revision blocks finish.

### isolated — Plans of one project being built get a port and an app data directory of their own from code

Why: runs of one project go side by side

- Two plans in one repo both have `port = true` and `data_dir = true`. Run `build start` on each while something listens on the first port of the range → two different ports, neither of them the busy one, and two directories that exist, all among the printed facts; `run show` prints `dev` with them filled in. Task entry creates a dedicated worktree independently of these settings.

### secrets-as-written — Code hands `[run]` values on as written and never resolves a keychain pointer

Why: a secret given by pointer stays out of the state and the briefs

- Run `brief implementer 2` on a plan with three `## Spec` entries → the file holds `[checks].phase`, every `[run]` key as written with the keychain pointer unresolved, each entry's ID, statement and Done items, and one `Territory:` line.

### e2e-within — e2e sets up only what the run file covers; what it does not cover is `not reached`

Why: nothing pulls the user in mid-run

- Run `runweld verify` on a plan whose use case needs a login its run file lacks → that case is `not reached: needs <the login>`, and the dev server it starts uses the run's port

### executor-presets — Each task records its resolved primary and secondary executor independently, and approval binds both roles

Why: a later host must resume with the approved assignments

- Confirm GPT primary and Claude secondary. Override just the secondary model for one task. Change global defaults, open a new session and inspect both role briefs. They use the recorded providers, models and efforts. A sibling task uses checkout defaults and a new clone offers the new personal defaults.
- Open a checkout with similarly titled tasks, select one by ID, and recover from its linked worktree. Read the next action before history. On an approved plan a separate start is still required. Inspect detailed output and execute a permitted JSON action in its declared cwd. For an unknown ID, follow the displayed recovery command.

### task-worktree — Every new Runweld task has a dedicated branch and worktree from entry through confirmed integration, with local history accessible across trees

Why: concurrent tabs can plan, build and resume independently while their code and specs reach the same project.

- Start two tasks concurrently from one checkout, including a small task → grill and planning use different branches and worktrees; project status lists both and each tab sees its own next action. Resume one task from a fresh tab → same tree and history. Both can plan before dependency installation. At the first step needing the environment, exercise optional setup with separate ports and data directories; fail it once and retry in the same tree. A project without a setup command also works.
- In both tasks edit code and the same spec file. Accept and finish the first → its code and spec reach the target, its clean worktree is removed and its history remains visible. Resume the second at its previous step. Exercise a conflicting integration and a cleanup with unsaved work → preserve the affected tree and files, report the next action, and complete cleanup safely after resolution. An open merge request retains its tree until integration is confirmed.

### worktree-setup — Tasks prepare their runtime environment when needed using optional project setup and task-specific resources

Why: planning works in a fresh tree and setup can retry without creating a second task.

- Start two tasks concurrently from one checkout, including a small task → grill and planning use different branches and worktrees; project status lists both and each tab sees its own next action. Resume one task from a fresh tab → same tree and history. Both can plan before dependency installation. At the first step needing the environment, exercise optional setup with separate ports and data directories; fail it once and retry in the same tree. A project without a setup command also works.

### mandatory-checks — A successful run accounts for every project-designated mandatory check

Why: colleagues need the same meaning of a passing result

- Resolve conflicting project and CI checks in chat after seeing both sources. With two mandatory commands, try omitting one before approval, then try a judge waiver after one fails. Both attempts stop before a pass or integration. Fix the failure, rerun at the current head and observe both successes.
- Starting with only the README chat prompt, complete onboarding and follow a disposable task through approval, verification, human acceptance and local finish. A fresh agent can identify outstanding checks, recorded decisions and the next owner after interruption.

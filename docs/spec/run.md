# The run file

`.runweld/workflow/plans/<slug>.run.toml`, written before the plan: what a run may do, its checks, its isolation and how it ends.

### starts-from-last — Every new run takes its defaults from current project configuration and records its exact Runweld release

Why: local history must not override shared project decisions and retro needs the release actually used.

- Initialize once, then start one local run and one merge-request run → the project has no finish method, and each run approves its own method and target. An undecided task may start planning; it must choose both before approval.
- Change the shared test command and create a run with an older run present → the new run config records the current checks, profiles and exact release. Resume the older run → it uses its approved snapshot.
- Install releases A and B, start a run on A and call `runweld update --project` → the project lock moves to B, new work uses B, and the active run and its briefs still use A. An unavailable or damaged release gives an actionable error and leaves the prior lock or run intact.

### contract-checked — Project and run settings validate fixed fields, opaque provider and model identifiers, optional effort and scalar task values

Why: malformed configuration must identify the affected setting across both terminal and agent entry points.

- Install outside the project and run `runweld init` in a plain terminal → select one provider, enter its pair and checks, receive a usable config, lock, ignore rule and short AGENTS pointer. Repeat init or interrupt and retry → user-authored content and profiles survive.
- Commit the shared files, clone elsewhere and select Claude → supply only the missing Claude pair, retain the Codex pair and checks, and see no previous plans. Both clones select the same release.
- Change the shared test command and create a run with an older run present → the new run config records the current checks, profiles and exact release. Resume the older run → it uses its approved snapshot.

### required-to-approve — Build requires explicit approval of the proposed run and a summary matching the current plan and Spec

Why: successful validation does not establish consent

- Validate a draft before consent → no approval; approve run then the current summary → build becomes eligible. Change run, plan or Spec → affected consent is stale; progress records survive reapproval.

### changes-through-approve — Approved run settings bind the release and execution inputs, and changing approved planning content requires corresponding renewed consent

Why: a project update or another contributor’s configuration cannot silently change approved work.

- Change the shared test command and create a run with an older run present → the new run config records the current checks, profiles and exact release. Resume the older run → it uses its approved snapshot.
- Install releases A and B, start a run on A and call `runweld update --project` → the project lock moves to B, new work uses B, and the active run and its briefs still use A. An unavailable or damaged release gives an actionable error and leaves the prior lock or run intact.

### isolated — Plans of one project being built get a port and an app data directory of their own from code

Why: runs of one project go side by side

- Two plans in one repo both have `port = true` and `data_dir = true`. Run `build start` on each while something listens on the first port of the range → two different ports, neither of them the busy one, and two directories that exist, all among the printed facts; `run show` prints `dev` with them filled in. Task entry creates a dedicated worktree independently of these settings.

### secrets-as-written — Code hands `[run]` values on as written and never resolves a keychain pointer

Why: a secret given by pointer stays out of the state and the briefs

- Run `brief implementer 2` on a plan with three `## Spec` entries → the file holds `[checks].phase`, every `[run]` key as written with the keychain pointer unresolved, each entry's ID, statement and Done items, and one `Territory:` line.

### e2e-within — e2e sets up only what the run file covers; what it does not cover is `not reached`

Why: nothing pulls the user in mid-run

- Run `runweld verify` on a plan whose use case needs a login its run file lacks → that case is `not reached: needs <the login>`, and the dev server it starts uses the run's port

### executor-presets — Project configuration supplies named primary and secondary presets and an approved run freezes its profiles

Why: teammates can add their own provider while retaining shared checks and earlier approvals.

- Install outside the project and run `runweld init` in a plain terminal → select one provider, enter its pair and checks, receive a usable config, lock, ignore rule and short AGENTS pointer. Repeat init or interrupt and retry → user-authored content and profiles survive.
- Commit the shared files, clone elsewhere and select Claude → supply only the missing Claude pair, retain the Codex pair and checks, and see no previous plans. Both clones select the same release.
- Change the shared test command and create a run with an older run present → the new run config records the current checks, profiles and exact release. Resume the older run → it uses its approved snapshot.

### task-worktree — Every new Runweld task has a dedicated branch and worktree from entry through confirmed integration, with local history accessible across trees

Why: concurrent tabs can plan, build and resume independently while their code and specs reach the same project.

- Start two tasks concurrently from one checkout, including a small task → grill and planning use different branches and worktrees; project status lists both and each tab sees its own next action. Resume one task from a fresh tab → same tree and history. Both can plan before dependency installation. At the first step needing the environment, exercise optional setup with separate ports and data directories; fail it once and retry in the same tree. A project without a setup command also works.
- In both tasks edit code and the same spec file. Accept and finish the first → its code and spec reach the target, its clean worktree is removed and its history remains visible. Resume the second at its previous step. Exercise a conflicting integration and a cleanup with unsaved work → preserve the affected tree and files, report the next action, and complete cleanup safely after resolution. An open merge request retains its tree until integration is confirmed.

### worktree-setup — Tasks prepare their runtime environment when needed using optional project setup and task-specific resources

Why: planning works in a fresh tree and setup can retry without creating a second task.

- Start two tasks concurrently from one checkout, including a small task → grill and planning use different branches and worktrees; project status lists both and each tab sees its own next action. Resume one task from a fresh tab → same tree and history. Both can plan before dependency installation. At the first step needing the environment, exercise optional setup with separate ports and data directories; fail it once and retry in the same tree. A project without a setup command also works.

# The run file

`.ai-workflow/plans/<slug>.run.toml`, written before the plan: what a run may do, its checks, its isolation and how it ends.

### starts-from-last — A new run file starts as a copy of the project's latest one, or of the shipped example with an empty `[run]` when there is none

Why: the user is asked only what differs from the last run, and no sample login reaches a run

- In a throwaway repo with no run file, run `run new <plan>` → the run file is a copy of the shipped example with an empty `[run]`, and the output names it; `run check` on it is silent. Add a newer run file, then run `run new` for another plan → it copies the newer one; run it again → refused, the file unchanged.

### contract-checked — A run file's fixed sections refuse an unknown or missing key and a value outside its type or list; its `[run]` section takes any key with a plain value

Why: no agent invents a field, and code hands on what it cannot judge

- Give a run file `mode = "x"` and `how = "squash"` under `[finish]`, no `full` under `[checks]`, a `[deploy]` section, a table and a list under `[run]`, and `dev` using `{port}` with `port = false` → `run check` exits 1 with one line per problem, naming its section and key. `admin_pwd = "keychain:app/admin"`, `can_remove_tasks = false` and `quota = 20` under `[run]` pass.

### required-to-approve — A draft is approved only with a run file that passes its check

Why: what a run may do and how it ends is asked before the plan, not mid-run

- `approve` a draft with no run file → exit 1, a fix naming `dev-skills:run-file`, no JSON; with a bad one → exit 1 with `run check`'s lines; with a good one → approved. Change `delete_backups` in the file, or `quota = 1` to `quota = true` → `status` and `run show` report the drift and show the approved value; `approve` again → the new value, and `status` lists the changed keys in the plan's history. A pre-5.1 plan at `building` with no run file → adopted.

### changes-through-approve — After approval every reader uses the run file's approved values and reports a changed file until `approve` runs again, which records the changed keys in the plan's history

Why: a run cannot widen what it may do without it showing

- `approve` a draft with no run file → exit 1, a fix naming `dev-skills:run-file`, no JSON; with a bad one → exit 1 with `run check`'s lines; with a good one → approved. Change `delete_backups` in the file, or `quota = 1` to `quota = true` → `status` and `run show` report the drift and show the approved value; `approve` again → the new value, and `status` lists the changed keys in the plan's history. A pre-5.1 plan at `building` with no run file → adopted.

### isolated — Plans of one project being built get a port and an app data directory of their own from code

Why: runs of one project go side by side

- Two plans in one repo both have `port = true` and `data_dir = true`. Run `build start` on each while something listens on the first port of the range → two different ports, neither of them the busy one, and two directories that exist, all among the printed facts; `run show` prints `dev` with them filled in. With `worktree = true`, `build start` without `--worktree` → refused; with `--note` → built here, the note in `status`.

### secrets-as-written — Code hands `[run]` values on as written and never resolves a keychain pointer

Why: a secret given by pointer stays out of the state and the briefs

- Run `brief implementer 2` on a plan with three `## Spec` entries → the file holds `[checks].phase`, every `[run]` key as written with the keychain pointer unresolved, each entry's ID, statement and Done items, and one `Territory:` line.

### e2e-within — e2e sets up only what the run file covers; what it does not cover is `not reached`

Why: nothing pulls the user in mid-run

- Run `dev-skills:verify` on a plan whose use case needs a login its run file lacks → that case is `not reached: needs <the login>`, and the dev server it starts uses the run's port

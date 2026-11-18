# The run file

`.ai-workflow/plans/<slug>.run.toml`, written before the plan: what a run may do, its checks, its isolation and how it ends.

### starts-from-last — A new run copies the latest run or the example, strips example credentials and snapshots all current AGENTS Executors profiles

Why: useful defaults are proposals while provider defaults come from one shared source

- Dispatch grill helpers using current AGENTS Executors profiles, then draft a run for GPT, Qwen, Claude and another provider → all profiles are copied; malformed presets and unknown fixed fields identify their paths; model names have no vendor allowlist.
- Approve a run, change AGENTS, then transfer planning from GPT to a Claude build → approved profiles stay frozen and Claude selects its own pair; missing profiles produce an actionable request.

### contract-checked — Fixed run fields and provider presets are validated; task values remain scalar and provider identifiers remain open

Why: malformed configuration fails without restricting supported providers

- Dispatch grill helpers using current AGENTS Executors profiles, then draft a run for GPT, Qwen, Claude and another provider → all profiles are copied; malformed presets and unknown fixed fields identify their paths; model names have no vendor allowlist.
- Approve a run, change AGENTS, then transfer planning from GPT to a Claude build → approved profiles stay frozen and Claude selects its own pair; missing profiles produce an actionable request.

### required-to-approve — Build requires explicit approval of the proposed run and a summary matching the current plan and Spec

Why: successful validation does not establish consent

- Validate a draft before consent → no approval; approve run then the current summary → build becomes eligible. Change run, plan or Spec → affected consent is stale; progress records survive reapproval.

### changes-through-approve — Readers use approved run snapshots; changed approved planning content requires renewed corresponding approval

Why: configuration cannot silently widen authority or change reviewed behavior

- Approve a run, change AGENTS, then transfer planning from GPT to a Claude build → approved profiles stay frozen and Claude selects its own pair; missing profiles produce an actionable request.
- Validate a draft before consent → no approval; approve run then the current summary → build becomes eligible. Change run, plan or Spec → affected consent is stale; progress records survive reapproval.
- Change the branch tree or approved planning content after a page/acceptance → stale stages are identified; passed and finish refuse until the required evidence and acceptance are current.

### isolated — Plans of one project being built get a port and an app data directory of their own from code

Why: runs of one project go side by side

- Two plans in one repo both have `port = true` and `data_dir = true`. Run `build start` on each while something listens on the first port of the range → two different ports, neither of them the busy one, and two directories that exist, all among the printed facts; `run show` prints `dev` with them filled in. With `worktree = true`, `build start` without `--worktree` → refused; with `--note` → built here, the note in `status`.

### secrets-as-written — Code hands `[run]` values on as written and never resolves a keychain pointer

Why: a secret given by pointer stays out of the state and the briefs

- Run `brief implementer 2` on a plan with three `## Spec` entries → the file holds `[checks].phase`, every `[run]` key as written with the keychain pointer unresolved, each entry's ID, statement and Done items, and one `Territory:` line.

### e2e-within — e2e sets up only what the run file covers; what it does not cover is `not reached`

Why: nothing pulls the user in mid-run

- Run `dev-skills:verify` on a plan whose use case needs a login its run file lacks → that case is `not reached: needs <the login>`, and the dev server it starts uses the run's port

### executor-presets — Literal project-root AGENTS model/effort pairs select primary/secondary before approval and remain frozen in the approved run

Why: explicit project choices supersede native execution presets or inferred vendor defaults

- Read literal project AGENTS, approve run, then change AGENTS → explicit pairs stay frozen; import-only configuration and unavailable choices fail clearly; no external native-preset alternative appears.
- Initialize and continue roles with captured instruction sources and bounded behavior checks → identity, executor, scope and reports persist; generic mode requires equivalence, and implementer context never becomes independent review.

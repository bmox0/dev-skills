This is history; the rules that hold now are in `docs/spec/`.

# Plan: Run dev-skills from the system ds CLI

## Result

Install `ds` once on a machine. A person can initialize a project directly in a terminal. An agent can use the same workflow with one independently installed `ds-cli-skill`. A colleague on Claude can clone a project initialized with Codex, reuse its configuration and run the same release through human acceptance. Starting two tasks from the same checkout gives each its own branch and worktree from the first conversation through finish.

## Approach

- Ship the existing engine, stage and role instructions, references and required helpers together. The release owns the graph, roles, transition conditions and approval boundaries. The coordinator and host retain their current responsibilities. Use [afactory’s project layout](https://github.com/PakhomovAlexander/afactory/blob/f7dc86516696397b365a5016ed11cea5b808be57/README.md#configuration) and [agent entry decision](https://github.com/PakhomovAlexander/afactory/blob/f7dc86516696397b365a5016ed11cea5b808be57/docs/adr/0259-point-agents-at-the-loop-in-four-rules-and-own-skills-by-their-bytes.md) as references.
- Keep editable project defaults and the exact release lock in Git-shareable files under `.ds/`. The initial release may use the prototype names `config.toml` and `ds.lock`. Select a packaging method that permits side-by-side versions and a tested install from outside this checkout. The public commands are `ds init`, `ds update` and `ds help agents`.
- Fresh runs use the current project defaults exclusively. Each run config records the actual release and proposed inputs. Existing approval gates freeze the agreed inputs. A run-specific command selects that run’s release even after the project updates. A missing release must be recoverable without executing a different one.
- Keep all former dev-skills workflow material local under `.ds/workflow/`, including plans, evidence and retros. Durable knowledge stays in the project’s specs, ADRs, context and agent instructions. Preserve old runs, approvals, paths used by outstanding work and historical evidence during adoption.

- On entry to every new task, including a small task, create its branch and worktree from the project base before grill or planning. Bind later actions to that task so another tab can resume it. The shared local workflow directory holds one record per task, visible from every linked tree. Help and status remain read-only. Build reuses the registered tree after the existing approvals.
- Planning needs only the checkout. At the first step requiring a runnable environment, use an optional project setup command configured at init. Run it in the task tree with the source checkout, task path and any allocated port and data directory. A failed setup can retry in place. Projects that need no setup require no script.
- Apply durable spec edits alongside code on the task branch. Finish follows the agreed merge policy. Remove only the task-owned tree after confirmed integration and a check for unsaved work. A conflict, pending merge request or unsafe cleanup preserves the tree and reports how to continue.

## Out of scope

Project-defined graphs, harness hooks on the new path, new agent orchestration, a shared database or synchronization of local runs. The repository supplies installable artifacts and instructions. Publishing a public release requires a separate release action.

## Done and Spec

```text
## Done

1. Install outside the project and run `ds init` in a plain terminal → select one provider, enter its pair and checks, receive a usable config, lock, ignore rule and short AGENTS pointer. Repeat init or interrupt and retry → user-authored content and profiles survive.
2. Commit the shared files, clone elsewhere and select Claude → supply only the missing Claude pair, retain the Codex pair and checks, and see no previous plans. Both clones select the same release.
3. Change the shared test command and create a run with an older run present → the new run config records the current checks, profiles and exact release. Resume the older run → it uses its approved snapshot.
4. Install releases A and B, start a run on A and call `ds update` → the project lock moves to B, new work uses B, and the active run and its briefs still use A. An unavailable or damaged release gives an actionable error and leaves the prior lock or run intact.
5. Adopt a legacy checkout with historical and active runs, compiled approvals, an issued command and a linked worktree → the command still works, inventory finds each run once, recorded approvals and evidence survive, and retrying migration preserves all files. New plans, evidence and scratch files stay ignored while config, lock and specs appear in Git.
6. Follow `ds help agents` through planning, approved build, review, E2E, judge, land, human gate and authorized finish with plugins and hooks disabled → the appropriate role receives its instructions, human receives a concrete guide, and release rules reject a premature transition or attempted project graph override.
7. Run an advertised JSON action from another directory with spaces in the checkout path → it targets the intended run and release. Existing CLI callers retain compatible output, status codes and approval checks.
8. In a real Codex project and a colleague’s Claude clone, use the documented skill installation and ask “используй ds” → each agent discovers its next action using the single skill. Review the guide for the actual build — you check.

9. Start two tasks concurrently from one checkout, including a small task → grill and planning use different branches and worktrees; project status lists both and each tab sees its own next action. Resume one task from a fresh tab → same tree and history. Both can plan before dependency installation. At the first step needing the environment, exercise optional setup with separate ports and data directories; fail it once and retry in the same tree. A project without a setup command also works.
10. In both tasks edit code and the same spec file. Accept and finish the first → its code and spec reach the target, its clean worktree is removed and its history remains visible. Resume the second at its previous step. Exercise a conflicting integration and a cleanup with unsaved work → preserve the affected tree and files, report the next action, and complete cleanup safely after resolution. An open merge request retains its tree until integration is confirmed.

## Spec

+ distribution#system-cli — A standalone installation provides ds and all release-owned workflow instructions to humans and agents
  Why: a new harness needs only one lightweight entry skill to use the same process.
  Done: 1, 6, 8
+ distribution#project-lock — The project locks the workflow release and ds update changes that selection for new work
  Why: collaborators must share reproducible rules and preserve ongoing work across updates.
  Done: 2, 4
+ distribution#local-workflow — Shared project configuration and private workflow artifacts have distinct Git visibility
  Why: a clone reuses project settings while execution records and evidence stay local.
  Done: 2, 5
~ run#starts-from-last — Every new run takes its defaults from current project configuration and records its exact ds release
  Why: local history must not override shared project decisions and retro needs the release actually used.
  Done: 3, 4
~ run#executor-presets — Project configuration supplies named primary and secondary presets and an approved run freezes its profiles
  Why: teammates can add their own provider while retaining shared checks and earlier approvals.
  Done: 1, 2, 3
~ run#contract-checked — Project and run settings validate fixed fields, opaque provider and model identifiers, optional effort and scalar task values
  Why: malformed configuration must identify the affected setting across both terminal and agent entry points.
  Done: 1, 2, 3
~ run#changes-through-approve — Approved run settings bind the release and execution inputs, and changing approved planning content requires corresponding renewed consent
  Why: a project update or another contributor’s configuration cannot silently change approved work.
  Done: 3, 4, 5
+ run#task-worktree — Every new ds task has a dedicated branch and worktree from entry through confirmed integration, with local history accessible across trees
  Why: concurrent tabs can plan, build and resume independently while their code and specs reach the same project.
  Done: 9, 10
+ run#worktree-setup — Tasks prepare their runtime environment when needed using optional project setup and task-specific resources
  Why: planning works in a fresh tree and setup can retry without creating a second task.
  Done: 9
```

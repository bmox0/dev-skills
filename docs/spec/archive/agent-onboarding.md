This is history; the rules that hold now are in `docs/spec/`.

# Plan: Onboard a team to Runweld from chat

## Result

A colleague can ask a coding agent to set up Runweld after cloning a repository. The agent reports the project's requirements, asks for both executors in chat, and verifies the resulting setup. A fresh agent can recover interrupted setup or an active task and identify who acts next.

## Approach

- `runweld onboard` is the sole setup command. Bare invocation inspects the checkout without writes or a TTY. `onboard --apply` records supplied answers, including explicit confirmation of offered defaults. A partial answer saves local progress and identifies the remaining question. Preview and apply never execute discovered project commands.
- Track root `runweld.lock`, the managed entry in `AGENTS.md`, and `/.runweld/` in `.gitignore`. Keep config and task state local. A clone of recorded project files gets its own role confirmation. Linked worktrees of the same task recover configuration from the owning checkout. Preserve unrelated file content and edits made between inspection and application.
- Read personal defaults from `$XDG_CONFIG_HOME/runweld/config.toml`, falling back to `~/.config/runweld/config.toml`. Use `[executors.primary]` and `[executors.secondary]` tables with `provider`, `model` and optional `effort`. Each checkout saves the confirmed pair. `onboard` and `task start` accept role-specific field flags such as `--secondary-model`. A task override inherits the remaining fields and its resolved pair travels with approvals and briefs. Surface unsupported choices before dispatch.
- Use project-declared mandatory checks, including a designated CI entry point. Cite each source. The agent can inspect scripts, manifests and CI to resolve intent. Conflicts require a decision in chat. Save the resolution locally. Bind the required commands at task entry. Additional checks may be proposed. A pass requires successful results for every mandatory command at the revision under review.
- Install and update from the latest published stable GitHub release by default. Resolve the release once per invocation and use that exact revision. Keep an explicit source selection available for development. A failed lookup or download leaves the working installation usable.

## Out of scope

Dashboard work, new provider integrations, remote storage for task state, and publication of a release.

## Done and Spec

```text
## Done

1. In an empty Git checkout run `next --json` then the offered preview. Nothing is written. Inspect proposed commands, sources and both roles. Apply the confirmed settings and see a per-path outcome. Repeat and verify byte-identical project files.
2. Commit shared setup and clone it. The clone has the root lock and no local configuration. With both global defaults supplied, a new agent still asks for confirmation. Save one role, stop, and finish from a fresh process. Removing only the managed block or ignore rule offers repair and preserves adjacent user text.
3. Resolve conflicting project and CI checks in chat after seeing both sources. With two mandatory commands, try omitting one before approval, then try a judge waiver after one fails. Both attempts stop before a pass or integration. Fix the failure, rerun at the current head and observe both successes.
4. Confirm GPT primary and Claude secondary. Override just the secondary model for one task. Change global defaults, open a new session and inspect both role briefs. They use the recorded providers, models and efforts. A sibling task uses checkout defaults and a new clone offers the new personal defaults.
5. Open a checkout with similarly titled tasks, select one by ID, and recover from its linked worktree. Read the next action before history. On an approved plan a separate start is still required. Inspect detailed output and execute a permitted JSON action in its declared cwd. For an unknown ID, follow the displayed recovery command.
6. With an unpublished branch tip, a prerelease and a published stable release, install into a clean prefix and update an existing one. Both select the stable revision. A failed lookup or damaged download preserves the working selection. A missing locked build in a clone identifies the exact build to install. Move a test project's root lock to another valid build and resume an already started task on its recorded build.
7. Starting with only the README chat prompt, complete onboarding and follow a disposable task through approval, verification, human acceptance and local finish. A fresh agent can identify outstanding checks, recorded decisions and the next owner after interruption.

## Spec

~ distribution#system-cli — Project and task entry guide an agent from chat onboarding through interruption and finish
  Why: a fresh session needs the next authorized action in context
  Done: 1, 2, 5, 7
~ distribution#local-workflow — The root release lock and entry instructions are shared while each checkout owns its configuration and workflow records
  Why: teammates share project requirements and choose their own executors
  Done: 1, 2
+ distribution#published-install — Default installation and CLI updates select an exact published stable release
  Why: two installs against the same release should use the same code
  Done: 6
~ run#contract-checked — Onboarding validates each role and exposes project commands, sources and unresolved decisions before use
  Why: an operator must see what the agent will run and which inputs are still needed
  Done: 1, 2, 3, 4
~ run#executor-presets — Each task records its resolved primary and secondary executor independently, and approval binds both roles
  Why: a later host must resume with the approved assignments
  Done: 4, 5
+ run#mandatory-checks — A successful run accounts for every project-designated mandatory check
  Why: colleagues need the same meaning of a passing result
  Done: 3, 7
```

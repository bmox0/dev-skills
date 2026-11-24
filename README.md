# dev-skills

A provider-neutral workflow with optional Claude Code, Codex and Qoder adapters: skills and three agents for building a
change — discussion, a plan file, implementation by subagents, a review and an
e2e check, and your approval before merge. The user or designated orchestrator coordinates the run;
a chosen build session coordinates implementation. Neither edits code.

## The pipeline

Run `python3 skills/build/pipeline.py workflow` from this repository to see the
eight stages before planning. Use the installed CLI path in other repositories.
Run `status <plan>` for its stage, owner and next action, or `status --current`
to find relevant plans from your checkout.

For automation, use `workflow --json` before there is a plan, or
`status --json <plan>` and `status --current --json` during a run. Read
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

1. **Grill (optional).** Use a grill when the change is unclear or a discussion
   for simpler work. Workers bring facts from the code. You make the decisions.
   A bug adds its reproduction and its cause. A second worker on secondary, the spec
   scout, brings the rules in `docs/spec/` that the task touches; you are asked
   about a rule only when the task leaves open whether it stays true, in product
   words, and the plan's writer records it.
2. **Prototype (optional).** After the discussion, you can choose an HTML file,
   a prototype inside the app with real data, or code. A worker draws it.
3. **Run file and plan.** First the run file (`<slug>.run.toml`,
   [`run-file`](skills/run-file/SKILL.md)): what the run may do, its checks, its
   isolation and how it ends, asked once so nothing pulls you in mid-run. Then
   the plan, always a file, one screen: Result, Approach, Out of scope, Phases,
   Checks, Done, `## Spec` (the rules added, changed, removed) and the prototype's
   link, in the language named by the `Language` line of your `AGENTS.md`; `pipeline.py spec check` runs before you see it. Each phase names its territory, the
   skills its code follows, the spec files it reads, and what it waits for; territories and waits form
   the graph. `pipeline.py approve` compiles the plan into its state, a JSON
   file beside it; from then on the CLI keeps the state and renders the plan,
   its notes, the judge's file and the gate page from it. Status runs `draft` →
   `approved` → `building` → `at the human gate` → `passed` → `merged`, via
   `a merge-request link` when finish opens one. The plan session sets
   `approved` only after explicit run approval and approval of a linked summary
   of at most 350 words. `approve` only validates; `run approve --by --words`
   freezes the proposed run, and `summary approve --file --by --words` binds
   consent to the current run, plan and Spec. Planning then stops.
4. **Build.** Summary approval starts nothing. A subsequent instruction chooses
   herdr, a native independent session or manual handoff.
   That session runs the graph and owns pipeline transitions. One branch and
   one working tree per plan: this one, or a
   worktree when another plan is building here. Every phase whose
   dependencies are met starts at once, as an implementer that writes only
   inside its territory and runs the project's checks on it. Before the gate and
   each re-check, `pipeline.py spec write` runs and `docs/spec/` is committed alone.
5. **Build verification.** The coordinator opens the gate after the last phase.
   At the level the plan names, small or normal, code runs
   the full checks, then at once a fresh review against the project's rules (and the `Spec:` areas' rules) and
   e2e over what you would not see by trying the app, at each width the plan
   names. Code records the findings and results; defects and failures make one
   list for one new implementer, then a targeted re-check. How many fixes and
   rounds a gate allows is held in code, not here.
6. **Judge.** A fresh primary judge decides every open entry and every Convention
   (let through, one round with a cause, or a question to you), records its
   verdict and its prediction of your verdict, and lands the branch: the working commits
   become the ones a reviewer reads, one or a few by meaning, on the same tree;
   a backup branch keeps the old ones.
7. **Human review.** The build session sends the guide you see on the page.
   The guide tells you where to open the landed result,
   what to try and what you still need to decide. The page also has the judge's
   report, E2E results with their commits and a walkthrough of each landed commit.
   Your designated contact alerts you and opens the result. You try the running app
   and read the commits in one sitting. Each note you make gets a cause from
   seven and is matched against the judge's prediction; a note that changes
   the approach is listed as a task, not built. A round runs on your word,
   then the judge again (it lands) and back to the gate. The contact relays
   your notes, round requests and approval unchanged to the same build session;
   notes alone start no round. [Example guide](skills/build/references/example.guide.md).
8. **Finish.** `accept --by --words` records the user’s or authorized acceptor’s
   approval of the current page; finish runs when instructed. It asks
   nothing: the run file says how it ends (a merge request, or local with
   `--no-ff` or `--ff-only`) and whether the plan's backups go; the message
   comes from the plan's Result. The branch stays.

## What you type

| You type | It does |
|---|---|
| [`grill`](skills/grill/SKILL.md), or just talk | reach a shared understanding; then a prototype is offered, then the run file, then the plan |
| [`bug`](skills/bug/SKILL.md) | a worker reproduces it and brings the cause; the red test becomes phase 1 |
| [`prototype`](skills/prototype/SKILL.md) | a throwaway answer to a design question, drawn by a worker |
| [`epic`](skills/epic/SKILL.md) | several plans in order, only when you say so |
| [`run-file`](skills/run-file/SKILL.md) | what the run may do, its checks and how it ends, asked once before the plan |
| [`plan`](skills/plan/SKILL.md) | the one-screen plan and its graph |
| [`build <plan>`](skills/build/SKILL.md) | the branch, the implementers, the E2E gate, the judge, the human gate |
| [`land`](skills/land/SKILL.md) | the commits a reviewer reads; the judge runs it |
| [`finish`](skills/finish/SKILL.md) | on your word at the gate, merge it: a merge request, or local with `--no-ff` or `--ff-only` |

The chosen handoff reuses the existing writer on resume. Questions and acceptance
go to the user or designated orchestrator within granted authority; relayed
words stay unchanged. The contract: [`references/SESSIONS.md`](references/SESSIONS.md).

## Who does what

- **You** decide, and say at the gate whether it passes. A prototype, an epic, how to
  finish and a retro are your call.
- **The orchestrator** plans using primary, handles routine questions from the
  agreed plan, and relays your words within the authority you grant.
- **The build session** coordinates using primary and owns pipeline transitions.
  It reports to the designated contact. Coordinators never edit code.
- **Implementers** use secondary in a clean context, handed their phase and
  earlier reports. They record rulings with their cost if wrong.
- **Workers** use secondary for research, prototypes and verify/E2E.
- **The reviewer** uses primary for the first review, even at a small gate;
  secondary for rechecks and round reviews.
- **The judge** uses primary after every gate or round, decides what results
  mean, records its prediction and runs `land`.

`AGENTS.md` is the shared source. Its Executors block defines each provider’s
primary/secondary model and optional effort. `executor show --provider NAME`
reads it before run approval; adding the plan selects the frozen snapshot
afterward. New runs copy every provider. All new briefs require `--provider`
and expose their assigned tier/model/effort; dispatch applies them explicitly.
Provider and model names are open. A missing profile asks for configuration,
never substitutes a provider. [`references/CODEX.md`](references/CODEX.md) is
an optional host adapter.

The state lives in code. `skills/build/pipeline.py` (the CLI) keeps each plan's
state and the run file's approved values, renders the plan and the gate page,
runs the checks, holds the caps, and lands and finishes as the run file says;
the skills and agents decide what to do with what it reports. The other tool is
`skills/browser-test/tab.mjs`; the level-1 checks are the project's own tests,
linters and typechecks.

Native hooks only advise: none blocks a tool or interprets a shell command.
Each host manifest selects its registration under `adapters/`; native payloads
reach the normalized handler in `hooks/advise.py`. At startup, resume and
compaction, `status --current` identifies plans by path and shows their next
actions. The main checkout shows approved plans awaiting a separate start
instruction and ongoing runs. A linked worktree shows its own run. After an edit
of a compiled plan's rendered or state file, the hook names the `pipeline.py`
command that makes the change. In Claude Code the hooks run once the plugin is enabled. In Codex you
trust them, and again after every plugin update. Untrusted or off, they change
no run: only the advice is lost. Qoder uses its own `QODER_PLUGIN_ROOT`
registration. Host permissions and trust remain the user’s decision.

## The project's side

The plugin reads the project's shared `AGENTS.md` and its style skills
as the bar for the build and the review: the plan names the skills each
phase's code follows, the project's and the global ones that fit the work.
It reads one block in that file for the commands a plan's Checks names:

```markdown
## Environment

**Tests.** `npm test`
**Lint.** `npm run lint`
**Dev server.** `npm run dev`, serves on `http://localhost:5173`
**Runtime.** a browser
**Access.** a test account without a one-time code, its password in `.env.local`
```

The full format is in
[environment-contract.md](skills/plan/references/environment-contract.md).
`AGENTS.md` serves both hosts: Codex reads it, and Claude Code reads it where
the project has no `CLAUDE.md`, or one that imports it with `@AGENTS.md`.

## Install

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

Then start a new session, and name a skill with `$`: `$dev-skills:grill`,
`$dev-skills:build <plan>`, `$dev-skills:land`, `$dev-skills:finish`. Codex's own `/plan` is not
this plugin's. To update, `codex plugin marketplace upgrade dev-skills`, then
`codex plugin add dev-skills@dev-skills` again. In the default
`workspace-write` sandbox `.git` is read-only, so the first `git add` and
`git commit` of a build ask for approval; approve each kind once.

In Qoder CLI, load the complete checkout for local testing:

```sh
qodercli --plugin-dir /absolute/path/to/dev-skills --add-dir /absolute/path/to/dev-skills
```

For a native installation, use `qodercli plugin install /absolute/path/to/dev-skills`
and start a new session. The package’s `.qoder-plugin/plugin.json` names the same
skills and three role sources. Use the native names `dev-skills:implementer`,
`dev-skills:reviewer` and `dev-skills:judge`; pass the approved model and optional
effort explicitly. `--add-dir` grants the selected session access to package
resources outside the target cwd; loading metadata alone does not grant tool
access. Honor any remaining native permission prompt. A loader inventory alone
does not establish role execution.

The repository is a marketplace holding exactly one plugin, itself:
[`.claude-plugin/`](.claude-plugin/marketplace.json) for Claude Code,
[`.agents/plugins/marketplace.json`](.agents/plugins/marketplace.json) and
[`.codex-plugin/plugin.json`](.codex-plugin/plugin.json) for Codex;
[`.qoder-plugin/plugin.json`](.qoder-plugin/plugin.json) is Qoder’s native manifest.
Keep the complete repository layout when installing: skills read sibling roles,
references and the CLI. Project `AGENTS.md`, worktrees and workflow artifacts
stay in the target project. Native version and loaded revision must be checked
separately. [Adapter contracts and host limits](adapters/README.md) describe coverage.

## Every skill

| Skill | For |
|---|---|
| [`browser-test`](skills/browser-test/SKILL.md) | the web e2e tool: the use cases as one Playwright scenario in a visible tab you can watch, single commands to dig in; a web app or an Electron build over CDP |
| [`bug`](skills/bug/SKILL.md) | reproduce a bug and pin down its cause before the plan |
| [`build`](skills/build/SKILL.md) | run a plan: the graph, the E2E gate, the judge, the human gate |
| [`commit-work`](skills/commit-work/SKILL.md) | stage by path, split into logical commits, write the message |
| [`domain-modeling`](skills/domain-modeling/SKILL.md) | the glossary in `CONTEXT.md`, and an ADR for a decision that needs one |
| [`epic`](skills/epic/SKILL.md) | shared decisions and the ordered list of plans |
| [`finish`](skills/finish/SKILL.md) | merge a passed plan, on the user's word |
| [`grill`](skills/grill/SKILL.md) | talk an idea into a shared understanding |
| [`handoff`](skills/handoff/SKILL.md) | pack this session for a fresh context |
| [`land`](skills/land/SKILL.md) | rewrite a plan's branch into reviewable commits, run by the judge |
| [`plan`](skills/plan/SKILL.md) | write the one-screen plan |
| [`prototype`](skills/prototype/SKILL.md) | answer a design question with throwaway code |
| [`retro`](skills/retro/SKILL.md) | propose environment changes after a plan, each with what it removes |
| [`review`](skills/review/SKILL.md) | the code half of the E2E gate, or a review of any range |
| [`run-file`](skills/run-file/SKILL.md) | what the run may do, its checks and how it ends, asked once before the plan |
| [`spec`](skills/spec/SKILL.md) | the project's rules in `docs/spec/`: the pipeline's grill, plan and build call it; alone, write one task's rules built outside the pipeline, list and show them |
| [`tdd`](skills/tdd/SKILL.md) | red before green, read by the implementer |
| [`verify`](skills/verify/SKILL.md) | the e2e half of the E2E gate: drive the Done use cases |
| [`writing-skills`](skills/writing-skills/SKILL.md) | design or audit a skill |

[`references/VOCABULARY.md`](references/VOCABULARY.md) defines the words they
share.

## Principles

- A stage stays only if it saves more time than it takes.
- The skills do not restrict the models or make them work one step after
  another without a reason.
- Where the work could go two ways, the user chooses, not the agent. During
  implementation the build session chooses from the agreed plan and the human gate shows
  each choice; an irreversible one waits for the authorized contact.

## Checking this repository

`scripts/check` runs shared resource checks: links, `dev-skills:` names,
retired names, frontmatter and [word budgets](scripts/word-budgets.txt).
It requires Python 3.11+ and calls no AI client. Select native checks explicitly:

```sh
scripts/check --host claude --host codex --host qoder
```

Each selected adapter names the actual native version and evidence scope.
Claude validates manifests; Codex installs into a temporary home and reads the
model-visible skills; Qoder validates its manifest and inventories loaded
skills, roles and hooks. None of those checks calls a model or certifies live
role execution. Missing or failed selected checks fail. Nonselected hosts are
outside that run’s coverage.

`scripts/test` runs offline behavioural tests with Bash, Python 3.11+, Node,
Git and standard shell tools; installed AI clients are unnecessary. Native
adapter tests use executable fixtures. One file is `scripts/test <path>`.
Relocation fixtures check complete resources, executable modes, target-project
profiles and each declared advisory launcher; they are fixture coverage.

`scripts/usage --source claude` or `scripts/usage --source codex` reports wall
and active hours, human messages, tokens and descendants. The source is required;
unknown sources fail. Readers own native transcript roots: `~/.claude/projects`
and `$CODEX_HOME/sessions` (default `~/.codex/sessions`), respectively; `--root DIR`
overrides them. `--json`, `--project` and `--since` select session output, project
and start date. Codex uses the initial cwd, cumulative token snapshots without
adding cached input again, and separate descendant totals. Forks exclude inherited
history where an ordinal is available. Missing snapshots report zero observed
usage; orphan children are omitted. Codex skill counts are not inferred, and
encrypted messages or tool arguments are not recovered. No Qoder transcript
reader is claimed. [Adapter interfaces](adapters/README.md) remain open to explicit
additional validators and readers without a common host catalogue.

Working on this repository with the installed plugin also active runs the
pipeline twice; turn it off first: `claude --settings
'{"enabledPlugins":{"dev-skills@dev-skills":false}}'`, or in Codex
`codex -c 'plugins.dev-skills@dev-skills.enabled=false'`.

## Licence

MIT — see [LICENSE](LICENSE).

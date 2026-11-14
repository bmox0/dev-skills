# dev-skills

A plugin for Claude Code and Codex: skills and three agents for building a
change — discussion, a plan file, implementation by subagents, a review and an
e2e check, and your approval before merge. The session you start coordinates
the work and does not edit code.

## The pipeline

Every change goes through the same seven stages. For a small task each stage
is shorter; none is skipped, and every plan ends in a human gate.

1. **Entry.** A grill when it is unclear what is being built, a discussion when
   it is lighter. Workers bring facts from the code; you make the decisions.
   A bug adds its reproduction and its cause. A second Sonnet worker, the spec
   scout, brings the rules in `docs/spec/` that the task touches; you are asked
   about a rule only when the task leaves open whether it stays true, in product
   words, and the plan's writer records it.
2. **Prototype.** Offered after the entry; you pick the shape or decline: an
   HTML file, inside the app with real data, or code. A worker draws it.
3. **Plan.** Always a file, one screen: Result, Approach, Out of scope, Phases,
   Checks, Done, `## Spec` (the rules added, changed, removed) and the prototype's
   link, in the language named by the `Language` line of your `AGENTS.md`; `spec.py check` runs before you see it. Each phase names its territory, the
   skills its code follows, the spec files it reads, and what it waits for; territories and waits form
   the graph. Status runs `draft` →
   `approved` → `building` → `at the human gate` → `passed` → `merged`, via
   `a merge-request link` when finish opens one. The plan session sets
   `approved` itself and starts the build at once, unless the session's brief
   names a command to run first.
4. **Build.** One branch and one working tree per plan: this one, or a
   worktree when another plan is building here. Every phase whose
   dependencies are met starts at once, as an implementer that writes only
   inside its territory and runs the project's checks on it. Before the gate and
   each re-check, `spec.py write` runs and `docs/spec/` is committed alone.
5. **The E2E gate.** At the level the plan names, small or normal: the
   full checks, then at once a fresh review against the project's rules (and the `Spec:` areas' rules) and
   e2e over what you would not see by trying the app, at each width the plan
   names. Defects and failures make one list for one new implementer, then a
   targeted re-check; two fixes at most. Then a judge, a fresh Opus context: it
   re-runs nothing, decides every open entry and every Convention (let
   through, one round with a cause, or a question to you), writes its
   prediction of your verdict, and lands the branch: the working commits
   become the ones a reviewer reads, one or a few by meaning, on the same tree;
   a backup branch keeps the old ones.
6. **The human gate.** One page: what was decided without you, what is still
   open with the judge's report, the e2e (the use cases, each with its last
   result and the commit it ran on; the ones marked "you check" are yours),
   and the landed commits, each with a walkthrough. You try the running app
   and read the commits in one sitting. Each note you make gets a cause from
   seven and is matched against the judge's prediction; a note that changes
   the approach is listed as a task, not built. A round runs on your word,
   then the judge again (it lands) and back to the gate.
7. **Finish.** On your word at the gate ("ок, в МР"), typed or plain. It asks
   for what you did not say: a merge request, or local with `--no-ff` or
   `--ff-only`, and the message. After the merge it offers to delete the
   plan's backups; the branch stays.

The drawing: [docs/pipeline.html](docs/pipeline.html).

## What you type

| You type | It does |
|---|---|
| [`grill`](skills/grill/SKILL.md), or just talk | reach a shared understanding; then a prototype is offered, then the plan |
| [`bug`](skills/bug/SKILL.md) | a worker reproduces it and brings the cause; the red test becomes phase 1 |
| [`prototype`](skills/prototype/SKILL.md) | a throwaway answer to a design question, drawn by a worker |
| [`epic`](skills/epic/SKILL.md) | several plans in order, only when you say so |
| [`plan`](skills/plan/SKILL.md) | the one-screen plan and its graph |
| [`build <plan>`](skills/build/SKILL.md) | the branch, the implementers, the E2E gate, the judge, the human gate |
| [`land`](skills/land/SKILL.md) | the commits a reviewer reads; the judge runs it |
| [`finish`](skills/finish/SKILL.md) | on your word at the gate, merge it: a merge request, or local with `--no-ff` or `--ff-only` |

A small task is built by the session that discussed it; anything bigger by a
new session started from the plan file. The build starts when the plan is
written, with no "go".

## Who does what

- **You** decide, and say at the gate whether it passes. A prototype, an epic, how to
  finish and a retro are your call.
- **The orchestrator** is the model you started with, from the first pipeline
  skill you enter. It talks, writes the plan, runs the graph, relays messages
  and sorts findings. During a build it answers product questions itself,
  except an irreversible one, and shows each answer at the human gate. It never
  edits code.
- **Implementers** are the [`implementer`](agents/implementer.md) agent: Sonnet,
  a clean context each, handed the whole plan, its phase, and what earlier
  phases reported. When the plan and the code disagree, it rules, carries on,
  and records the ruling with its cost if wrong.
- **Workers** are Sonnet subagents for side jobs: facts from the code, the
  rules the task touches (the spec scout), a prototype, the full checks, e2e.
- **The reviewer** is the [`reviewer`](agents/reviewer.md) agent: Opus for the
  first review of a plan's branch and for a range you name, Sonnet for the
  re-check and every later round.
- **The judge** is the [`judge`](agents/judge.md) agent: Opus, a fresh context
  after the E2E gate. It decides what the results mean for you, writes its
  prediction of your verdict, and runs `land`.

In Codex the same roles are Codex subagents on the session's model, at
reasoning effort `high` where Claude Code uses Sonnet and `xhigh` for the first
review and the judge. The skills name Claude Code's tools;
[`references/CODEX.md`](references/CODEX.md) says what each one is in Codex.

The plugin ships no hooks. The pipeline lives in the skills' text, with
two tools beside it: `skills/spec/spec.py` and `skills/browser-test/tab.mjs`; the level-1 checks are the project's own tests, linters and typechecks.

## The project's side

The plugin reads the project's `AGENTS.md` or `CLAUDE.md` and its style skills
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

Then restart the session. Installing also brings the agents `implementer` and
`reviewer`.

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

The repository is a marketplace holding exactly one plugin, itself:
[`.claude-plugin/`](.claude-plugin/marketplace.json) for Claude Code,
[`.agents/plugins/marketplace.json`](.agents/plugins/marketplace.json) and
[`.codex-plugin/plugin.json`](.codex-plugin/plugin.json) for Codex. Both hosts
install the same skills.

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
- Where the work could go two ways, the user chooses, not the agent. During a
  build the orchestrator chooses and the human gate shows each choice; an
  irreversible one waits for the user.

## Checking this repository

`scripts/check` asks whether the tree is sound: every link resolves, every
`dev-skills:` name exists, no retired name comes back, every markdown file is
within its budget in [`scripts/word-budgets.txt`](scripts/word-budgets.txt),
and the manifests and every frontmatter parse (`claude plugin validate`).
It also installs the plugin into a throwaway Codex home and reads back the
skills Codex shows its model: all of them
([`scripts/check-codex.py`](scripts/check-codex.py)).

`scripts/test` runs the behavioural tests on the maintainer scripts and the
plugin's shape — TC-13 pins the shape itself (no hooks, no `scripts/` under `skills/`,
Sonnet implementers, an Opus reviewer and judge, one version in every manifest), TC-14 pins the plan's statuses across `plan`, `build`,
`finish`, `epic` and the implementer; one file is `scripts/test <path>`.

`scripts/usage` measures sessions from Claude Code's transcripts: wall and
active hours, human messages, tokens, subagents, per project or per session
(`--json`, `--project`, `--since`).

Working on this repository with the installed plugin also active runs the
pipeline twice; turn it off first: `claude --settings
'{"enabledPlugins":{"dev-skills@dev-skills":false}}'`, or in Codex
`codex -c 'plugins.dev-skills@dev-skills.enabled=false'`.

## Licence

MIT — see [LICENSE](LICENSE).

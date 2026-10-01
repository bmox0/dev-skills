# dev-skills

A Claude Code plugin of skills and two agents for building a change:
discussion, a plan file, implementation by Sonnet subagents, a review and an
e2e check, and your approval before merge. The session you start coordinates
the work and does not edit code.

## The pipeline

Every change goes through the same seven stages. For a small task each stage
is shorter; none is skipped, and every plan ends in a human gate.

1. **Entry.** A grill when it is unclear what is being built, a discussion when
   it is lighter. Workers bring facts from the code; you make the decisions.
   A bug adds its reproduction and its cause.
2. **Prototype.** Offered after the entry; you pick the shape or decline: an
   HTML file, inside the app with real data, or code. A worker draws it.
3. **Plan.** Always a file, one screen: Result, Approach, Out of scope, Phases,
   Checks, Done, and the prototype's link. Each phase names its territory and
   what it waits for; together they form the graph. Status runs `draft` →
   `approved` → `building` → `at the human gate` → `passed` → `landed`, via
   `a merge-request link` when finish opens one; your "go" takes it from
   draft to approved.
4. **Build.** One branch per plan, one working tree. Every phase whose
   dependencies are met starts at once, as an implementer that writes only
   inside its territory and runs the project's checks on it.
5. **The E2E gate.** The full checks, then at once a fresh review against the
   project's rules and e2e over the plan's Done use cases. Their findings make
   one list for one new implementer, then a targeted re-check. One pass.
6. **The human gate.** One page: the code (the branch against its base, a
   walkthrough, the rulings the implementers made alone) and the e2e (the use
   cases with the machine's results), written into the plan. It approves; it does
   not test.
7. **Finish.** You type it. It asks: a merge request or local, squash or
   `--no-ff`.

The drawing: [docs/pipeline.html](docs/pipeline.html).

## What you type

| You type | It does |
|---|---|
| [`grill`](skills/grill/SKILL.md), or just talk | reach a shared understanding; then a prototype is offered, then the plan |
| [`bug`](skills/bug/SKILL.md) | a worker reproduces it and brings the cause; the red test becomes phase 1 |
| [`prototype`](skills/prototype/SKILL.md) | a throwaway answer to a design question, drawn by a worker |
| [`epic`](skills/epic/SKILL.md) | several plans in order, only when you say so |
| [`plan`](skills/plan/SKILL.md) | the one-screen plan and its graph |
| [`build <plan>`](skills/build/SKILL.md) | the branch, the implementers, the E2E gate, the human gate |
| [`finish`](skills/finish/SKILL.md) | land it: a merge request or local, squash or `--no-ff` |

A small task is built by the session that discussed it; anything bigger by a
new session started from the plan file. `finish` is the only skill the model
cannot start.

## Who does what

- **You** decide, approve, and type `finish`. A prototype, an epic, where to
  build, how to finish and a retro are your call.
- **The orchestrator** is the model you started with, from the first pipeline
  skill you enter. It talks, writes the plan, runs the graph, relays messages
  and sorts findings. It never edits code.
- **Implementers** are the [`implementer`](agents/implementer.md) agent: Sonnet,
  a clean context each, handed the whole plan, its phase, and what earlier
  phases reported. When the plan and the code disagree, it rules, carries on,
  and records the ruling with its cost if wrong.
- **Workers** are Sonnet subagents for side jobs: facts from the code, a
  prototype, the full checks, e2e.
- **The reviewer** is the [`reviewer`](agents/reviewer.md) agent: Opus for the
  first review of a plan's branch and for a range you name, Sonnet for the
  re-check and every later round.

The plugin ships no hooks and no scripts. The pipeline lives in the skills'
text; the level-1 checks are the project's own tests, linters and typechecks.

## The project's side

The plugin reads the project's `CLAUDE.md` and style skills as the bar for
review, and one block in `CLAUDE.md` for the commands a plan's Checks names:

```markdown
## Environment

**Tests.** `npm test`
**Lint.** `npm run lint`
**Dev server.** `npm run dev`, serves on `http://localhost:5173`
**Runtime.** a browser
```

The full format is in
[environment-contract.md](skills/plan/references/environment-contract.md).

## Install

```
/plugin marketplace add bmox0/dev-skills
/plugin install dev-skills@dev-skills
```

Then restart the session. The repository carries its own
[`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json), so it is a
marketplace holding exactly one plugin, itself. Installing also brings the
agents `implementer` and `reviewer`.

## Every skill

| Skill | For |
|---|---|
| [`browser-test`](skills/browser-test/SKILL.md) | drive a web app or an Electron build over CDP; the web e2e tool, used instead of a browser MCP server or Playwright scripts because tests showed it costs fewer tokens |
| [`bug`](skills/bug/SKILL.md) | reproduce a bug and pin down its cause before the plan |
| [`build`](skills/build/SKILL.md) | run a plan: the graph, the E2E gate, the human gate |
| [`commit-work`](skills/commit-work/SKILL.md) | stage by path, split into logical commits, write the message |
| [`domain-modeling`](skills/domain-modeling/SKILL.md) | the glossary in `CONTEXT.md`, and an ADR for a decision that needs one |
| [`epic`](skills/epic/SKILL.md) | shared decisions and the ordered list of plans |
| [`finish`](skills/finish/SKILL.md) | land a passed plan, typed by the user |
| [`grill`](skills/grill/SKILL.md) | talk an idea into a shared understanding |
| [`handoff`](skills/handoff/SKILL.md) | pack this session for a fresh context |
| [`plan`](skills/plan/SKILL.md) | write the one-screen plan |
| [`prototype`](skills/prototype/SKILL.md) | answer a design question with throwaway code |
| [`retro`](skills/retro/SKILL.md) | propose environment changes after a plan, each with what it removes |
| [`review`](skills/review/SKILL.md) | the code half of the E2E gate, or a review of any range |
| [`tdd`](skills/tdd/SKILL.md) | red before green, read by the implementer |
| [`verify`](skills/verify/SKILL.md) | the e2e half of the E2E gate: drive the Done use cases |
| [`writing-skills`](skills/writing-skills/SKILL.md) | design or audit a skill |

[`references/VOCABULARY.md`](references/VOCABULARY.md) defines the words they
share.

## Principles

- A stage stays only if it saves more time than it takes.
- The skills do not restrict the models or make them work one step after
  another without a reason.
- Where the work could go two ways, the user chooses, not the agent.

## Checking this repository

`scripts/check` asks whether the tree is sound: every link resolves, every
`dev-skills:` name exists, no retired name comes back, every markdown file is
within its budget in [`scripts/word-budgets.txt`](scripts/word-budgets.txt),
and the manifests and every frontmatter parse (`claude plugin validate`).

`scripts/test` runs the behavioural tests on the maintainer scripts and the
plugin's shape — TC-13 pins the shape itself (no hooks, no skill scripts,
Sonnet implementers, an Opus reviewer), TC-14 pins the plan's statuses across `plan`, `build`,
`finish`, `epic` and the implementer; one file is `scripts/test <path>`.

`scripts/usage` measures sessions from Claude Code's transcripts: wall and
active hours, human messages, tokens, subagents, per project or per session
(`--json`, `--project`, `--since`).

Working on this repository with the installed plugin also active runs the
pipeline twice; turn it off first: `claude --settings
'{"enabledPlugins":{"dev-skills@dev-skills":false}}'`.

## Licence

MIT — see [LICENSE](LICENSE).

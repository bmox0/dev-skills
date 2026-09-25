# dev-skills

A Claude Code plugin for building software with an agent. It keeps a few
things true on every task, whatever its size, and offers a handful of entries
for when a task needs more than a session and a todo.

What is always true:

- **Work happens on its own branch or worktree**, cut before the first edit.
  The default branch changes only through a merge the user asks for.
- **Every step is a green commit**, and git is the state: there is no run, no
  marker and no ledger to keep in sync.
- **Changed behaviour is driven on the running system** before it is called
  done, looks included, on screenshots and frames.
- **A built unit gets a fresh review**, bounded to two fix rounds, never
  "until clean".
- **The user is asked at four points and nowhere else**: grill decisions, the
  three lines under a new brief, a question the brief and epic do not answer,
  and the merge.
- **The plugin stays small**: every skill has a word budget that
  `scripts/check` enforces.

## How work goes

**A small task.** A branch, a todo, edits under the project's rules, checks
green, a commit. If behaviour changed, drive it and say what was seen. Merge
on the user's word.

**A one-session feature.** [`grill`](skills/grill/SKILL.md) when "done" is
not yet clear, a [`prototype`](skills/prototype/SKILL.md) when the question is
visual, then build it here on `feat/<topic>` with a commit per step.
[`review`](skills/review/SKILL.md) the range if it has logic,
[`verify`](skills/verify/SKILL.md) the scenarios the grill settled, and
[`finish`](skills/finish/SKILL.md) on the user's word.

**Work that leaves this context.** [`plan`](skills/plan/SKILL.md) writes a
brief; [`implement <brief>`](skills/implement/SKILL.md) builds it in another
seat, then review and verify follow. More than one unit goes under an
[`epic`](skills/epic/SKILL.md), whose queue says what blocks what; a project
can mirror it to its tracker.

**A bug.** [`bug`](skills/bug/SKILL.md): one command that goes red, the root
cause named, the fix and its pinning test in the same context, driven, and
committed as `fix(...)`. A brief only when the cause is a design flaw.

## The acts

Each act is a command of its own, usable on any branch or range. The seat, the
session, a subagent, a tab or the user, is whoever holds the tools.

| Act | Does | Returns |
|---|---|---|
| [`implement`](skills/implement/SKILL.md) | builds a brief's steps: one commit per step, three stop triggers, park and continue | commits and an inline report |
| [`review`](skills/review/SKILL.md) | reads a range from a fresh, read-only context | Defects, Conventions, Observations |
| [`verify`](skills/verify/SKILL.md) | drives the Acceptance on the running system | one evidence file per scenario |
| [`finish`](skills/finish/SKILL.md) | squashes by meaning and merges `--no-ff` locally | a merge summary |

`finish` is the only skill the model cannot start: the user types `/finish`,
or an orchestrator does under a delegation that names merging.

## What is always on

- **`git-guard`**, one stateless hook on every Bash call. It refuses blanket
  staging and `commit -a`, a subject that is not Conventional Commits or runs
  past 72 characters, a body past 300, attribution trailers, `reset --hard`,
  `clean -f`, `checkout .`, `restore .`, `branch -D`, a force push to the
  default branch, and a commit on the default branch. It reads the command the
  way the shell does, so text in a heredoc or a quoted string is never taken
  for a git command, and it fails open.
- **The session rule**, injected at start by [`bootstrap`](skills/bootstrap/SKILL.md).
- **Prototypes open themselves**: a file written under `.ai-workflow/prototypes/`
  opens in the browser (`open`, `xdg-open`, or `DEV_SKILLS_OPEN_CMD`).

## The project's side

The plugin reads the project's `CLAUDE.md` and style skills as the bar, and
one block in `CLAUDE.md` for how the project runs:

```markdown
## Environment

**Tests.** `npm test`
**Dev server.** `npm run dev`, serves on `http://localhost:5173`
**bootstrap.** `npm ci`
**link.** `.env*`
**Tracker.** Daily
```

`bootstrap` and `link` prepare a fresh worktree. `Tracker` names where an
epic's units are mirrored. A project that commits straight to its default
branch adds `**main.** direct`. The full format is in
[environment-contract.md](skills/implement/references/environment-contract.md).

## Install

```
/plugin marketplace add bmox0/dev-skills
/plugin install dev-skills@dev-skills
```

Then restart the session. The repository carries its own
[`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json), so it is a
marketplace holding exactly one plugin — itself. Installing also brings the
seat agents `builder` and `reviewer` and the hooks in
[`hooks/hooks.json`](hooks/hooks.json).

## Every skill

| Skill | For |
|---|---|
| [`bootstrap`](skills/bootstrap/SKILL.md) | the session rule, injected at start |
| [`browser-test`](skills/browser-test/SKILL.md) | drive a web app or an Electron build over CDP; the web tester's tool |
| [`bug`](skills/bug/SKILL.md) | reproduce, find the root cause, fix and pin it |
| [`commit-work`](skills/commit-work/SKILL.md) | stage by path, split into logical commits, write the message |
| [`domain-modeling`](skills/domain-modeling/SKILL.md) | the glossary in `CONTEXT.md`, and an ADR when one is earned |
| [`epic`](skills/epic/SKILL.md) | the decisions and the queue for more than one unit |
| [`finish`](skills/finish/SKILL.md) | squash by meaning and merge, typed by the user |
| [`grill`](skills/grill/SKILL.md) | talk an idea into a shared understanding, ending in a size call |
| [`handoff`](skills/handoff/SKILL.md) | pack this session for a fresh context |
| [`implement`](skills/implement/SKILL.md) | build a unit from a brief |
| [`plan`](skills/plan/SKILL.md) | write the brief |
| [`prototype`](skills/prototype/SKILL.md) | answer a design question with throwaway code |
| [`retro`](skills/retro/SKILL.md) | propose environment changes after a unit, each with what it removes |
| [`review`](skills/review/SKILL.md) | a fresh, read-only review of a range |
| [`tdd`](skills/tdd/SKILL.md) | red before green, read by the builder |
| [`verify`](skills/verify/SKILL.md) | drive the Acceptance, one evidence file per scenario |
| [`writing-great-skills`](skills/writing-great-skills/SKILL.md) | design or audit a skill |

[`references/VOCABULARY.md`](references/VOCABULARY.md) defines the words they
share.

## Why it looks like this

Version 3.0 was rebuilt from what had to stay true, after a month of real use
showed the process costing more than the work. The diagrams:
[before (2.7)](docs/pipeline-2.7.html), [a proposal that was not
taken](docs/pipeline-proposal.html), and [the shape that was built
(3.0)](docs/pipeline-3.0.html).

## Checking this repository

`scripts/check` asks whether the tree is sound: every link resolves, every
`dev-skills:` name exists, no retired name comes back, every markdown file is
within its budget in [`scripts/word-budgets.txt`](scripts/word-budgets.txt),
and the manifest and every `SKILL.md` frontmatter parse
(`claude plugin validate`).

`scripts/test` runs the behavioural tests on the scripts and hooks; one file is
`scripts/test <path>`.

`scripts/usage` measures sessions from Claude Code's transcripts: wall and
active hours, human messages, tokens, subagents, per project or per session
(`--json`, `--project`, `--since`).

## Licence

MIT — see [LICENSE](LICENSE).

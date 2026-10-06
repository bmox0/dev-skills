# Runtime

Read this before dispatching a role, invoking another skill, or reading a
project's rules. The workflow is shared; the host supplies its tools. Identify
Claude Code or Codex from the current environment, not the model's name.

## Roles and models

| Role | Claude Code | Codex model | Codex reasoning effort |
|---|---|---|---|
| Worker, implementer, targeted reviewer | Sonnet | Sol | high |
| Initial reviewer | Opus | Sol | xhigh |

An initial reviewer checks the plan's whole branch or a range the user names.
A targeted reviewer checks fixes and later rounds. Both use a fresh context.
The orchestrator remains the model the user started with.

In Codex, resolve Sol to the user's configured Sol preset when available, or
an available Sol identifier in the spawn tool's model list. Set both model and
reasoning effort explicitly. A user's explicit choice for a role overrides
the table. If the required model or effort is unavailable, report what cannot
run and ask for an alternative; never silently change the table or skip a gate.

## Dispatch and coordination

Only the orchestrator dispatches. An assigned child performs its role's steps
and returns its report; it does not become the orchestrator or delegate again.

Hand each child its role, task, plan path, territory, relevant prior reports,
and the result it must return. Children explore the repository themselves.
The two role instructions are [implementer](../agents/implementer.md) and
[reviewer](../agents/reviewer.md). Workers receive the side job's instructions.

**Claude Code.** Use the native Agent tool and the installed
`dev-skills:implementer` or `dev-skills:reviewer` agent. Select the table's model
when dispatching: targeted review overrides the reviewer's initial-review
default. Workers are general-purpose subagents. Route messages through the
orchestrator with the host's SendMessage tool and the actual recipient ID.

**Codex.** Use the available native subagent tools, such as `spawn_agent` under
`collaboration`. Pass the role's instructions in the task; these Markdown
files are not automatically registered as Codex TOML agents. Request an
isolated context (`fork_turns: "none"` when supported), rather than copying
the conversation. Use `send_message` for a running child, and `followup_task`
to resume an idle one; use the current host's equivalents if named differently.
Collect final reports with its mailbox or wait tool. Subagents serve the current
chat; creating a separate user-owned chat is only for a user-requested handoff.

Use the actual tool list. Start ready phases up to the available concurrency
limit; leave the others waiting. Release completed children when the host
requires it. With no subagent tools, report that build cannot dispatch; the
orchestrator does not take over implementation.

All phases use the plan's working tree. Coordinate Git writes one at a time:
grant a child its commit turn and release it after its report. Stage only its
paths. A locked index waits and is reported; never delete an unknown lock.

## Project rules and commands

**Claude Code:** read the project's applicable `CLAUDE.md` files and style
skills. **Codex:** read the applicable `AGENTS.md` files from the repository
root down to the phase's territory, respecting nested scope. Other written
rules, ADRs and `CONTEXT.md` still apply.

Take Checks from the applicable `## Environment` blocks. Inherit ancestor
commands unless a scoped block overrides them. With no applicable block, an
existing `CLAUDE.md` Environment block can supply commands in Codex; otherwise
discover them from manifests and scripts. Record the source in Checks. Offer a missing
block for the host's project instructions, as the
[environment contract](../skills/plan/references/environment-contract.md) says.

## Skills and package paths

`dev-skills:<name>` names a skill in this package. In Claude Code, use its
native Skill tool or `/dev-skills:<name>`. In Codex, match that name in the
available skill catalog and read its `SKILL.md` at the supplied path. A human
can select it through the skill picker or `$`; built-in slash commands such
as `/plan` are not this package's skills.

Keep `description` in every skill. `finish` is explicit-only: Claude uses
`disable-model-invocation: true`; Codex uses its
[invocation policy](../skills/finish/agents/openai.yaml). Neither setting
authorizes a merge or push; `finish` still requires the user's chosen outcome.
Claude's `user-invocable: false` hides `tdd` from its shortcut list; Codex can
still expose it, and implementers read it normally.

Resolve resources relative to the skill or role file that was loaded. Both
hosts install the same tree. Browser checks use the adjacent `tab.mjs`;
never guess a provider's cache directory or select another installed version.

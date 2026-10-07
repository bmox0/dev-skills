The skills and the two role files are written for Claude Code and name its
tools. In Codex they hold as written, read through this page.

## Subagents

A subagent, worker, implementer or reviewer is `spawn_agent` with
`fork_turns: "none"`: a clean context that starts from its task alone. Hand it
what the skill says to hand over; an implementer or a reviewer also gets its
role file by absolute path, to read first:
[implementer](../agents/implementer.md), [reviewer](../agents/reviewer.md). A
worker given a skill's steps, as `dev-skills:verify` gives them, gets that
`SKILL.md` by absolute path.

Leave `model` unset; the child keeps the session's model. The role files'
`model:` lines are Claude's; the reasoning effort stands in for them:

| The skills say | `reasoning_effort` |
|---|---|
| an implementer, a worker, the reviewer on Sonnet | `high` |
| `dev-skills:reviewer`, the first review of a range | `xhigh` |

All at once, in the background: spawn every ready one, up to the session's
concurrency slots; the rest start as slots free. Close a child with
`close_agent` once its report is in, where that tool exists, so its slot
returns.

`SendMessage` to a child is `send_message` to its task name while it runs,
and `followup_task` once it is idle (`send_input` and `resume_agent` on older
tools).

## A child

If your task name is not `/root`, you are a child, and you dispatch no one.
Where a skill says the session that asks dispatches someone to follow its
steps, you are that someone: follow them yourself.

`SendMessage` to `main` is `send_message` to `/root`. Without `send_message`,
end with the question in your report.

## Git

Under `workspace-write`, `.git` is read-only: `git add`, `git commit` and
cutting a branch need escalation. Request it with the prefix rule
`["git", "add"]` or `["git", "commit"]`, so the user approves each kind once.
A commit the user declines is not made; the report says so.

## Names

- `dev-skills:<name>` is that skill in Codex's skill list: read its
  `SKILL.md` and follow it. The user names one with `$`, as
  `$dev-skills:plan`; Codex's own `/plan` is not it.
- `/finish` is `$dev-skills:finish`. Codex never offers it to the model:
  [policy](../skills/finish/agents/openai.yaml).

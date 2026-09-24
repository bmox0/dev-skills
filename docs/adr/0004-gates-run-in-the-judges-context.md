---
status: proposed
---

# Gate A, gate B and the remediation loop run in a judge's own context

Measured on a full run: the orchestrator was **86%** of the bill, and two thirds
of that was one line — re-reading its own context, which had grown to ~382K
tokens across 451 turns. The eleven agents that wrote every line of production
code were 14%. What grew that context was findings and two remediation rounds
landing in the builder's conversation.

So `dev-skills:implement` builds, and hands the assembled range to a **judge**
that owns gate A, gate B *and* the remediation loop in a context of its own, and
returns a verdict rather than findings. The human still types only `implement`
and `finish`.

## Consequences

- A subagent granted the `Agent` tool can spawn subagents — probed live before
  this was decided. No agent in `agents/*.md` carries `Agent` in its `tools:`
  line today; the judge will.
- A **join** runs the tests and the checks, and gate A runs them again — but only
  when the SHA has moved, which after the last join it has not. No duplication.

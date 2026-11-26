# Optional Codex adapter

The shared workflow is [SESSIONS.md](SESSIONS.md), and project rules come from
`AGENTS.md`. This adapter changes only host mechanics, never presets or topology.

Preserve registered native roles; a generic worker needs the role-equivalence
verification in SESSIONS.md. For a clean native child use `spawn_agent` with
`fork_turns: "none"`, explicitly passing the selected model and reasoning effort when present. Read the
Executor headers in its brief; do not inherit the parent's model as a role
assignment. If that preset is unavailable, surface the limitation.

When available, use `send_message` while a child runs and `followup_task` when
idle; otherwise collect its actionable result/artifact per SESSIONS.md. A child
follows its assigned role itself and dispatches no further agents. Questions go to the recorded build writer.
Independent-session handoff follows the selected topology, not child naming.

Run `runweld plan` for planning instructions.

Honor the current sandbox and approval policy for git and other tools. Never
request escalation where that policy disables it. Report a denied required
action instead of pretending it succeeded.

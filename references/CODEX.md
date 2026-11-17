# Optional Codex adapter

The shared workflow is [SESSIONS.md](SESSIONS.md), and project rules come from
`AGENTS.md`. This adapter changes only host mechanics, never presets or topology.

For a clean native child use `spawn_agent` with `fork_turns: "none"`, explicitly
passing the selected model and reasoning effort when present. Read the
Executor headers in its brief; do not inherit the parent's model as a role
assignment. If that preset is unavailable, surface the limitation.

Use `send_message` while a child runs and `followup_task` when idle; older
hosts may expose equivalent tools. A child follows its assigned role itself
and dispatches no further agents. Questions go to the recorded build writer.
Independent-session handoff follows the selected topology, not child naming.

`dev-skills:<name>` means read that skill's `SKILL.md`. Users can name it with
`$dev-skills:plan`; the host's own `/plan` is separate.

Honor the current sandbox and approval policy for git and other tools. Never
request escalation where that policy disables it. Report a denied required
action instead of pretending it succeeded.

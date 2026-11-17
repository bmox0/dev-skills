# Original and build sessions

The original conversation remains the user’s orchestrator. Compilation alone
launches nothing. On the user’s start instruction, including one already given,
it starts an independent build session in a **new herdr tab in the same
workspace**, for every build. Do not ask current versus new. Native phase
agents keep their roles; a build session already handed this plan executes
`dev-skills:build` without opening another build tab.

## Start once

Read the installed herdr skill and `herdr --skill`; check command help where
needed. Use the CLI’s current flags, not a helper that defaults to Claude.
Before creating anything, look for the existing build session recorded beside
the plan. On resume, inspect and watch that session; do not launch a duplicate
or take over its pipeline writes. If it exited, report that before restarting.

Write a brief beside the plan with absolute plan, run-file and local build
`SKILL.md` paths, verified decisions, working tree, same host, and original
workspace/tab/pane as the return destination. Say that this is the build root,
that its native agents report to it, and that it must report questions and the
human gate back, then wait for relayed user instructions.

Create the tab, keeping the user’s focus:

```sh
herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$PWD" --label "Build" --no-focus
```

Read the tab ID and root pane ID from `.result.tab` and `.result.root_pane`.
Start the **same host** in that pane: `--kind codex` for Codex, `--kind claude`
for Claude Code; choose a unique live name. For Codex:

```sh
herdr agent start <name> --kind codex --pane <root-pane-id>
herdr agent prompt <name> "Read <absolute-brief-path> and execute the local build skill." --wait --timeout 60000
```

Keep the returned IDs, agent name, host and brief path beside the plan so a
resumed original can find them. A fresh root can dispatch its native phase
agents; it is not a native child. The build session owns pipeline transitions,
including notes, rounds, approval and finish; native roles keep their existing
reporting commands. The original never writes pipeline state after handoff.

## Watch and relay

Run settled-state waits in the background; let completion wake the original
session. `herdr agent wait <name> --timeout 60000` matches idle, done or blocked;
read `herdr agent get <name>` and
`herdr agent read <name> --source recent-unwrapped --lines 120` afterward.
While working, use `--source visible` if history is unavailable. Read the
response: a settled state alone does not mean the build reached its gate.

A timeout, stalled prompt or unknown state is not completion or proof of failed
submission. Inspect before retrying. Never blindly resend. A blocked state
needs its actual question or permission prompt read and surfaced; answer only
from existing authorization or the user’s answer. Handle routine questions
from the agreed plan and relay the answer; bring unresolved product calls to
the user. Do not silently approve permissions or a human gate.

At the human gate, the build session reports the plan’s gate page, concrete
app or artifact location, how to try it, checks and limits, and waits. The
original alerts the user and opens that review location. It never approves
its own result.

Relay the user’s notes, round requests and approval **unchanged** to the same
build session. Send only when it is settled and inspected; retain incoming
words while it works. Notes alone do not start a round. The build session
records them and advances through the existing CLI only on the user’s word.
Continue watching through rounds and finish; never start a second build for
feedback or write duplicate state from the original.

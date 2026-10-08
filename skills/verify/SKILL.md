---
name: verify
description: Drive a plan's Done use cases on the running system — a browser, the simulator, curl or a CLI, as the plan's Checks says — and return each one's result with a capture. The e2e half of the E2E gate; also when the user asks to verify a branch.
---

# Verify

In Codex, read [CODEX.md](../../references/CODEX.md) first.

The session that asks for e2e dispatches a worker, a fresh Sonnet subagent
each run, that follows the steps below, and reads only its lines. It drives
what the user will see at the human gate.

**Receives:** the plan's Done use cases, or the ones the user names; how e2e
drives the system and where it runs (the plan's Checks, the project's
`AGENTS.md` or `CLAUDE.md`); the prototype when the plan links one.

1. **Find the running system.** If the user's dev instance of the tree you were
   handed is up, use it; never start a second one or restart theirs. If none
   is up, start it as the project says, on a port of its own in a worktree, and
   stop it when done. The project's Environment block, its Access and Devices
   lines included, is all you set up: what it does not cover is
   `not reached: needs <what>`.
2. **Drive each use case** as a user would: a web app through
   `dev-skills:browser-test`, all of them as one scenario in the window the
   user watches; iOS through the simulator's MCP server, a backend with curl, a
   CLI by running it. A click only a script gets through is failed. One
   device, one theme, one size, unless the plan's Checks names more.
3. **Check looks on captures:** a screenshot for each state whose appearance
   matters, frames for anything that moves, compared with the prototype.
   "Visible" is a look: text in the DOM is not one, nor are sampled pixels.

**Returns** one line per use case, failures first:

```text
<n>. <do this> → <see that> — passed | failed: <what was seen> | not reached: <why> — <capture path, or the command's output>
```

Once. After a fix, drive only the use cases that failed or were not reached.

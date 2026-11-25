---
name: verify
description: Drive a plan's Done use cases on the running system — a browser, the simulator, curl or a CLI, as the plan's Checks says — and return each one's result with a capture. The e2e half of the E2E gate; also when the user asks to verify a branch.
---

# Verify

Read shared `AGENTS.md` and the executor contract:
[SESSIONS.md](../../references/SESSIONS.md).

Coordinators dispatch a fresh secondary worker. The assigned worker drives
the cases from the brief and records their results.

**Receives:** the plan's Done use cases, or the ones the user names; how e2e
drives the system and where it runs (the plan's Checks and `CLI run show PLAN`
using the brief; without a plan, `AGENTS.md`); the prototype when linked.

1. **Find the running system.** If the user's dev instance of the tree is
   up, use it; never start a second or restart theirs. If none, start it with the run file's `dev`, on the port and data directory `run show`
   gives, and stop it when done. The run file's `[run]` keys and `[checks]` are
   all you set up. A login, a secret or a permission comes only from them, never
   the code or a `.env`; without one: `not reached: needs <what>`. A case the
   code itself keeps from being reached is `failed`, not `not reached`.
   Without a plan, the project's Environment block, Access and Devices
   included, is all you set up.
2. **Drive each use case** as a user would: a web app through
   `dev-skills:browser-test`, all of them as one scenario in the window the
   user watches; iOS through the simulator's MCP server, a backend with curl, a
   CLI by running it. A click only a script gets through is failed.
3. **Check looks on captures:** a screenshot of each state whose look matters, at
   every width the plan's Checks names, frames for anything that moves, compared with the prototype.
   "Visible" is a look: text in the DOM is not one, nor are sampled pixels.

**Returns** one line per use case, failures first:

```text
<n>. <do this> → <see that> — <width> — passed | failed: <what was seen> | not reached: <why> — <capture path, or the command's output>
```

Once. After a fix or round, drive the cases in the current brief. Use its
`result` command with the supplied cycle and commit. If the tree changed,
get the current brief and drive the case again. Return one line.

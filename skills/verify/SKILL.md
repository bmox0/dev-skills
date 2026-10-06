---
name: verify
description: Drive a plan's Done use cases on the running system — a browser, the simulator, curl or a CLI, as the plan's Checks says — and return each one's result with a capture. The e2e half of the E2E gate; also when the user asks to verify a branch.
---

# Verify

Read [RUNTIME.md](../../references/RUNTIME.md). The orchestrator dispatches a
fresh worker and reads its result. An assigned worker runs these steps
directly, without dispatching another child.

**Receives:** the plan's Done use cases, or the ones the user names; how e2e
drives the system and where it runs (the plan's Checks, the project's
Environment); the prototype when the plan links one.

1. **Find the running system.** If the user's dev instance is up, use it; never
   start a second one or restart theirs. If none is up, start it as the project
   says, and stop it when done.
2. **Drive each use case** as a user would: a web app through
   `dev-skills:browser-test`, all of them as one scenario in the window the
   user watches; iOS through the simulator's MCP server, a backend with curl, a
   CLI by running it. A click only a script gets through is failed.
3. **Check looks on captures:** a screenshot for each state whose appearance
   matters, frames for anything that moves, compared with the prototype.
   "Visible" is a look: text in the DOM is not one, nor are sampled pixels.

**Returns** one line per use case, failures first:

```text
<n>. <do this> → <see that> — passed | failed: <what was seen> | not reached: <why> — <capture path, or the command's output>
```

Once. After a fix, drive only the use cases that failed or were not reached.

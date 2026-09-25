---
name: verify
description: Drive a unit's Acceptance on the running system and write one evidence file per scenario, looks checked on captures. Use after review on a unit built from a brief, or when the user asks to verify a branch.
---

# Verify

The seat is whoever holds the tools to drive the system: this session with
`dev-skills:browser-test` on the web, a tab with the simulator's MCP server on
iOS, or the user. Take a seat only after you have seen it drive the system;
never assume a subagent holds the tools. When no seat you can reach holds them,
or the project's rules say the human tests (a manual simulator run before a
commit), hand the user the scenario list and record what they report.

**Receives:** the Acceptance (from the brief, or the scenarios the grill
settled), where the system runs (the `## Environment` block: dev server,
runtime), and the prototype or the looks list.

1. **Find the running system first.** If the user's dev instance is up, use it;
   do not start a second one or restart theirs. If the user is using the app
   right now, they are the tester: give them the list.
2. **Drive each scenario** as a user would, and note the actions, what you
   expected and what you saw.
3. **Check looks on captures:** a screenshot for each state on the looks list,
   frames for anything that moves, each compared with the prototype or the
   description. A verdict on looks needs a capture to show; sampled pixels are
   not one.
4. **Write one evidence file per scenario**, `.ai-workflow/verify/<unit>/<n>.md`:

```markdown
# <n>. <scenario>

Actions: <what was done, commands included>
Expected: <from the Acceptance>
Seen: <what happened, quoted where it is output>
Captures: <paths, or none>
Verdict: pass | fail | not reached — <why>
```

A scenario with no file was not checked. Write the file when the answer is
"could not reach it", with the reason.

**Once.** After fixes, drive only the affected scenarios again and update their
files.

**Returns:** the evidence files with their verdicts, failures first. A failure
goes back to the builder like a Defect.

Inline, with no brief: drive what changed and say what you saw; no files.

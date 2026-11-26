---
name: runweld
description: Use the installed runweld workflow when the user asks for Runweld, says "use runweld" or "используй runweld", or asks to continue a runweld task.
---

# Use Runweld

1. Run `runweld help agents` in the project. For a named run, use
   `runweld help agents --plan PLAN` with its absolute plan path. If runweld or its
   selected release is missing, report the install or recovery needed.
2. Read the session rules. Use `runweld status --current` to locate ongoing work or
   `runweld workflow` for new work, then read its stage instructions. With a role
   brief, use its source, protocol and exact commands.
3. Follow the CLI's next action for the requested task. A request to use runweld
   alone is not approval to create, start, accept or finish work.

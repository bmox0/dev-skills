---
name: ds-cli-skill
description: Use the installed ds workflow when the user asks for dev-skills, says "use ds" or "используй ds", or asks to continue a ds task.
---

# Use ds

1. Run `ds help agents` in the project. For a named run, use
   `ds help agents --plan PLAN` with its absolute plan path. If ds or its
   selected release is missing, report the install or recovery needed.
2. Read the session rules. Use `ds status --current` to locate ongoing work or
   `ds workflow` for new work, then read its stage instructions. With a role
   brief, use its source, protocol and exact commands.
3. Follow the CLI's next action for the requested task. A request to use ds
   alone is not approval to create, start, accept or finish work.

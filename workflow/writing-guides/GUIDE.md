---
name: writing-guides
description: Write instructions delivered by a Runweld CLI command.
---

# Write a command guide

Start with the decision, action or output the human needs from the command.
Write the steps in execution order. Give the actual `runweld` invocation
where a step calls another guide or changes task state.

Keep the guide in `workflow/NAME/GUIDE.md`. Put worked examples and detailed
procedures in its `references/` directory. A bare command prints the guide and
its bundled references. Describe when each optional procedure applies.

For a new command, register its name in `WORKFLOW_GUIDES`. For an input to
a workflow stage, declare its release-relative path in
[workflow.toml](../../references/workflow.toml) so the project lock records
which stages use it. Give each instruction file a word budget in
[scripts/word-budgets.txt](../../scripts/word-budgets.txt).

Test the installed command from a clean project. Its output should contain
the steps and examples an agent needs to do the work. Run `scripts/check`
and the installed CLI fixture before publishing.

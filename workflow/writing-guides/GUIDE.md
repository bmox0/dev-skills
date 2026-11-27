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

Register a new bare guide in `WORKFLOW_GUIDES`. For an input to
a workflow stage, declare its release-relative path in
[workflow.toml](../../references/workflow.toml) so the release records which
stages use it. Give each instruction file a word budget in
[scripts/word-budgets.txt](../../scripts/word-budgets.txt).

Terminal help is separate from the guide. Use the argument definitions in
[pipeline.py](../build/pipeline.py) for syntax and option summaries, and
[cli_help.py](../build/cli_help.py) for command descriptions and examples.
Say who can act, what is required, what is written, which defaults matter,
and how to verify success or recover. Show a command that ships. Use uppercase
placeholders for values the agent must get first. Group commands by the job
they do, not by implementation.

Test both `runweld help COMMAND` and `runweld COMMAND --help` in an installed
CLI. Run the examples in a disposable project and check the bare guide still
prints its instructions. Run `scripts/check` and the affected CLI fixtures.

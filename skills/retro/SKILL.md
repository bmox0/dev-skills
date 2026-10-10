---
name: retro
description: Propose environment changes after a merged plan — a check, a standards line, a pointer — each paired with what it removes. Offered once by finish, or on demand; applies nothing.
---

# Retro

Read what the plan cost: the plan with its `## Human gate` page, the commits,
and where the session stalled or was corrected by the user. Then propose
changes to the environment, so the next plan does not pay the same cost.

## What a proposal can be

- **A mechanical mistake → a check that fails:** a test, a lint rule, a check
  in the project's scripts. It stops the mistake without anyone remembering it.
- **A judgement call → one standards line** in the project's AGENTS.md,
  CLAUDE.md or style skill, where the implementer reads it first and the
  reviewer cites it.
- **Missing knowledge → a pointer:** a path, a command, a line in the
  `## Environment` block.
- **A plugin problem → the same three kinds,** in the plugin.

A lesson written as a paragraph in a skill is not one of these. Known failure
modes go in a note for the human next to the entry, not into the prompt.

## Every addition names its removal

For each proposal, name what it removes or replaces: a rule it makes redundant,
a paragraph it makes stale, a check it supersedes. When nothing goes, say why in
one line. A change that raises a skill's word budget names what it cuts.

## What comes back

A short list, most useful first: what happened, the change, where it goes, and
what it removes. Nothing is applied. The user picks; applying a pick is ordinary
work.

Once per plan, never per phase, never in a loop.

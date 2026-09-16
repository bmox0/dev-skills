---
name: setup
description: Generates this plugin's five Codex roles under ~/.codex/agents from agents/*.md, so a Codex session can dispatch dev-skills-gate-a, dev-skills-gate-b, dev-skills-implementer, dev-skills-prototyper and dev-skills-test-writer as separate agents. Run once after installing the plugin in Codex, and again whenever agents/*.md or skills/tdd/SKILL.md changes.
disable-model-invocation: true
---

Codex's plugin manifest has no `agents` key, and its plugin loader ignores a
top-level `agents/` directory. Without this step, the five roles this plugin
dispatches by name simply do not exist in a Codex session — a run would fall
back to the orchestrator marking its own work. This skill turns `agents/*.md`
into `~/.codex/agents/dev-skills-<role>.toml`, once, and again whenever a role
or the test discipline it carries changes.

This is not a script to run blind. Walk the human through it.

## 1. Show what already exists

Look at `~/.codex/agents/` for any `dev-skills-*.toml` file already there. For
each one, read its first line:

- carries the ownership marker below — ours. The generator will refresh it
  if its recorded source file has changed since, and leave it alone
  otherwise.
  ```
  # dev-skills:generated source=... sha256=...
  ```
- anything else — not ours. The generator refuses to touch it and leaves it
  byte-identical. Tell the human this up front if you find one: that role
  will not be (re)created until they move the file aside themselves.

## 2. Show what is about to happen, and wait

Tell the human, plainly:

- which of the five roles (`dev-skills-gate-a`, `dev-skills-gate-b`,
  `dev-skills-implementer`, `dev-skills-prototyper`,
  `dev-skills-test-writer`) will be created fresh, which will be refreshed,
  and which are refused because an unmarked file already occupies that path;
- exactly where: `~/.codex/agents/`;
- that the implementer role's generated file is by far the largest of the
  five, because it carries the whole of `skills/tdd/SKILL.md` inline — Codex
  has no `Skill` tool, so a generated role cannot reach a skill at runtime,
  and the test discipline has to travel with it instead.

Wait for the human to agree before running anything.

## 3. Run the generator

```
skills/setup/scripts/install-codex-agents
```

It is idempotent and safe to re-run: it only ever writes a file it owns or
creates one fresh, only ever refuses a same-named file it does not own, and
only ever removes a file it owns whose source role no longer exists under
`agents/`. Report its output verbatim — every line it printed names one file
and what happened to it.

## 4. Tell them the session is stale

Codex builds its role catalog from session configuration; there is no reload.
**A fresh session is required before any of these roles exist to dispatch.**
Say this plainly, and do not imply the session they are in now can use them.

## For a maintainer of this repository

`skills/setup/scripts/generate-skill-metadata` is a different script, for a
different moment: it derives every skill directory's own
`agents/openai.yaml` (the Codex picker's display name and description, and
the invocation policy) from that skill's own `SKILL.md` frontmatter. It is
not part of the human-facing flow above — it is run once when a skill is
added or its frontmatter changes, and its output is committed alongside that
change.

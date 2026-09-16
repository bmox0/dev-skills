---
name: setup
description: Install or refresh dev-skills' five custom Codex agents under $CODEX_HOME/agents, or ~/.codex/agents when CODEX_HOME is unset. Use once after installing dev-skills in Codex and again after plugin updates.
disable-model-invocation: true
---

Codex does not load this plugin's top-level `agents/` directory. This setup step
turns those role definitions into standalone Codex agent files so the workflow
can dispatch the two gates, implementer, test writer, and prototyper separately.

Run the bundled
[`scripts/install-codex-agents`](scripts/install-codex-agents), resolving that
path relative to this `SKILL.md`, not from the user's project directory. The
explicit `$dev-skills:setup` invocation is the user's request to install these
files; do not add a second confirmation. The host may still require its normal
filesystem approval before writing outside the project.

The generator is idempotent and owns only files whose first line starts with:

```
# dev-skills:generated source=...
```

It creates or refreshes those files under `$CODEX_HOME/agents/`, falling back
to `~/.codex/agents/`. It refuses a same-named file without the ownership marker
and removes only owned files whose source role no longer exists. Report its
output verbatim. If it reports a refusal, name the conflicting path and stop;
the human must move or rename that file before retrying.

After a successful run, give exactly these remaining first-run actions:

1. Open `/hooks`, review the hooks supplied by `dev-skills`, and trust them.
2. Start a fresh Codex session. Codex loads custom agent files only when the
   session starts, so the current session cannot dispatch the new roles.

Mention that both actions should be repeated after an update only when Codex
shows changed hooks or this setup skill refreshed the agent files.

## For a maintainer of this repository

`skills/setup/scripts/generate-skill-metadata` is a different script, for a
different moment: it derives every skill directory's own
`agents/openai.yaml` (the Codex picker's display name and description, and
the invocation policy) from that skill's own `SKILL.md` frontmatter. It is
not part of the human-facing flow above — it is run once when a skill is
added or its frontmatter changes, and its output is committed alongside that
change.

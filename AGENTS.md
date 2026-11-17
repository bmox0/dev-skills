## Environment

**Build.** none
**Typecheck.** none
**Lint.** `scripts/check`
**Tests.** `scripts/test`
**Single test file.** `scripts/test <path>`
**Dev server.** none
**E2E.** none
**Language.** English
**Runtime.** a CLI invocation — `scripts/check`, `scripts/test`, `scripts/usage`, `skills/build/pipeline.py`
and `skills/browser-test/tab.mjs` are run directly from a shell, never through
a browser or a server
**Plugin off.** Claude Code: `claude --settings '{"enabledPlugins":{"dev-skills@dev-skills":false}}'`;
Codex: `codex -c 'plugins.dev-skills@dev-skills.enabled=false'`

## Executors

The current provider selects its own pair. Planning, coordination, the
first review of a range (including a small gate) and every judge use primary. Helpers, implementation,
E2E, fixes, rounds and rechecks use secondary. Provider and model names are
opaque identifiers; effort is optional. New runs snapshot every provider here.
Apply the selected model and effort explicitly to each dispatch; never infer
a role from an inherited model. Shared handoff and acceptance rules:
[SESSIONS.md](references/SESSIONS.md). Host adapters import shared rules.

```toml
[executors."GPT".primary]
model = "gpt-6.1-sol"
effort = "ultra"

[executors."GPT".secondary]
model = "gpt-6.1-sol"
effort = "high"

[executors."Qwen".primary]
model = "qwen4-max"
effort = "xhigh"

[executors."Qwen".secondary]
model = "qwen4-max"
effort = "high"

[executors."Claude".primary]
model = "claude-opus-5-5"
effort = "xhigh"

[executors."Claude".secondary]
model = "claude-sonnet-5-5"
effort = "medium"
```

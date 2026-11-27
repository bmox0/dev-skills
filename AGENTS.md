## Environment

**Build.** none
**Typecheck.** none
**Lint.** `scripts/check`
**Tests.** `scripts/test`
**Single test file.** `scripts/test <path>`
**Dev server.** none
**E2E.** explicitly selected native host checks; default tests use fixtures
**Dependencies.** Bash, Python 3.11+, Node, Git and standard shell tools; AI clients are optional
**Language.** English
**Runtime.** a CLI invocation — `scripts/check`, `scripts/test`, `scripts/usage`, `workflow/build/pipeline.py`
and `workflow/browser-test/tab.mjs` are run directly from a shell, never through
a browser or a server

## Executors

The current provider selects its own pair. Planning, coordination, the
first review of a range (including a small gate) and every judge use primary. Helpers, implementation,
E2E, fixes, rounds and rechecks use secondary. Provider and model names are
opaque identifiers and effort is optional. A task records only the initiating
provider's pair. Other providers add their own pair when they join.
Apply the selected model and effort explicitly to each dispatch; never infer
a role from an inherited model. Shared handoff and acceptance rules:
[SESSIONS.md](references/SESSIONS.md). Host adapters import shared rules.

```toml
[executors."GPT".primary]
model = "gpt-6.2-astra"
effort = "high"

[executors."GPT".secondary]
model = "gpt-6.2-sol"
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

<!-- runweld:begin -->

Start or resume work with `runweld next`.

<!-- runweld:end -->

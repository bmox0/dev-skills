## Environment

**Build.** none
**Typecheck.** none
**Lint.** `scripts/check`
**Tests.** `scripts/test`
**Phase checks.** `scripts/check`
**Full checks.** `scripts/check`, `scripts/test`
**Required checks.** `scripts/check`, `scripts/test`
**CI workflow.** `.github/workflows/ci.yml`
**CI checks.** `scripts/check`, `scripts/test`
**Worktree setup.** none
**Single test file.** `scripts/test <path>`
**Dev server.** none
**E2E.** explicitly selected native host checks; default tests use fixtures
**Dependencies.** Bash, Python 3.11+, Node, Git and standard shell tools; AI clients are optional
**Language.** English
**Runtime.** a CLI invocation — `scripts/check`, `scripts/test`, `scripts/usage`, `workflow/build/pipeline.py`
and `workflow/browser-test/tab.mjs` are run directly from a shell, never through
a browser or a server

## Executors

Confirm both roles in checkout onboarding. Planning, coordination, the first
review of a range (including a small gate) and every judge use primary. Helpers,
implementation, E2E, fixes, rounds and rechecks use secondary. Provider and model
names are opaque identifiers and effort is optional. A task records each role
independently. Read both from `runweld executor show PLAN`. Apply the selected
settings explicitly to each dispatch.
[SESSIONS.md](references/SESSIONS.md) holds the shared handoff and acceptance rules.

<!-- runweld:begin -->

Start or resume work with `runweld next`.

<!-- runweld:end -->

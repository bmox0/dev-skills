## Environment

**Build.** none
**Typecheck.** none
**Lint.** `scripts/check`
**Tests.** `scripts/test`
**Single test file.** `scripts/test <path>`
**Dev server.** none
**E2E.** none
**Runtime.** a CLI invocation — `scripts/check`, `scripts/test`, `scripts/usage`
and `skills/browser-test/tab.mjs` are run directly from a shell, never through
a browser or a server
**Plugin off.** `claude --settings '{"enabledPlugins":{"dev-skills@dev-skills":false}}'`

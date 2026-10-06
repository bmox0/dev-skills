## Environment

**Build.** none
**Typecheck.** none
**Lint.** `scripts/check`
**Tests.** `scripts/test`
**Single test file.** `scripts/test <path>`
**Dev server.** none
**E2E.** native plugin discovery with a local marketplace config override
**Runtime.** CLI commands; Node for `skills/browser-test/tab.mjs`

The repository contains the plugin's source. Use its maintainer checks;
loading the installed dev-skills pipeline while editing it runs the workflow
twice. Disable that plugin for this task with
`codex -c 'plugins."dev-skills@dev-skills".enabled=false'`.

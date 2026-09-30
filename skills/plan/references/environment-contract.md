# The project's commands

A plan's Checks names the commands each phase runs, the full commands run after
all phases, and how e2e drives the system. They come from one block in the
project's `CLAUDE.md`, stated once so that no plan has to discover them:

```markdown
## Environment

**Build.** `<command>` — or: none
**Typecheck.** `<command>` — or: none
**Lint.** `<command>` — or: none
**Tests.** `<command that runs the suite>` — or: none, this project has no test framework
**Single test file.** `<command> <path>`
**Dev server.** `<command>`, serves on `<url>`
**E2E.** `<command>` — or: none
**Runtime.** <how the observable behaviour is driven here: a browser, a request,
the simulator, a CLI invocation>
```

State facts, not prohibitions. "none, this project has no test framework" is a
fact and it is worth a line.

When the block is missing, find the commands in the project's manifests and
scripts, write them into Checks, and offer the user the block for `CLAUDE.md`.

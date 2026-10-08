# The project's commands

A plan's Checks names the commands each phase runs, the full commands run after
all phases, and how e2e drives the system. They come from one block in the
project's `AGENTS.md` or `CLAUDE.md`, stated once so that no plan has to
discover them:

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
**Access.** <how e2e signs in: the account, its roles, where its credentials
live (an env var, `.env.local`, the keychain), where a one-time code comes
from> — or: none
**Devices.** <what e2e runs on, and what it leaves alone> — or: any
```

State facts, not prohibitions. "none, this project has no test framework" is a
fact and it is worth a line. Access names where a credential lives, never the
credential: the file is committed.

When the block is missing, find the commands in the project's manifests and
scripts, write them into Checks, and offer the user the block for the file the
project keeps its rules in; with neither, `AGENTS.md`. Both hosts read
`AGENTS.md`; Claude Code skips it when a `CLAUDE.md` sits beside it, unless
that file imports it with `@AGENTS.md`.

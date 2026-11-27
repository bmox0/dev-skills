# The project's commands

A plan's Checks names the commands each phase runs, the full commands run after
all phases, and how e2e drives the system. Plan and verify read the run file.
For standalone `runweld`, checkout checks come from `.runweld/config.toml`.
`runweld onboard` previews commands from the project's `AGENTS.md` environment
block and other project sources:

```markdown
## Environment

**Build.** `<command>` — or: none
**Typecheck.** `<command>` — or: none
**Lint.** `<command>` — or: none
**Tests.** `<command that runs the suite>` — or: none, this project has no test framework
**Phase checks.** `<command to run for each phase>`
**Full checks.** `<command to run at the full gate>`
**Required checks.** `<mandatory command>`
**CI workflow.** `<path to designated GitHub Actions workflow>`
**CI checks.** `<mandatory command named by the designated workflow>`
**Worktree setup.** `<command to prepare a worktree>` — or: none
**Single test file.** `<command> <path>`
**Dev server.** `<command>`, serves on `<url>`
**E2E.** `<command>` — or: none
**Language.** <the language the project's documents are written in>
**Runtime.** <how the observable behaviour is driven here: a browser, a request,
the simulator, a CLI invocation>
**Access.** <how e2e signs in: the account, its roles, where its credentials
live (an env var, `.env.local`, the keychain), where a one-time code comes
from> — or: none
**Devices.** <what e2e runs on, and what it leaves alone> — or: any
```

Language applies to plans and specs. If it is missing, read `docs/spec/` first,
then `docs/`. If neither supplies the language, ask once in chat. Offer only
the Language line unless the project has no Environment block.

State facts, not prohibitions. "none, this project has no test framework" is a
fact and it is worth a line. Access names where a credential lives, never the
credential: the file is committed.

When the block is missing, find the commands in the project's manifests and
scripts, write them into Checks, and offer the human the block for the file the
project keeps its shared rules in: `AGENTS.md`. A host adapter such as
`CLAUDE.md` imports it with `@AGENTS.md`; it does not duplicate the rules.

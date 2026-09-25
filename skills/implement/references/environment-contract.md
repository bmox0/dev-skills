# The environment contract

How this project runs, stated once in its `CLAUDE.md` so that no builder,
reviewer or tester has to discover it by looking around.

## Shape

```markdown
## Environment

**Build.** `<command>`
**Typecheck.** `<command>` — or: none
**Lint.** `<command>` — or: none
**Tests.** `<command that runs the suite>` — or: none, this project has no test framework
**Single test file.** `<command> <path>`
**Dev server.** `<command>`, serves on `<url>`
**E2E.** `<command>` — or: none
**Runtime.** <how the observable behaviour is driven here: a browser, a request,
a simulator build, a CLI invocation>

**bootstrap.** `<commands to run in a fresh working tree>`
**link.** `<untracked paths to symlink from the main checkout>`
**Tracker.** <where units are mirrored as tasks: Daily, GitHub issues, Linear> — or omit
```

State facts, not prohibitions. "none, this project has no test framework" is a
fact and it is worth a line.

## `bootstrap` and `link`

A fresh worktree has no installed dependencies and none of the untracked local
files the project needs. `bootstrap` is what to run in it so it builds and
starts; `link` names the untracked paths symlinked from the main checkout
(`.env*` by default). `.ai-workflow` is linked too when the main checkout has one.

`preflight --worktree` runs both. When either is missing it reports it; ask the
user once and record the answer here, so the next worktree does not ask.

## `Tracker` and `main.`

`Tracker` names where the epic's units are mirrored as tasks; the skills say
"the tracker" and read the name from here.

`git-guard` refuses a commit on the default branch. A project that commits there
on purpose adds one line to the block: `**main.** direct`.

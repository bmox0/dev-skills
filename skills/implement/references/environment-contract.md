# The environment contract

How this project is run. Every actor in a run needs some of it, and none of them
should be discovering it by looking around: a reviewer that does not know what
the project offers infers a conventional one and goes hunting — a repo with no
test framework gets `npm test` attempted at it, a branch with a screen gets a
browser launched. That is not misbehaviour, it is a gap being filled.

Two parts, different in kind:

| | Where it lives | Who writes it |
|---|---|---|
| **Permanent** — how the project runs at all | `CLAUDE.md` | the human, once, prompted by preflight |
| **One-off** — what gets clicked through for *this* task | the plan's *final-gate scenarios*, which project its approved test cases | the planner, from cases the human approved |

Only the permanent part is described here.

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
**Mutation.** `<command that mutates production code deterministically>` — or: none
**Runtime.** <how the observable behaviour is driven here: a browser, a request,
a simulator build, a CLI invocation>

**bootstrap.** `<commands to run in a fresh working tree>`
**link.** `<untracked paths to symlink from the main checkout>`
```

State facts, not prohibitions. A fact lets an actor plan; a prohibition only
tells it what to abandon after it has already planned. "none, this project has
no test framework" is a fact and it is worth a line.

## `bootstrap` and `link`

A fresh working tree does not run. It has no installed dependencies and none of
the untracked local files the project needs. Without these two fields, both
gates that need a live system — `dev-skills:gate-b` and the human's acceptance —
walk into a tree that cannot start, and they walk into it *after* all the code
is written.

**`bootstrap`** — what to run in a new tree so it builds and starts: install
dependencies, generate clients, run migrations, warm a cache. Whatever the
README tells a new contributor to do, minus the parts that only matter once.

**`link`** — untracked paths symlinked from the main checkout rather than
recreated. `.env*` by default; add anything else the project needs and git does
not carry. The mechanism is the one already used for `.ai-workflow`:

```bash
ln -s "$MAIN_CHECKOUT/<path>" "$WORKTREE/<path>"
```

## When a field is missing

`dev-skills:implement`'s preflight checks that the tree actually starts. If `bootstrap`
or `link` is absent, it **stops and asks — once** — and records the answer in
`CLAUDE.md` before continuing.

Not a guess: a guessed bootstrap fails somewhere in the middle and leaves a tree
that is half-prepared. Not a skip either: skipping moves the failure to the
runtime gate, which is the most expensive place in the run to discover that
nothing starts.

Asking once is the point of writing it down. The second run in this repository
does not ask.

## `Mutation`

How this repository mutates its own production code deterministically, so
that a check can watch a named test fail and then watch it pass again.
`none` is the expected answer in most repositories, and it is a fact worth a
line, not a gap.

A run never installs a mutation tool, and no actor treats the field's
absence as a problem.

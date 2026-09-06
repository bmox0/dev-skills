## Environment

**Build.** none
**Typecheck.** none
**Lint.** none
**Tests.** `scripts/test`
**Single test file.** `scripts/test <path>`
**Dev server.** none
**E2E.** none
**Mutation.** none — `scripts/test --mutations` replays recorded rows, it does not generate mutants over changed files
**Runtime.** a CLI invocation — every script under `skills/*/scripts/` is run
directly from a shell, never through a browser or a server

**bootstrap.** none — the tree runs as checked out
**link.** `.ai-workflow` from the main checkout

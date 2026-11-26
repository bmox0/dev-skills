# Root Cause Tracing

Bugs often surface deep in the call stack — the instinct is to fix where the
error appears, but that treats a symptom. Trace backward through the call
chain to the original trigger, then fix there.

## When to use

- The error happens deep in execution, not at the entry point.
- The stack trace shows a long call chain.
- It's unclear where invalid data originated.
- It's unclear which test or code path triggers the problem.

## The tracing process

1. **Observe the symptom** — what actually failed, and where.
2. **Find the immediate cause** — the line of code that directly causes it.
3. **Ask what called this** — walk up one caller at a time.
4. **Keep tracing up**, asking what value was passed at each level, until you
   reach the point where the bad value first appears.
5. **Fix at that source**, not at the point where it happened to surface.

## Adding stack traces

When manual tracing stalls, instrument before the operation, not after it
fails: log the relevant values (directory, cwd, environment) and
`new Error().stack` to capture the full call chain. In tests, use
`console.error()` rather than a logger, since a logger may be suppressed;
then run the suite and grep for the debug line, and read the stack for the
test name and line number that triggered it.

## Finding which test causes pollution

When something leaks across tests but the source is unclear, run the test
files one at a time and check for the pollution after each — the first file
that leaves it behind is the polluter.

## Key principle

Never fix just where the error appears. Trace back to the original trigger,
fix there, and once found, add validation at each layer the bad value passed
through so the bug becomes structurally impossible
([defense-in-depth.md](defense-in-depth.md)).

# The E2E gate

How `dev-skills:build` checks a plan's branch before the user sees it. The gate
checks what the user will not see by trying the app: data, sync, errors, races,
the code. Looks and feel are the user's, at the human gate.

## The level

The plan's Checks names it; the user's "go" approved it.

| Level | When | The gate |
|---|---|---|
| small | looks, copy, layout in one place; no logic | the full checks; the reviewer on Sonnet; no e2e: every Done use case is `you check` |
| normal | logic inside the feature's own code | the full checks; the reviewer; e2e over Done |
| wide | data, storage, sync, security, concurrency, shared code, migrations | as normal, plus e2e over the Done of the merged plans in `.ai-workflow/plans/` whose territories the diff touches |

Before the gate, read `git diff --stat <base>..HEAD`. Files outside the plan's
territories, or anything the wide row names, raise the level to what the diff
reaches; say so in a line on the gate page. The level never goes down.

## The pass

1. A worker runs the plan's full checks and returns only what failed. Red is a
   finding.
2. At once: `dev-skills:reviewer` over `<base>..HEAD` with the plan and the
   checks' result, and, above small, a worker driving through
   `dev-skills:verify` the Done use cases not marked `you check`.
3. One list: red checks, Defects, use cases failed, or not reached because of
   the code. One new implementer fixes all of it. A use case not reached for the
   environment goes on the gate page with what it needs; Conventions and
   Observations go folded to the code review, and only the user moves one into
   the notes.
4. A targeted re-check: a worker's full checks, then at once the reviewer on
   Sonnet over the fix's commits only and a fresh worker on the use cases that
   failed or the fix touched.

## When it stops

- A re-check runs only on a new commit or a changed environment; with neither,
  the last result stands.
- A finding that survives its fix gets no second fix: it goes under Open on the
  gate page.
- What the re-check finds new, a regression of the fix, gets a second fix and
  its re-check. Two fixes at most: Fix 1 and Fix 2, none for a third.

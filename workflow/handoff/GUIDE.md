---
name: handoff
description: Write this session down as a document a new context continues from — the work, or the thinking. Use when the work moves to another context mid-way, not as a plan.
---

# Handing a session over

The next context has none of this conversation; what you write is everything it
gets. Writing it is not the moment to finish the work: do not fix, build or
commit while you write.

Work nobody has started gets a plan (`runweld plan`), not a handoff.

## Ask once, then write

Ask, in one turn, only what the request left open:

1. Does the new context carry the **work** forward or the **thinking**? Which
   entry does it start from (`runweld bug`, `runweld grill`,
   `runweld build`, plain conversation)?
2. A file, or text in the chat?

## Write from what this session holds

No `git`, no `grep`, no file reads, no subagents: the value is the layer that
exists only in this conversation, and this is usually the session with no room
left. A fact you are not sure of is written as uncertain, never omitted and
never asserted.

## Always

- **The goal**, in one sentence.
- **The repository**, as an absolute path. Not the branch: it goes stale first.
- **What is decided, and why.** A decision without its reason gets reopened.
- **Out of scope**, and the constraints someone would break on the first edit.

## Carrying the work

- What is done, and what shows it: the passing test, the commit, the output.
- What is left.
- The paths that matter, and the commands to run and check it.
- **Approaches tried and abandoned.**
- Anything in the tree that is not a deliverable: instrumentation, scratch
  files, edits the human is making in parallel.
- What is running or logged in, as of this writing.

## Carrying the thinking

- Where the decision tree stands: asked, answered, untouched.
- **What the human rejected, and why.**
- What the human confirmed, kept apart from what is only your suggestion.
- The terms that settled.

## What earns a place

- **Receipts:** `path:line`, a commit, a command for every checkable claim.
- **Absolute paths** for anything outside the repository.
- **Links, not copies,** of plans, epics and ADRs.
- **No secrets.**
- **The entry** the new context starts from, named.

## Handing it over

**To a file:** Write beside the plan, or use the
[project handoff directory](../../references/WORKFLOW-PATHS.md) without one.
Name it `YYYY-MM-DD-<name>.md`. Give the human its path.

**To the chat:** the whole document in one fenced block, with nothing around
it; anything outside the fence gets copied with it.

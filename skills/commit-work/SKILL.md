---
name: commit-work
description: "Create high-quality git commits: review/stage intended changes, split into logical commits, and write clear commit messages (including Conventional Commits). Use when the user asks to commit, craft a commit message, stage changes, or split work into multiple commits."
---

# Commit work

## Goal
Make commits that are easy to review and safe to ship:
- only intended changes are included
- commits are logically scoped (split when needed)
- messages are short, plain, and say why — not what the diff already shows

## Non-negotiables (a PreToolUse hook enforces these — a violating `git commit` is blocked)
- **Conventional Commits** subject: `type(scope): summary`.
- **No** `Co-Authored-By`, no "Generated with Claude Code" footnote, no `Claude-Session:` trailer.
- **Never** `git add .` / `git add -A` — stage intentionally (`git add -p` or explicit paths).

## Inputs to ask for (if missing)
- Single commit or multiple commits? (If unsure: default to multiple small commits when there are unrelated changes.)
- Commit style: Conventional Commits are required.
- Any rules: max subject length, required scopes.

## Workflow (checklist)
1) Inspect the working tree before staging
   - `git status`
   - `git diff` (unstaged)
   - If many changes: `git diff --stat`
2) Decide commit boundaries (split if needed)
   - Split by: feature vs refactor, backend vs frontend, formatting vs logic, tests vs prod code, dependency bumps vs behavior changes.
   - If changes are mixed in one file, plan to use patch staging.
3) Stage only what belongs in the next commit
   - Prefer patch staging for mixed changes: `git add -p`
   - To unstage a hunk/file: `git restore --staged -p` or `git restore --staged <path>`
4) Review what will actually be committed
   - `git diff --cached`
   - Sanity checks:
     - no secrets or tokens
     - no accidental debug logging
     - no unrelated formatting churn
5) Describe the staged change in 1-2 sentences (before writing the message)
   - "What changed?" + "Why?"
   - If you cannot describe it cleanly, the commit is probably too big or mixed; go back to step 2.
6) Write the message — compact, complete, plain

   ```text
   <type>(<scope>): <summary>

   <Why it changed, plus anything the diff cannot show.>
   ```

   **Budget.** Subject ≤ 72 chars, imperative, no trailing period. A body is
   optional — write one only when the subject leaves a real question open.
   When you do: one paragraph, 2-4 sentences, wrapped at 72 columns. Add a
   second short paragraph only for a genuinely separate fact (a caveat, a side
   effect, a follow-up). Past ~80 words the commit is usually too big — go back
   to step 2 and split it. Compact is the target, not terse: keep every fact a
   reviewer needs, drop every word they do not.

   **Each line must earn its place.** Keep: the reason, the symptom it fixes,
   the constraint that forced this shape, a consequence a reader would miss,
   the exact error message if there was one. Cut: anything the diff already
   shows, file-by-file lists, "This commit …", the subject restated in longer
   words, and praise for your own change ("cleaner", "more robust", "much
   better").

   **Simple programming English.** Write for a reader at B1 English. Short
   sentences, one idea each, active voice. Use plain verbs — use, add, remove,
   fix, keep, drop, break, run, call, move, rename — and plain joiners — so,
   but, because, then. Do **not** reach for: leverage, utilize, facilitate,
   mitigate, surface (as a verb), subsequently, thereby, whilst, albeit, hence,
   aforementioned, myriad, plethora, obviate, expedite. Technical terms stay
   exact: race condition, debounce, idempotent, symlink, backpressure are
   precise, not fancy. No metaphors, no marketing adjectives (seamless, robust,
   comprehensive, streamlined, powerful).

   - Breaking change: `!` in the header and/or a `BREAKING CHANGE:` footer.
   - Prefer an editor for multi-line messages: `git commit -v`
   - Word swaps and good/bad pairs: `references/commit-message-template.md`
7) Run the smallest relevant verification
   - Run the repo's fastest meaningful check (unit tests, lint, or build) before moving on.
8) Repeat for the next commit until the working tree is clean

## Deliverable
Provide:
- the final commit message(s)
- a short summary per commit (what/why)
- the commands used to stage/review (at minimum: `git diff --cached`, plus any tests run)

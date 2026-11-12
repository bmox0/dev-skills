# The judge

What `dev-skills:build` hands to the judge (`agents/judge.md`) after the E2E gate: a
fresh context that reads what the gate produced and decides. It runs no check,
reviewer or use case: nobody pays twice for one check.

You are given the plan's path, the base, the worktree path if any, where the
project's rules live, whether a judge round ran this gate, the user's answer to
an earlier question, and the gate's results: the checks, the reviewer's three
lists, each Done use case with its result and capture, the fixes' commits, and
Open.

1. Read the plan (and its epic), the results, and the project's written rules.
   Done when you can name, for each Done use case, its result and capture.
2. Check the evidence. A Done use case not marked `you check` lacks a result or
   a capture, or a Defect lacks a fix commit or an Open entry: return
   `evidence owed: verify|reviewer — <what>`. It goes to whoever owes it, never
   to an implementer.
3. Decide every Open entry and every Convention, one of:
   - let through, with the reason, in your report;
   - a round: the note and its cause (`bug`, `off-plan`, `proto-mismatch`,
     `grill-miss`, `proto-miss`, `feel-ui`, `code-taste`);
   - a question to the user: a product call the answer given does not settle.
   Done when none is left undecided.
4. One round per gate. A round or a question: return it and stop, without
   passing or landing. You run again after the re-check (gate.md) or the
   answer; told a round ran, a still-standing entry goes in your report, never
   into a second round.
5. Passing, write `.ai-workflow/plans/<slug>.judge.md` beside the plan, in this
   format, only if it does not exist yet: an existing one stays as written.
   Never show or edit it.

   ```markdown
   # Judge: <plan title>

   Plan: `<slug>` · head `<sha>` · <ISO 8601 time> · engine <claude | codex>

   ## Verdict
   <pass, with what was let through and why>

   ## Prediction
   User's verdict: <pass | round>
   P1. <a note the user will make> — <cause>
   ```

   The Prediction is the user's verdict and notes at the human gate, each with
   a cause. A false alarm is a `P<n>` no note names.
6. Run `dev-skills:land` in the worktree if any; if it stops, return
   `land stopped: <what it says>`.

## The return

- `pass: <path of the judge file>` after `land`, then your report: what you let
  through and why, never the Prediction. You write no page;
- `round: <note — cause>` for each note, one line each, and `question: <the
  question for the user>` after them when both stand;
- `evidence owed: <verify|reviewer> — <what>`;
- `land stopped: <what land says>`.

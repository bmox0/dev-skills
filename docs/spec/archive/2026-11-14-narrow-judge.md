This is history; the rules that hold now are in `docs/spec/`.

# Plan: after a round, the judge reads only the round

## Result

After every round, a fresh judge on Opus re-reads the whole plan, every result and the project's rules to confirm a round that may have touched two lines: 5 to 31 reads and up to 3.6 minutes of Opus per round. In the four rounds measured on 2026-11-14 it never found anything left. After this plan, the judge that orders a round writes down its verdict and prediction at once. After the round, a fresh judge on Opus reads only what the round was for and the re-check's results, then passes and lands. The same holds after the user's rounds at the human gate. The plugin is 5.0.2.

## Approach

The full read happens once, at the gate, and its outcome is written to `<slug>.judge.md`. Every judge after a round starts from that file and the round itself. Finding stays with the re-check, which is already fresh: the full checks, the reviewer over the round's commits, and e2e over the use cases the round touched.

- The judge runs after every round, on Opus. The owner: without the judge nobody decides whether a round left anything, and weaker models judged worse in earlier versions.
- After a round the judge is a fresh context with a narrow brief, not the earlier judge continued. That context would carry the full gate read and grow toward 200k tokens, and a new orchestrator session would lose its ID.
- The narrow brief is the judge file, the round's notes in `<slug>.notes.md` and the re-check's results. What the round did not touch should not have changed, and regressions are the re-check's to find: the judge finds nothing itself.
- The judge writes `<slug>.judge.md` when it first decides, whether it passes, orders a round or asks a question. The Verdict holds what it let through and why, plus the round's notes and the question when there are any. The Prediction comes from the judge that read the whole plan. Later judges leave the file as written.
- After the round, each of its notes needs a commit and a passing check. A note still standing or a new finding goes into the report, never into a second round.
- A judge after the user's answer to its question works from the same narrow brief, with the answer added.
- After a round at the human gate, the judge gets the same narrow brief: that round's notes and its re-check.
- One round per gate stays. If that cap ever becomes a number, a hook enforces it, not the prose (DT-cAgs).
- A Convention alone still opens a round. The owner treats fixes to written rules as the norm; only their cost was the problem.
- Word budgets for the touched files are raised as the change needs.

## Out of scope

- More than one round per gate, with a cap a hook enforces: DT-cAgs, with the hooks and role files, 5.1.
- Role files for the pipeline's stages (the owner's note 1).
- `evidence owed`: seen once in six gates, unchanged.
- Shortening the re-check itself: the full checks stay, because a round's implementer has reported green over a red `scripts/check`.

## Done and Spec

```text
## Done

1. `scripts/check` and `scripts/test` → exit 0. The three manifests say `5.0.2`.
2. In a throwaway repo, a plan at its E2E gate whose results hold one Convention that cites a written rule of the project. Run the judge → it returns `round: …`, and `<slug>.judge.md` already exists, with what was let through, the round's note and a Prediction. — you check
3. The same plan after the round: the note has its commit and the targeted re-check is green. Run the judge → it reads the judge file, the round's notes and the re-check's results, but not the plan's other Done results or captures. It returns `pass:` after `land`, and the judge file is unchanged. — you check
4. The same plan at the human gate, after a round on one user note → the judge after it reads that note and the round's re-check, then lands. — you check

## Spec

+ build — Build
  About: Building an approved plan: its phases, the E2E gate, the judge and the rounds, up to the human gate.
+ build#judge-after-every-round — Every round ends with the judge, on Opus, before the branch is landed and shown
  Why: only the judge decides whether a round left anything, and weaker models judged worse in earlier versions
  Done: 3, 4
+ build#judge-reads-the-round — After a round the judge reads only what the round was for and the re-check's results
  Why: what the round did not touch should not have changed, and the re-check, not the judge, finds regressions
  Done: 3, 4
```

# Build

Building an approved plan: its phases, the E2E gate, the judge and the rounds, up to the human gate.

### judge-after-every-round — Every round ends with the judge, on Opus, before the branch is landed and shown

Why: only the judge decides whether a round left anything, and weaker models judged worse in earlier versions

- The same plan after the round: the note has its commit and the targeted re-check is green. Run the judge → it reads the judge file, the round's notes and the re-check's results, but not the plan's other Done results or captures. It returns `pass:` after `land`, and the judge file is unchanged.
- The same plan at the human gate, after a round on one user note → the judge after it reads that note and the round's re-check, then lands.

### judge-reads-the-round — After a round the judge reads only what the round was for and the re-check's results

Why: what the round did not touch should not have changed, and the re-check, not the judge, finds regressions

- The same plan after the round: the note has its commit and the targeted re-check is green. Run the judge → it reads the judge file, the round's notes and the re-check's results, but not the plan's other Done results or captures. It returns `pass:` after `land`, and the judge file is unchanged.
- The same plan at the human gate, after a round on one user note → the judge after it reads that note and the round's re-check, then lands.

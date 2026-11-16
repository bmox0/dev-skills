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

### state-through-commands — After approval a plan's state changes only through the CLI, and a write refuses while the plan file differs from its last render

Why: one writer per fact; a hand edit would vanish at the next render

- Under a throwaway epic, run `build start --base <tag>` → the branch starts at the tag, and Status reads `building` with the tag's SHA. The epic's row reads `building`, and `status` shows phase 1 as ready.
- Edit the Status line by hand, then run `phase start 1` → refused, naming the line and its command, and `status` still prints, showing the drift. Instead, edit a Done item and run `approve` → the plan is recompiled and every status is kept.

### act-with-a-reason — An agent may act against a fact the CLI reports, with a reason the CLI records for the human gate

Why: code states facts, agents keep the judgment

- Phase 1 commits one path inside its territory and one outside, leaves one staged, and records its report. `phase done 1` → exit 1, naming both, and the phase stays `in progress`. Grant the outside path, commit the staged one and record the report again → `phase done 1` marks it `done` and prints phase 2 as ready.
- Run `phase start 3` before phase 2 is done → refused; with `--note` → started, and `status` shows the note. Run `phase start 1` on the done phase with a note → back to `in progress`, with the note and HEAD's SHA.

### phase-done-checked — A phase is done once its reported commits are on the branch, inside its territory or grants, with nothing of its territory left uncommitted or staged

Why: the check sits in the command the orchestrator calls anyway

- Phase 1 commits one path inside its territory and one outside, leaves one staged, and records its report. `phase done 1` → exit 1, naming both, and the phase stays `in progress`. Grant the outside path, commit the staged one and record the report again → `phase done 1` marks it `done` and prints phase 2 as ready.

### base-is-named — The base is the ref the orchestrator names; the CLI never picks one

Why: in real runs the base is almost never the default branch

- Under a throwaway epic, run `build start --base <tag>` → the branch starts at the tag, and Status reads `building` with the tag's SHA. The epic's row reads `building`, and `status` shows phase 1 as ready.

### epic-row-follows — Under an epic, the plan's row shows the plan's status after every change

Why: the row was forgotten in 3 of 5 runs

- Under a throwaway epic, run `build start --base <tag>` → the branch starts at the tag, and Status reads `building` with the tag's SHA. The epic's row reads `building`, and `status` shows phase 1 as ready.

### pre-5-1-adopted — A plan without state is adopted by `approve` as its file stands; no other command but `spec` and `run` runs on it

Why: no migration step to remember, and a plan mid-build goes on where it is; the run file is written and checked before the plan has state

- Take a pre-5.1 plan at `building` with phase 1 `done` and no JSON, and run `phase start 2` → refused, with a fix naming `approve`. Run `approve` → phase 1 is still `done`, and phase 2 is ready.

### brief-carries-spec — An implementer's brief lists every `## Spec` entry of the plan with its ID and Done items

Why: tests carry the rule's ID, which lives only in the plan until `spec write`; a run lost a judge round to it

- Run `brief implementer 2` on a plan with three `## Spec` entries → the file holds `[checks].phase`, every `[run]` key as written with the keychain pointer unresolved, each entry's ID, statement and Done items, and one `Territory:` line.
